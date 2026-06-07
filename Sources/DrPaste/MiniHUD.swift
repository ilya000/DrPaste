//
//  MiniHUD.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Mini HUD — the small floating progress indicator that pops up near the
//  cursor whenever an action runs without the Big HUD being visible.
//  Two entry points: (1) direct-trigger per-action hotkeys (quick tap of
//  ⌥⌘<letter>), and (2) the deferred-paste handoff in commitBigHUD when
//  the user releases ⌥⌘ while an AI action is still streaming — the
//  Big HUD chrome hides, MiniHUD takes over as the in-flight indicator,
//  and the paste fires when the stream completes. Shows action title +
//  spinner; for AI actions also surfaces provider · model · elapsed
//  seconds. The X button cancels (and, in the deferred-paste case,
//  cancels the underlying streaming task).
//
//  Counterpart: BigHUD.swift — the press-and-hold browser panel.
//

import AppKit
import SwiftUI

/// Mutable view state for the mini progress HUD. Lives across show / hide
/// calls so SwiftUI can keep redrawing while a tick timer pushes `elapsed`
/// updates without rebuilding the hosting view.
@MainActor
final class MiniHUDState: ObservableObject {
    @Published var label: String = ""
    @Published var inflight: AIInflight? = nil
    @Published var elapsed: TimeInterval = 0
    /// True once the underlying task has completed. The View
    /// switches the spinner row for a "✓ Done · X.Xs" green
    /// confirmation so the user knows the call finished BEFORE
    /// the panel disappears + the result lands in their target
    /// app. Without this the elapsed counter just ticks until
    /// hide() and the user can't tell whether 5 s in is "still
    /// waiting" or "almost there".
    @Published var completed: Bool = false
    /// #A69 — non-nil while showing the explicit failure surface.
    /// Replaces the spinner + provider line with a red ✕ icon, a
    /// one-line reason, and an optional recovery action button.
    /// Auto-dismissed by `MiniHUDController.showFailure` after 4 s
    /// (longer than the success "Done" pill so the reason is
    /// actually readable), or by the X button.
    @Published var failure: MiniHUDFailure? = nil
    /// #A12 — non-nil while showing a decorative copy/cut/append content
    /// preview (no spinner, no X). `badge` labels it ("Copied").
    @Published var preview: MiniHUDPreview? = nil
    @Published var badge: String = ""
    /// #A12 — ⌥⌘S append preview: the session-track dot colour (cyan = files,
    /// red = text / rich) shown in the badge, plus a flag that swaps the footer
    /// for the dot legend.
    @Published var badgeDot: Color? = nil
    @Published var isAppendPreview: Bool = false
}

/// #A12 — content payload for the decorative copy-hold MiniHUD preview.
enum MiniHUDPreview {
    case text(String)
    case rich(NSAttributedString)   // rich text — formatting + embedded images
    case image(NSImage)
    case files([String])    // absolute paths
}

/// View-model for the MiniHUD failure state. Keeps reason text + a
/// single optional recovery affordance (title + closure) so the view
/// doesn't need to know about specific failure kinds.
struct MiniHUDFailure {
    /// Short reason ("Network error", "Image too large", etc.).
    /// Two-line wrap at most — keeps the panel from growing.
    let reason: String
    /// Optional recovery affordance — e.g. "Open Settings" for a
    /// missing key, "Open Welcome" for an AX-permissions issue.
    /// nil hides the button row.
    let recoveryTitle: String?
    let recoveryAction: (() -> Void)?
}

@MainActor
final class MiniHUDController {
    static let shared = MiniHUDController()

    private var panel: NSPanel?
    private let state = MiniHUDState()
    private var tickTimer: Timer?
    /// Closure fired ONLY when the user dismisses the HUD via the X button.
    /// Programmatic `hide()` (e.g. after the action completes) does NOT call
    /// it. Used by the deferred-paste path in AppDelegate to cancel an
    /// in-flight AI task + clear `pendingDeferredPasteApp` when the user
    /// changes their mind mid-stream.
    private var onCancelHandler: (() -> Void)?

    /// Incremented every `show()`. Callers can capture the token at show
    /// time and pass it to `hideIfOwner(_:)` so a defensive cleanup path
    /// (a cancelled task that wants to take down "its" MiniHUD) doesn't
    /// accidentally hide a *different* MiniHUD that a later show()
    /// replaced it with.
    private var generation: UInt64 = 0
    /// The token returned by the most recent `show()` call. Caller uses
    /// it with `hideIfOwner(_:)`.
    typealias ShowToken = UInt64

    private init() {}

    /// True while the panel is on screen (orderFront'd, not orderOut'd).
    /// Used by region-capture arm guards to avoid stacking a second
    /// floating overlay on top of an active MiniHUD — without this
    /// guard, a fast direct-trigger fire followed by bare ⌥⌘ held alone
    /// would produce two unrelated DrPaste surfaces on screen at once.
    var isVisible: Bool { panel?.isVisible == true }

    /// Show progress HUD with a label and an optional AI inflight descriptor.
    /// Idempotent — calling while visible updates the label / inflight in
    /// place. When `inflight` is provided, a 10 Hz timer drives the elapsed
    /// counter until `hide()` is called.
    ///
    /// `onCancel`, if provided, is invoked when the user clicks the X button.
    /// It is NOT called when the HUD is dismissed programmatically via
    /// `hide()` — that path is reserved for "action completed normally".
    @discardableResult
    func show(label: String, inflight: AIInflight? = nil, onCancel: (() -> Void)? = nil) -> ShowToken {
        generation &+= 1
        let token = generation
        state.label = label
        state.inflight = inflight
        state.elapsed = 0
        state.completed = false
        onCancelHandler = onCancel
        startTickIfNeeded(inflight: inflight)
        if panel == nil { buildPanel() }
        guard let panel = panel else { return token }
        // Rebuild hosting view only on first show so the @StateObject inside
        // the view tree keeps its identity across label updates.
        if panel.contentView == nil || !(panel.contentView is NSHostingView<MiniHUDView>) {
            panel.contentView = NSHostingView(rootView: MiniHUDView(
                state: state,
                onClose: { [weak self] in self?.userDismiss() },
                onPreviewHeight: { [weak self] h in self?.resizePreviewToContent(h) }
            ))
        }
        positionNearCursor(panel)
        panel.orderFrontRegardless()
        return token
    }

    /// #A12 — show a DECORATIVE content preview (copy-hold gesture). No
    /// spinner, no tick timer, no X button, non-draggable: the ⌥⌘ gesture is
    /// the only commit/cancel surface (release keeps, Esc reverts). Idempotent.
    @discardableResult
    func showPreview(badge: String, preview: MiniHUDPreview) -> ShowToken {
        generation &+= 1
        let token = generation
        stopTick()
        state.label = ""
        state.inflight = nil
        state.completed = false
        state.failure = nil
        state.badge = badge
        state.preview = preview
        onCancelHandler = nil
        autoDismissTask?.cancel()
        autoDismissTask = nil
        if panel == nil { buildPanel() }
        guard let panel = panel else { return token }
        if panel.contentView == nil || !(panel.contentView is NSHostingView<MiniHUDView>) {
            panel.contentView = NSHostingView(rootView: MiniHUDView(
                state: state,
                onClose: { [weak self] in self?.userDismiss() },
                onPreviewHeight: { [weak self] h in self?.resizePreviewToContent(h) }
            ))
        }
        // Decorative: the gesture drives dismissal, so don't let the user drag
        // it around (and it can't steal focus).
        panel.isMovableByWindowBackground = false
        positionNearCursor(panel)
        panel.orderFrontRegardless()
        return token
    }

    /// #A12 — ⌥⌘S append preview: show the accumulating clipboard composite so
    /// the user watches it GROW with each append, plus the session-track dot and
    /// a legend explaining cyan vs red. Auto-dismisses after a short window,
    /// re-armed on every append. Decorative (no X, non-draggable).
    @discardableResult
    func showAppendPreview(filesMode: Bool, preview: MiniHUDPreview, badge: String) -> Bool {
        generation &+= 1
        stopTick()
        state.label = ""
        state.inflight = nil
        state.completed = false
        state.failure = nil
        state.preview = preview
        state.badge = badge
        state.badgeDot = filesMode ? Color(nsColor: .systemCyan) : Color(nsColor: .systemRed)
        state.isAppendPreview = true
        onCancelHandler = nil
        if panel == nil { buildPanel() }
        guard let panel = panel else { return false }
        if panel.contentView == nil || !(panel.contentView is NSHostingView<MiniHUDView>) {
            panel.contentView = NSHostingView(rootView: MiniHUDView(
                state: state,
                onClose: { [weak self] in self?.userDismiss() },
                onPreviewHeight: { [weak self] h in self?.resizePreviewToContent(h) }
            ))
        }
        panel.isMovableByWindowBackground = false
        positionNearCursor(panel)
        panel.orderFrontRegardless()
        // Primary dismiss is ⌥⌘ release (hideIfAppendPreview) so it behaves like
        // the copy preview. This long timer is only a safety net for the rare
        // race where the async append finishes after ⌥⌘ was already released.
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
        return true
    }

    /// #A12 — hide the panel only if it's currently the ⌥⌘S append preview.
    /// Called on ⌥⌘ release so the append preview disappears like the copy one.
    func hideIfAppendPreview() {
        if state.isAppendPreview { hide() }
    }

    /// Hide the panel only if `token` matches the latest `show()` call.
    /// Defensive cleanup path for tasks that captured a token at show
    /// time and want to take down "their" MiniHUD on a cancellation
    /// branch without accidentally killing a later show() that
    /// replaced theirs.
    func hideIfOwner(_ token: ShowToken) {
        guard token == generation else { return }
        hide()
    }

    /// Hide HUD immediately and stop the elapsed-tick timer. Used by the
    /// completion path — does NOT invoke `onCancelHandler` because the
    /// underlying action ran to completion (or was cancelled elsewhere).
    /// #A12 — true while the promotion (copy-hold → BigHUD) dismiss animation
    /// is in flight; a stray `hide()` during it is ignored so the animation
    /// finishes and tears the panel down itself.
    private var isAnimatingPromotion = false

    /// #A12 — animate the MiniHUD into the BigHUD: a quick fade-out + slight
    /// scale-up so the C→V transition reads as the mini expanding into the big,
    /// rather than a hard cut. Self-contained — runs on the panel, then tears it
    /// down and restores it for the next show.
    func animateDismissForPromotion() {
        guard let panel = panel, panel.isVisible, !isAnimatingPromotion else { hide(); return }
        isAnimatingPromotion = true
        let original = panel.frame
        let grown = original.insetBy(dx: -original.width * 0.07, dy: -original.height * 0.07)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(grown, display: true)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isAnimatingPromotion = false
            self.tearDown()
            panel.setFrame(original, display: false)
            panel.alphaValue = 1
        })
    }

    func hide() {
        // Don't interrupt the promotion animation — it tears the panel down on
        // completion.
        guard !isAnimatingPromotion else { return }
        tearDown()
    }

    private func tearDown() {
        stopTick()
        state.inflight = nil
        state.completed = false
        state.failure = nil           // #A69 — clear failure on hide
        state.preview = nil           // #A12 — clear preview on hide
        state.badge = ""
        state.badgeDot = nil
        state.isAppendPreview = false
        // Restore default draggability for the next AI/progress show().
        panel?.isMovableByWindowBackground = true
        onCancelHandler = nil
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panel?.orderOut(nil)
    }

    /// #A69 — Show MiniHUD in the explicit failure state. Replaces
    /// whatever was on screen with a red ✕ + reason + optional
    /// recovery button. Auto-dismissed after 4 s (long enough to
    /// read a two-line reason) unless the user clicks the X or
    /// the recovery button first.
    ///
    /// Used by `actionHotkeyDidFire` failure path so direct-trigger
    /// AI / image action failures no longer disappear silently after
    /// the failure sound — the user sees *what* went wrong without
    /// having to re-run the action in BigHUD.
    @discardableResult
    func showFailure(label: String,
                     reason: String,
                     recoveryTitle: String? = nil,
                     recoveryAction: (() -> Void)? = nil) -> ShowToken {
        generation &+= 1
        let token = generation
        state.label = label
        state.inflight = nil
        state.elapsed = 0
        state.completed = false
        state.failure = MiniHUDFailure(reason: reason,
                                       recoveryTitle: recoveryTitle,
                                       recoveryAction: recoveryAction)
        stopTick()
        onCancelHandler = nil
        if panel == nil { buildPanel() }
        guard let panel = panel else { return token }
        if panel.contentView == nil || !(panel.contentView is NSHostingView<MiniHUDView>) {
            panel.contentView = NSHostingView(rootView: MiniHUDView(
                state: state,
                onClose: { [weak self] in self?.userDismiss() },
                onPreviewHeight: { [weak self] h in self?.resizePreviewToContent(h) }
            ))
        }
        positionNearCursor(panel)
        panel.orderFrontRegardless()
        autoDismissTask?.cancel()
        let tokenAtSchedule = token
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.hideIfOwner(tokenAtSchedule)
        }
        return token
    }

    /// Auto-dismiss task for the failure surface (#A69). Held so a
    /// later `show()` / `showFailure()` can cancel the prior timer
    /// before scheduling its own.
    private var autoDismissTask: Task<Void, Never>?

    /// Mark the underlying task as complete WITHOUT closing the
    /// panel. The View shows a green "✓ Done · X.Xs" pill in
    /// place of the spinner so the user sees the response landed
    /// before the panel disappears. Tick timer stops here so the
    /// final elapsed value is frozen at "actual completion time"
    /// rather than continuing to count until the caller's
    /// post-completion delay finishes. No-op when `token` is
    /// stale (later `show()` already replaced this HUD).
    func markCompleteIfOwner(_ token: ShowToken) {
        guard token == generation else { return }
        stopTick()
        state.completed = true
    }

    /// User clicked the X button. Fire the cancel handler first (so the
    /// caller can tear down its inflight state), then hide. Order matters:
    /// hide() clears `onCancelHandler`, so we must capture + call before
    /// hide runs.
    private func userDismiss() {
        let handler = onCancelHandler
        onCancelHandler = nil
        hide()
        handler?()
    }

    private func startTickIfNeeded(inflight: AIInflight?) {
        stopTick()
        guard let inflight = inflight else { return }
        let startedAt = inflight.startedAt
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.state.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.hidesOnDeactivate = false
        // Allow the user to drag the panel out of the way when a
        // long-running action is covering something they need to
        // see. Borderless NSPanels don't move by default — but
        // setting `isMovableByWindowBackground = true` lets them
        // pick up the panel anywhere on its content view and drag
        // it like a regular window. The X (cancel) button and any
        // future interactive controls stop the drag automatically
        // because hitTest on those subviews resolves first.
        p.isMovableByWindowBackground = true
        // Subscribe to Settings → Appearance so the MiniHUD re-skins
        // when the user switches themes, same as BigHUDPanel.
        p.subscribeToAppTheme()
        panel = p
    }

    /// Position the panel just above the mouse cursor on the screen
    /// containing it. Keeps the spinner inside the user's visual focus area
    /// so they don't have to glance across the display to confirm an
    /// action fired. 30 pt vertical gap so the cursor doesn't sit on top of
    /// the panel; clamped to the active screen's visibleFrame with an 8 pt
    /// margin so it never collides with the menu bar / Dock / display edge.
    /// #A12 — size the copy-hold preview panel to its content height (reported
    /// by the SwiftUI view), capped at ~2/3 of the screen so big text / images
    /// grow to fit and overflow scrolls. Only acts while a preview is showing
    /// and not mid-promotion-animation.
    private func resizePreviewToContent(_ contentHeight: CGFloat) {
        guard let panel = panel, state.preview != nil, !isAnimatingPromotion else { return }
        let cap = (NSScreen.main?.visibleFrame.height ?? 800) * 0.66
        let height = max(60, min(contentHeight, cap)).rounded()
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.size = NSSize(width: 320, height: height)
        panel.setFrame(frame, display: true)
        positionNearCursor(panel)
    }

    private func positionNearCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
        guard let screen = screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let offsetAboveCursor: CGFloat = 30
        let margin: CGFloat = 8

        var x = mouse.x - size.width / 2
        var y = mouse.y + offsetAboveCursor    // bottom-left origin → +y is up

        x = max(visible.minX + margin,
                min(x, visible.maxX - size.width - margin))
        y = max(visible.minY + margin,
                min(y, visible.maxY - size.height - margin))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// #A12 — carries the copy-hold preview's natural content height up to the
/// controller so it can size the panel adaptively.
private struct PreviewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MiniHUDView: View {
    @ObservedObject var state: MiniHUDState
    /// Observes Settings → Appearance so picking Vivid/Soft re-tints
    /// the mini panel background. Same accent reads it for the close
    /// button's hover state.
    @ObservedObject private var theme = ThemeManager.shared
    /// Closure invoked when the user dismisses the mini-window via the close
    /// button. Used as a safety net — even if the underlying action hangs
    /// (network stall, deadlocked URLSession, etc.) the user always has a
    /// one-click escape out of the floating panel.
    var onClose: () -> Void = {}
    /// #A12 — reports the preview's natural content height so the controller can
    /// size the panel (adaptive: short content → small window, big content →
    /// grows up to ~2/3 of the screen, then scrolls).
    var onPreviewHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        Group {
            if let preview = state.preview {
                previewBody(preview)
            } else {
                standardBody
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(width: 320, alignment: .leading)
            }
        }
        .background(
            ZStack {
                VisualEffect(material: .hudWindow, blending: .behindWindow)
                ThemeBackgroundFill(theme: theme.current)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.current.hudBorderColor,
                                  lineWidth: theme.current.hudBorderWidth)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Max preview content height — about 2/3 of the active screen.
    private var previewContentCap: CGFloat {
        max(120, (NSScreen.main?.visibleFrame.height ?? 800) * 0.66 - 96)
    }

    // #A12 — decorative copy/cut/append content preview. Self-sizing: the inner
    // VStack lays out at its natural height (reported up via onPreviewHeight);
    // the ScrollView caps it at ~2/3 screen so overflow scrolls.
    @ViewBuilder
    private func previewBody(_ preview: MiniHUDPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let dot = state.badgeDot {
                        Circle().fill(dot).frame(width: 9, height: 9)
                    } else {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(state.badge)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                previewContent(preview)
                if state.isAppendPreview {
                    appendDotLegend
                } else {
                    copyPreviewFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 320, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: PreviewHeightKey.self, value: g.size.height)
            })
        }
        .frame(width: 320)
        .onPreferenceChange(PreviewHeightKey.self) { onPreviewHeight($0) }
    }

    // ⌥⌘C copy-hold footer — keep / undo / chain into the full HUD.
    private var copyPreviewFooter: some View {
        HStack(spacing: 6) {
            Text("⌥⌘V")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                .foregroundStyle(Color.accentColor)
            Text("full HUD · release keep · Esc undo")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // ⌥⌘S append footer. The badge above already shows the CURRENT track's dot
    // + label (cyan = files, red = text/images), so only ONE label is shown —
    // a second dimmed legend just confused. This is a plain hint.
    private var appendDotLegend: some View {
        HStack(spacing: 6) {
            Text("⌥⌘S adds more")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: MiniHUDPreview) -> some View {
        switch preview {
        case .text(let s):
            // Grow with the text; the outer ScrollView caps + scrolls overflow.
            Text(s.isEmpty ? "(empty)" : s)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .rich(let attr):
            // RichTextPreviewView scrolls internally, so give it a bounded
            // height (it can't report a natural size) and let it grow up to the
            // screen cap.
            RichTextPreviewView(attributedString: attr, fontScale: 1.0)
                .frame(maxWidth: 288)
                .frame(height: min(previewContentCap, 320))
        case .image(let img):
            // Grow up to ~2/3 screen, keeping aspect ratio — but never upscale a
            // small image past its native size (it would look stretched/blurry).
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: min(288, max(1, img.size.width)),
                       maxHeight: min(previewContentCap, max(1, img.size.height)))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .files(let paths):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(paths.prefix(20).enumerated()), id: \.offset) { _, path in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable().frame(width: 14, height: 14)
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 12))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                if paths.count > 20 {
                    Text("+\(paths.count - 20) more")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: spinner / completion check / failure ✕ + action
            // title + close button. The spinner ↔ checkmark swap is the
            // primary "your AI call landed" signal; the ✕ (#A69) replaces
            // both when the action failed.
            HStack(spacing: 10) {
                if state.failure != nil {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 13, weight: .semibold))
                } else if state.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            // #A69 — failure reason + optional recovery button. The
            // reason line shares the same monospaced 11 pt style as
            // the inflight provider row so the panel stays visually
            // balanced when switching between the two surfaces.
            if let failure = state.failure {
                Text(failure.reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let title = failure.recoveryTitle,
                   let action = failure.recoveryAction {
                    HStack {
                        Spacer(minLength: 0)
                        Button(action: action) {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // AI inflight row — provider / model + ticking elapsed
            // counter. On completion the elapsed capsule turns
            // green and prefixes the value with "Done · " so the
            // final wall time is visibly framed as the completed
            // duration, not "still ticking".
            if let inflight = state.inflight {
                HStack(spacing: 8) {
                    Text("\(inflight.providerLabel) · \(inflight.modelName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if state.completed {
                        Text(String(format: "Done · %.1fs", state.elapsed))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    } else {
                        Text(String(format: "%.1fs", state.elapsed))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
            }
        }
    }
}
