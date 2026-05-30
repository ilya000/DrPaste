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

    private init() {}

    /// Show progress HUD with a label and an optional AI inflight descriptor.
    /// Idempotent — calling while visible updates the label / inflight in
    /// place. When `inflight` is provided, a 10 Hz timer drives the elapsed
    /// counter until `hide()` is called.
    ///
    /// `onCancel`, if provided, is invoked when the user clicks the X button.
    /// It is NOT called when the HUD is dismissed programmatically via
    /// `hide()` — that path is reserved for "action completed normally".
    func show(label: String, inflight: AIInflight? = nil, onCancel: (() -> Void)? = nil) {
        state.label = label
        state.inflight = inflight
        state.elapsed = 0
        onCancelHandler = onCancel
        startTickIfNeeded(inflight: inflight)
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }
        // Rebuild hosting view only on first show so the @StateObject inside
        // the view tree keeps its identity across label updates.
        if panel.contentView == nil || !(panel.contentView is NSHostingView<MiniHUDView>) {
            panel.contentView = NSHostingView(rootView: MiniHUDView(
                state: state,
                onClose: { [weak self] in self?.userDismiss() }
            ))
        }
        positionNearCursor(panel)
        panel.orderFrontRegardless()
    }

    /// Hide HUD immediately and stop the elapsed-tick timer. Used by the
    /// completion path — does NOT invoke `onCancelHandler` because the
    /// underlying action ran to completion (or was cancelled elsewhere).
    func hide() {
        stopTick()
        state.inflight = nil
        onCancelHandler = nil
        panel?.orderOut(nil)
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
        panel = p
    }

    /// Position the panel just above the mouse cursor on the screen
    /// containing it. Keeps the spinner inside the user's visual focus area
    /// so they don't have to glance across the display to confirm an
    /// action fired. 30 pt vertical gap so the cursor doesn't sit on top of
    /// the panel; clamped to the active screen's visibleFrame with an 8 pt
    /// margin so it never collides with the menu bar / Dock / display edge.
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

struct MiniHUDView: View {
    @ObservedObject var state: MiniHUDState
    /// Closure invoked when the user dismisses the mini-window via the close
    /// button. Used as a safety net — even if the underlying action hangs
    /// (network stall, deadlocked URLSession, etc.) the user always has a
    /// one-click escape out of the floating panel.
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: spinner + action title + close button.
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
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
            // AI inflight row — provider / model + ticking elapsed counter.
            if let inflight = state.inflight {
                HStack(spacing: 8) {
                    Text("\(inflight.providerLabel) · \(inflight.modelName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1fs", state.elapsed))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow, blending: .behindWindow)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
