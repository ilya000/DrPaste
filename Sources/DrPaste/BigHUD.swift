//
//  BigHUD.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Big HUD — the press-and-hold browser panel that opens on ⌥⌘V hold (or
//  via the summon hotkey in Limited Mode). Single implementation for both
//  gesture and summon modes (only the panel styleMask and the Limited
//  Mode banner differ). Renders an inline notice for ApplyOutcome.failed,
//  the source label under the header, AttributedString rich-text preview,
//  system accent colors, font scaling, dynamic visibleRowCount with
//  chevrons, and an auto-centering action row.
//
//  Counterpart: MiniHUD.swift — the small floating progress indicator
//  shown for direct-trigger hotkeys and for the deferred-paste handoff
//  when the user releases ⌥⌘ before an AI action finishes.
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - State

@MainActor
final class BigHUDState: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var itemIndex: Int = 0
    @Published var actionIndex: Int = 0
    @Published var actions: [ClipboardAction] = []

    /// Most recent action.apply result — drives the preview and the inline failure notice.
    @Published var outcome: ApplyOutcome? = nil
    @Published var isPreviewLoading: Bool = false
    /// When an async (AI) action is mid-flight, this carries the provider
    /// name, model identifier, action title, and start instant so the HUD can
    /// surface a transparent "Anthropic claude-sonnet-4-6 · 4.2s" status line
    /// instead of an opaque spinner. Reset to nil when the outcome arrives.
    @Published var aiInflight: AIInflight? = nil
    /// Tick counter driven by AppDelegate's timer while `aiInflight != nil`.
    /// Surfaced as the elapsed-time label so the user sees that the request
    /// is still progressing (rather than wondering whether DrPaste is frozen).
    @Published var aiElapsed: TimeInterval = 0

    /// In-HUD clip accumulator. First ⌥⌘S on the focused clip starts the
    /// accumulator — that clip becomes the "carrier" (anchor) and changes
    /// color. The user can then navigate up/down (↑/↓) to any other clip
    /// without losing the accumulator, and a subsequent ⌥⌘S on a different
    /// clip causes the previous carrier to disappear from the visible list
    /// (folded into `consumed`) and the newly focused row to become the new
    /// carrier showing the merged text — the accumulator "walks" through the
    /// list, eating clips as it goes. Commit pastes the merged text; close /
    /// cancel discards. Session-local and never persisted.
    @Published var accumulator: BigHUDClipAccumulator? = nil
    @Published var mode: BigHUDMode = .gesture
    @Published var engineLabel: String = ""

    /// When true, the HUD does NOT auto-close on commit. The user
    /// can run several commits in a row from the same HUD session
    /// (e.g. paste a series of action results into different fields).
    /// Per-session: resets to false on every fresh HUD open.
    /// Toggled via the pin icon in the HUD header (#A30).
    @Published var isPinned: Bool = false

    /// Content meta for the focused item — computed lazily via ContentMetaCache.
    @Published var contentMeta: String? = nil

    /// Optional provider that lets the HUD look up a user-customized title for
    /// an action (built-ins can be renamed). Wired in by AppDelegate.showBigHUD
    /// when the view is created.
    var actionTitleProvider: ((String, String) -> String)? = nil

    /// Optional provider telling the HUD whether an action is trait-gated —
    /// i.e. it is only in this list because its trait condition matched the
    /// focused clip. Such "conditional / surprise" chips get a yellow accent
    /// (same yellow as the Settings trait toggle) so they stand out: the user
    /// doesn't expect them and they appear/disappear with context. Wired in by
    /// AppDelegate.showBigHUD.
    var traitGatedProvider: ((String) -> Bool)? = nil

    /// #A13 — In-HUD inline search. nil = inactive; "" = active but
    /// empty (prompt visible, all rows still shown); non-empty = active
    /// + filter rows by `previewText` substring (case-insensitive).
    /// `F` opens, `esc` clears + closes the field. Survives across
    /// session navigation; reset on `openHUD`.
    @Published var searchQuery: String? = nil

    private static let fontScaleKey = "drpaste.hud.fontScale"
    @Published var fontScale: CGFloat = {
        let v = UserDefaults.standard.double(forKey: BigHUDState.fontScaleKey)
        return v == 0 ? 1.0 : CGFloat(v)
    }() {
        didSet { UserDefaults.standard.set(Double(fontScale), forKey: Self.fontScaleKey) }
    }

    func adjustFontScale(_ change: FontChange) {
        switch change {
        case .bigger:  fontScale = min(1.6, fontScale + 0.1)
        case .smaller: fontScale = max(0.7, fontScale - 0.1)
        case .reset:   fontScale = 1.0
        }
    }

    var currentItem: ClipboardItem? {
        guard itemIndex >= 0, itemIndex < items.count else { return nil }
        return items[itemIndex]
    }
    var currentAction: ClipboardAction? {
        guard actionIndex >= 0, actionIndex < actions.count else { return nil }
        return actions[actionIndex]
    }
}

// MARK: - HUD clip accumulator

/// Session-local "walking" accumulator for the in-HUD ⌥⌘S "merge clips"
/// feature. Model:
///   • `anchorIndex` — the row currently carrying the merged text. Rendered
///     with a distinctive (green) highlight so the user can see at a glance
///     which row is "the accumulator".
///   • `consumed`   — set of indices that have been folded into the merge
///     and are visually hidden from the HUD list (the rows literally
///     disappear so it's obvious they're inside the carrier now).
///   • `text`       — concatenated text (joined with "\n"), in absorption
///     order: the original anchor, then each subsequent target in the order
///     the user pressed ⌥⌘S on them.
struct BigHUDClipAccumulator {
    var consumed: Set<Int>
    var anchorIndex: Int
    /// Composite content built up by ⌥⌘S inside the HUD. Stored
    /// as `NSAttributedString` (not `String`) so rich text spans
    /// and inline images survive the merge — flattening to plain
    /// text would drop images and formatting, which is what the
    /// 0.35-series HUD accumulator regression was about.
    var attr: NSAttributedString
}

// MARK: - AI inflight descriptor

/// Required for Equatable on BigHUDClipAccumulator — NSAttributedString
/// is reference-typed and Equatable, but the synthesised Equatable on
/// the surrounding struct needs an explicit comparator. We compare by
/// length + raw RTFD blob bytes; both attributes and attachments survive
/// the round-trip.
extension BigHUDClipAccumulator {
    static func == (lhs: BigHUDClipAccumulator, rhs: BigHUDClipAccumulator) -> Bool {
        lhs.consumed == rhs.consumed
            && lhs.anchorIndex == rhs.anchorIndex
            && lhs.attr.isEqual(to: rhs.attr)
    }
}

/// Snapshot of an in-progress AI action. Surfaced in the HUD preview pane
/// while the network call is outstanding so the user sees which provider is
/// being talked to, on which model, and how long the wait has been so far.
/// Provider / model are resolved at request-start time from the AIAction's
/// configured providerID (or the user's default if the action follows it).
struct AIInflight: Equatable {
    let providerLabel: String   // e.g. "Anthropic"
    let modelName: String       // e.g. "claude-sonnet-4-6"
    let actionTitle: String     // e.g. "Translate to Spanish"
    let startedAt: Date
}

// MARK: - Panel

final class BigHUDPanel: NSPanel {
    private let allowsKey: Bool
    private static let cornerRadius: CGFloat = 18

    init(contentRect: NSRect, allowsKey: Bool) {
        self.allowsKey = allowsKey
        let style: NSWindow.StyleMask = allowsKey
            ? [.borderless, .titled, .fullSizeContentView]
            : [.borderless, .nonactivatingPanel]
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        // Subscribe to the app theme so picking Light/Dark/Vivid/Soft
        // in Settings re-skins the BigHUD without an app restart.
        self.subscribeToAppTheme()
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = !allowsKey
    }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    // Defensive corner radius: re-apply on every layout, recursively over
    // subviews (vibrant material owns its own layer). cornerCurve = .continuous
    // gives the Apple-style squircle.
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        applyRoundedCorners()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        applyRoundedCorners()
    }

    private func applyRoundedCorners() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.cornerRadius = Self.cornerRadius
        cv.layer?.cornerCurve = .continuous
        cv.layer?.masksToBounds = true
        applyRoundedCornersRecursive(cv)
    }

    private func applyRoundedCornersRecursive(_ view: NSView) {
        for sub in view.subviews {
            if sub.wantsLayer || sub.layer != nil {
                sub.layer?.cornerRadius = Self.cornerRadius
                sub.layer?.cornerCurve = .continuous
                sub.layer?.masksToBounds = true
            }
            applyRoundedCornersRecursive(sub)
        }
    }
}

// MARK: - acceptsFirstMouse host

final class BigHUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - HUD view

struct BigHUDView: View {
    @ObservedObject var state: BigHUDState
    /// Observes Settings → Appearance so picking Vivid/Soft re-tints
    /// the HUD background and re-pulls the accent color used by
    /// chips and selection rings.
    @ObservedObject private var theme = ThemeManager.shared
    let onPick: (Int, Int) -> Void               // (itemIdx, actionIdx) — refresh the preview
    let onCommit: () -> Void                      // release / Enter / dbl-click
    let onOpenAccessibility: () -> Void
    let onRecoveryAction: (RecoveryAction) -> Void
    let onClose: () -> Void                       // routed from the header close button

    @State private var hoveredItemID: UUID? = nil
    @State private var hoveredActionID: String? = nil

    /// Effective accent — theme override (Vivid orange / Soft lavender)
    /// or the system accent for Auto/Light/Dark.
    private var accent: Color {
        theme.current.accentColor ?? Color(nsColor: .controlAccentColor)
    }
    private func sz(_ base: CGFloat) -> CGFloat { base * state.fontScale }

    var body: some View {
        ZStack {
            // System VisualEffect blur (untouched for Auto/Light/Dark;
            // mostly hidden for Vivid/Soft by the gradient overlay).
            VisualEffect(material: .hudWindow, blending: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    // Theme-specific gradient on top of the system blur.
                    // Vivid: deep indigo→plum at ~85 % opacity (system
                    // blur barely visible underneath); Soft: warm
                    // cream→lavender at ~78 %. Auto/Light/Dark = clear.
                    ThemeBackgroundFill(theme: theme.current)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    // Border: hairline + neutral for Auto/Light/Dark;
                    // 1.5 pt accent-coloured frame for Vivid/Soft so
                    // the theme reads loud-and-clear at the edge.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.current.hudBorderColor,
                                lineWidth: theme.current.hudBorderWidth)
                )

            VStack(spacing: 8) {
                compactHeader
                Divider().opacity(0.3)
                content
                Divider().opacity(0.3)
                actionsBar
                if showTraitDebug {
                    traitDebugRow
                }
                footer
                if state.mode == .summon { limitedModeBanner }
            }
            .padding(14)
        }
        .frame(width: 720, height: state.mode == .summon ? 440 : 400)
    }

    // MARK: header — compact single row plus a close button

    private var compactHeader: some View {
        HStack(spacing: 6) {
            AppBrand.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: sz(16), height: sz(16))
            Text(AppBrand.name)
                .font(.system(size: sz(13), weight: .semibold))
            Text("·").foregroundStyle(.secondary)
            Text("\(state.itemIndex + 1)/\(max(state.items.count, 1))")
                .font(.system(size: sz(11), design: .monospaced))
                .foregroundStyle(.secondary)
            if let src = compactSourceLabel {
                Text("·").foregroundStyle(.secondary)
                Text(src)
                    .font(.system(size: sz(11)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let timestampLabel = compactTimestampLabel {
                Text("·").foregroundStyle(.secondary)
                Text(timestampLabel)
                    .font(.system(size: sz(11)))
                    .foregroundStyle(.tertiary)
                    .help(absoluteTimestampLabel ?? "")
            }
            Spacer()
            // The hotkey-engine kind ("tap" / "carbon") used to be surfaced
            // here as a small badge — that was internal dev info and was
            // confusing to users (especially "tap", which looked like "tab"
            // at small monospace sizes). Mode is already conveyed by the
            // footer key hint (release vs ⏎), so the badge has been removed.
            // Pin toggle (#A30). When pinned, commit (release ⌥⌘
            // in Gesture Mode / Enter in Limited Mode) does not
            // close the HUD — useful for chained pastes across
            // several target fields without re-opening the HUD
            // each time. Per-session: resets on every fresh HUD
            // open. Icon mirrors macOS conventions: `pin` for
            // unpinned (action available), `pin.fill` for pinned.
            Button {
                state.isPinned.toggle()
            } label: {
                Image(systemName: state.isPinned ? "pin.fill" : "pin")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: sz(13)))
                    .foregroundStyle(state.isPinned ? Color.accentColor : .secondary)
                    .rotationEffect(.degrees(state.isPinned ? 0 : 30))
            }
            .buttonStyle(.plain)
            .help(state.isPinned ? "Unpin — close HUD after next paste"
                                 : "Pin — keep HUD open across pastes")
            .accessibilityLabel(state.isPinned ? "Unpin HUD" : "Pin HUD")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: sz(14)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close DrPaste")
        }
    }

    /// Short form of the source: app + window title (truncated to 25 chars).
    private var compactSourceLabel: String? {
        guard let item = state.currentItem else { return nil }
        guard let app = item.sourceAppName ?? item.sourceBundleID?
                .components(separatedBy: ".").last?.capitalized else { return nil }
        if let title = item.sourceWindowTitle, !title.isEmpty {
            let trimmed = title.prefix(25)
            let suffix = title.count > 25 ? "…" : ""
            return "\(app) \"\(trimmed)\(suffix)\""
        }
        return app
    }

    /// Relative timestamp ("just now", "5m ago", "2h ago") for recent items,
    /// absolute date/time for older items (>1 day). Tooltip always shows the full date.
    private var compactTimestampLabel: String? {
        guard let item = state.currentItem else { return nil }
        let interval = Date().timeIntervalSince(item.createdAt)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 86400 * 7 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
        // Older than a week — show the exact date.
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: item.createdAt)
    }

    /// Full timestamp shown in the hover tooltip (always absolute).
    private var absoluteTimestampLabel: String? {
        guard let item = state.currentItem else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return "Copied \(formatter.string(from: item.createdAt))"
    }

    /// Content meta row — a small line with metadata about the focused item.
    /// Sits directly above the preview pane in the right column of the content area.
    private var contentMetaRow: some View {
        HStack(spacing: 0) {
            if let meta = state.contentMeta {
                Text(meta)
                    .font(.system(size: sz(10)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if state.currentItem != nil {
                Text("…")
                    .font(.system(size: sz(10)))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(height: sz(14))
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        if state.items.isEmpty {
            emptyHistoryOnboarding
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // #A59 — release-to-paste discoverability hint. Shows
                // until the user has visibly internalised the gesture
                // (5 successful commits in the current reset
                // generation), or re-shows once after a 90-day
                // dormancy gap. Only paints in Gesture mode — the
                // Limited mode banner already covers the gesture
                // story there.
                if state.mode == .gesture && ReleaseToPasteHint.shouldShow {
                    releaseToPasteHintRow
                }
                HStack(spacing: 12) {
                    historyColumn.frame(width: 260, alignment: .leading)
                    Divider().opacity(0.2)
                    VStack(alignment: .leading, spacing: 4) {
                        contentMetaRow                  // meta row above the preview pane
                        previewPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    // MARK: release-to-paste hint (#A59)

    /// Single-line discoverability strip surfacing the core gesture
    /// of the product. Quiet by design — secondary foreground,
    /// monospaced 10pt so it doesn't compete with the main content
    /// strip. Auto-fades from `ReleaseToPasteHint.shouldShow` once
    /// the user has visibly internalised the gesture.
    private var releaseToPasteHintRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.system(size: sz(9)))
                .foregroundStyle(.secondary)
            Text("hold ⌥⌘V to browse · release to paste · esc to cancel")
                .font(.system(size: sz(10), design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .onAppear {
            // Acknowledge stale-reshow inside .onAppear so the next
            // open after a 90-day dormancy gap sees `shouldShow ==
            // false` again until the counter is fresh.
            ReleaseToPasteHint.acknowledgeStaleReshow()
        }
    }

    // MARK: empty-history onboarding (#A61)

    /// Inline onboarding panel shown when `state.items.isEmpty`.
    /// Replaces the prior "History is empty" two-line placeholder with
    /// a brief explainer of what just happened + a concrete next step.
    /// Reached on first launch, after Factory Reset, and after the user
    /// manually clears history. The HUD's action bar is also hidden in
    /// this state (no actions apply to nothing) — release / esc just
    /// close without a failure sound (`hudCommit` early-outs when the
    /// items list is empty).
    private var emptyHistoryOnboarding: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: sz(36), weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Your clipboard history is empty")
                    .font(.system(size: sz(14), weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Copy something with ⌘C and try again — DrPaste will record it here.")
                    .font(.system(size: sz(11)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            HStack(spacing: 8) {
                keyChip("⌘C", label: "Copy")
                Text("•").foregroundStyle(.tertiary)
                keyChip("⌥⌘V", label: "Re-open")
                Text("•").foregroundStyle(.tertiary)
                keyChip("esc", label: "Close")
            }
            .font(.system(size: sz(10)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    /// Small chip used by the empty-history onboarding to surface a
    /// keyboard shortcut next to its meaning. Keeps the visual weight
    /// muted so the chips don't compete with the headline.
    private func keyChip(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: sz(10), weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.10)))
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: history

    /// Item indices that should appear in the list. Rows folded into the
    /// accumulator (consumed) are hidden so the carrier "swallowing" them is
    /// visible to the user.
    private var visibleIndices: [Int] {
        let consumed = state.accumulator?.consumed ?? []
        var base: [Int]
        if consumed.isEmpty {
            base = Array(state.items.indices)
        } else {
            base = state.items.indices.filter { !consumed.contains($0) }
        }
        // #A13 — apply substring filter when search is active and
        // non-empty. Case-insensitive; matches previewText only.
        // Image / files clips without a previewText filter out
        // unless their semantic name matches — keeps the list
        // sensible for mixed history.
        if let q = state.searchQuery, !q.isEmpty {
            let needle = q.lowercased()
            base = base.filter { idx in
                let item = state.items[idx]
                if let text = item.previewText,
                   text.lowercased().contains(needle) {
                    return true
                }
                return item.semantic.displayName.lowercased().contains(needle)
            }
        }
        return base
    }

    private var visibleRowCount: Int {
        let base = 11
        let v = Int(round(Double(base) / state.fontScale))
        return max(5, min(v, visibleIndices.count))
    }

    /// Window expressed as positions INTO `visibleIndices` (not raw item
    /// indices) so consumed rows never count toward the row budget.
    private var visibleWindow: (start: Int, end: Int) {
        let vis = visibleIndices
        let n = vis.count
        guard n > 0 else { return (0, 0) }
        let count = visibleRowCount
        let focusedPos = vis.firstIndex(of: state.itemIndex) ?? 0
        var start = focusedPos - count / 2
        start = max(0, min(start, max(0, n - count)))
        let end = min(start + count, n)
        return (start, end)
    }
    private var hasItemsAbove: Bool { visibleWindow.start > 0 }
    private var hasItemsBelow: Bool { visibleWindow.end < visibleIndices.count }

    private var historyColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasItemsAbove {
                HStack { Spacer(); Image(systemName: "chevron.compact.up")
                    .foregroundStyle(.secondary).opacity(0.7); Spacer() }
                    .frame(height: 10)
            } else {
                Color.clear.frame(height: 10)
            }

            let win = visibleWindow
            let vis = visibleIndices
            ForEach(win.start..<win.end, id: \.self) { pos in
                let idx = vis[pos]
                itemRow(state.items[idx], absoluteIdx: idx)
            }

            if hasItemsBelow {
                HStack { Spacer(); Image(systemName: "chevron.compact.down")
                    .foregroundStyle(.secondary).opacity(0.7); Spacer() }
                    .frame(height: 10)
            } else {
                Color.clear.frame(height: 10)
            }
            Spacer(minLength: 0)
        }
    }

    private func itemRow(_ item: ClipboardItem, absoluteIdx: Int) -> some View {
        let isActive = absoluteIdx == state.itemIndex
        let isHover = hoveredItemID == item.id
        // Accumulator carrier: the row currently holding the merged text.
        // Rendered in a distinctive green tint so it's never confused with
        // the standard accent-blue focus highlight.
        let isAnchor = state.accumulator?.anchorIndex == absoluteIdx
        let displayedText: String = {
            if isAnchor, let acc = state.accumulator {
                // Show merged content directly in the row so the user
                // sees the accumulator literally "live" at this
                // position. The accumulator stores NSAttributedString
                // now (for rich/image preservation), but the in-row
                // snippet stays single-line plain — strip Object
                // Replacement Characters (image attachments) so the
                // user doesn't see ￼ litter in the list.
                return String(acc.attr.string
                                .replacingOccurrences(of: "\u{FFFC}", with: "🖼")
                                .replacingOccurrences(of: "\n", with: " ⏎ ")
                                .prefix(80))
            }
            return snippet(item)
        }()
        let rowIcon: String = isAnchor ? "rectangle.stack.fill" : item.semantic.sfSymbol
        let anchorColor = Color.green
        return HStack(spacing: 6) {
            Image(systemName: rowIcon)
                .foregroundStyle(isAnchor ? anchorColor : .primary)
                .frame(width: sz(14))
            Text(displayedText)
                .lineLimit(1)
                .font(.system(size: sz(12), weight: isAnchor ? .semibold : .regular))
                .foregroundStyle(isActive || isAnchor ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isAnchor
                      ? anchorColor.opacity(isActive ? 0.32 : 0.22)
                      : (isActive
                         ? accent.opacity(0.22)
                         : (isHover ? Color.primary.opacity(0.06) : Color.clear)))
        )
        .overlay(alignment: .leading) {
            if isAnchor {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(anchorColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in hoveredItemID = hovering ? item.id : nil }
        .onTapGesture(count: 2) {
            onPick(absoluteIdx, state.actionIndex)
            onCommit()
        }
        .onTapGesture(count: 1) {
            onPick(absoluteIdx, state.actionIndex)
        }
    }

    private func snippet(_ item: ClipboardItem) -> String {
        switch item.semantic {
        case .image, .pdf:
            return item.previewText ?? item.semantic.displayName
        case .files:
            return item.previewText ?? "Files"
        default:
            return (item.previewText ?? "").prefix(80)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    // MARK: preview

    @ViewBuilder
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Failure notice on top when outcome is .failed.
            if case .failed(_, let reason, let recovery) = state.outcome {
                failureNotice(reason: reason, recovery: recovery)
            }
            if case .sideEffect(let desc, _) = state.outcome {
                sideEffectNotice(description: desc)
            }
            if case .alternativeCommit(_, let style) = state.outcome {
                alternativeCommitNotice(style: style)
            }

            if state.isPreviewLoading {
                aiLoadingPanel
            } else {
                previewContent
            }
        }
    }

    /// Loading state shown while an async (AI) action is awaiting a network
    /// response. Surfaces provider name, model, and elapsed seconds so the
    /// user can tell the wait is progress, not a hang. Falls back to the
    /// generic "processing…" copy for any non-AI async path.
    @ViewBuilder
    private var aiLoadingPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if let inflight = state.aiInflight {
                    Text("\(inflight.providerLabel) · \(inflight.modelName)")
                        .font(.system(size: sz(11), weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                } else {
                    Text("processing…")
                        .font(.system(size: sz(11)))
                        .foregroundStyle(.secondary)
                }
            }
            if state.aiInflight != nil {
                Text(String(format: "thinking… %.1fs", state.aiElapsed))
                    .font(.system(size: sz(10), design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            if let inflight = state.aiInflight {
                Text("Action: \(inflight.actionTitle)")
                    .font(.system(size: sz(10)))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewContent: some View {
        // Every outcome renders item content. Failed / sideEffect / alternativeCommit
        // show the original so the user sees what would actually be pasted.
        let item: ClipboardItem? = {
            switch state.outcome {
            case .preview(let i):                return i
            case .alternativeCommit(let i, _):   return i
            case .failed(let i, _, _):           return i
            case .sideEffect:                    return state.currentItem
            case .none:                           return state.currentItem
            }
        }()
        if let item = item { renderItem(item) }
    }

    @ViewBuilder
    private func renderItem(_ item: ClipboardItem) -> some View {
        switch item.semantic {
        case .text, .url, .email, .json, .code, .markdown, .table:
            ScrollView {
                Text(item.previewText ?? "")
                    .font(.system(size: sz(12), design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
                    .padding(.horizontal, 6)        // safeguard against corner-radius clipping
                    .padding(.vertical, 2)
            }
        case .richText:
            // RichTextPreviewView wraps its own NSScrollView; nesting it inside a
            // SwiftUI ScrollView collapses it to zero height because the parent
            // gives infinite height to a child that reports zero intrinsic size.
            richTextView(item)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        case .image, .pdf:
            ImagePreview(item: item)
                .padding(.horizontal, 6)
        case .files:
            // #A17 — show NSWorkspace icon next to each filename so
            // the user can tell folders / symlinks / regular files
            // apart visually. Folder = standard blue folder, symlinks
            // get the system arrow overlay automatically, regular
            // files get their UTI-resolved icon (.txt vs .pdf vs
            // .docx etc.). Falls back to a generic doc icon if
            // NSWorkspace can't resolve.
            VStack(alignment: .leading, spacing: 3) {
                if let urls = filesList(item) {
                    ForEach(urls, id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(nsImage: fileRowIcon(forPath: path))
                                .resizable()
                                .interpolation(.medium)
                                .frame(width: sz(16), height: sz(16))
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: sz(11), design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        case .unknown:
            VStack(alignment: .leading) {
                Text("Unknown content type")
                    .foregroundStyle(.secondary)
                Text(item.previewText ?? "")
                    .font(.system(size: sz(11), design: .monospaced))
            }
            .padding(.horizontal, 6)
        }
    }

    private func filesList(_ item: ClipboardItem) -> [String]? {
        guard item.semantic == .files else { return nil }
        let paths = clipFilePaths(item)
        return paths.isEmpty ? nil : paths
    }

    /// #A17 — Resolve the system icon for a file row in the HUD.
    /// Uses NSWorkspace which handles folders, symlinks (with arrow
    /// overlay), regular files (UTI-resolved), and gracefully
    /// degrades to a generic doc icon when the file no longer
    /// exists or sits behind a hardened sandbox boundary.
    private func fileRowIcon(forPath path: String) -> NSImage {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        let ws = NSWorkspace.shared
        if FileManager.default.fileExists(atPath: trimmed) {
            return ws.icon(forFile: trimmed)
        }
        // File doesn't exist (deleted between copy and display, or
        // sandboxed away). Fall back to a generic doc icon so we
        // don't render a blank slot.
        return NSImage(systemSymbolName: "doc",
                       accessibilityDescription: "Document")
            ?? ws.icon(for: .data)
    }

    @ViewBuilder
    private func richTextView(_ item: ClipboardItem) -> some View {
        if let attr = RichTextLoader.attributedString(from: item) {
            RichTextPreviewView(attributedString: attr, fontScale: state.fontScale)
        } else {
            Text(item.previewText ?? "").font(.system(size: sz(12)))
        }
    }

    // MARK: failure / side-effect / alternativeCommit notices

    private func failureNotice(reason: String, recovery: RecoveryAction?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: sz(11)))
            reasonText(reason, recovery: recovery)
                .font(.system(size: sz(11)))
                .foregroundStyle(.primary)
            Spacer()
            if let rec = recovery {
                Button(recoveryLabel(rec)) { onRecoveryAction(rec) }
                    .controlSize(.small)
                    .font(.system(size: sz(10)))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
        // Inline `drpaste://` links inside the reason (e.g. "Settings → AI")
        // route through the deep-link handler rather than NSWorkspace.
        .environment(\.openURL, OpenURLAction { url in
            let handled = (NSApp.delegate as? AppDelegate)?.openDeepLink(url) ?? false
            return handled ? .handled : .systemAction
        })
    }

    /// Render the failure reason, turning the recovery phrase into a tappable
    /// inline deep link when one is available — so "open Settings → AI" itself
    /// is clickable, not just the trailing button. Falls back to plain text
    /// when there's no deep-linkable recovery (the MiniHUD keeps the plain
    /// string, so we deliberately don't bake markup into the stored reason).
    @ViewBuilder
    private func reasonText(_ reason: String, recovery: RecoveryAction?) -> some View {
        if let rec = recovery,
           let phrase = deepLinkPhrase(for: rec),
           let url = deepLinkURL(for: rec),
           let attr = linkifiedReason(reason, phrase: phrase, url: url) {
            Text(attr)
        } else {
            Text(reason)
        }
    }

    /// Substring within a reason string that should become the link, per
    /// recovery kind. Returns nil for recoveries with no in-app destination.
    private func deepLinkPhrase(for rec: RecoveryAction) -> String? {
        switch rec {
        case .openProvidersConfig:       return "Settings → AI"
        case .openAccessibilitySettings: return nil   // routes to System Settings
        case .custom:                    return nil
        }
    }

    private func deepLinkURL(for rec: RecoveryAction) -> URL? {
        switch rec {
        case .openProvidersConfig:       return URL(string: "drpaste://settings/ai")
        case .openAccessibilitySettings: return nil
        case .custom:                    return nil
        }
    }

    /// Build an AttributedString from `reason` with `.link` applied to the
    /// first occurrence of `phrase`. Returns nil if the phrase isn't present
    /// (wording drifted) so the caller can fall back to plain text.
    private func linkifiedReason(_ reason: String, phrase: String, url: URL) -> AttributedString? {
        var attr = AttributedString(reason)
        guard let range = attr.range(of: phrase) else { return nil }
        attr[range].link = url
        attr[range].underlineStyle = .single
        return attr
    }

    private func recoveryLabel(_ rec: RecoveryAction) -> String {
        switch rec {
        case .openProvidersConfig:      return "Open AI Settings"
        case .openAccessibilitySettings: return "Open Accessibility"
        case .custom(let label, _):     return label
        }
    }

    private func sideEffectNotice(description: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(accent).font(.system(size: sz(11)))
            Text(description).font(.system(size: sz(11)))
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.10)))
    }

    private func alternativeCommitNotice(style: CommitStyle) -> some View {
        let label: String = {
            switch style {
            case .standardPaste: return ""
            case .typeSlowly(let d, _): return "Will type slowly (\(Int(d * 1000)) ms / char)"
            case .typeFast: return "Will type fast (50 ms / char)"
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: "keyboard").foregroundStyle(accent).font(.system(size: sz(11)))
            Text(label).font(.system(size: sz(11)))
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.10)))
    }

    // MARK: actions bar (scroll + autocenter + fade)

    private var actionsBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.actions.indices, id: \.self) { idx in
                        actionChip(idx).id(idx)
                    }
                }
                .padding(.horizontal, 4)
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .leading, endPoint: .trailing)
            )
            .onChange(of: state.actionIndex) { newIdx in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
        .frame(height: sz(30))
    }

    private func actionChip(_ idx: Int) -> some View {
        let a = state.actions[idx]
        let isActive = idx == state.actionIndex
        let isHover = hoveredActionID == a.id
        let title = state.actionTitleProvider?(a.id, a.title) ?? a.title
        // Conditional ("surprise") action — shown only because its trait
        // matched the clip. Same yellow as the Settings trait toggle.
        let traitGated = state.traitGatedProvider?(a.id) ?? false
        let traitYellow = Color(red: 1.0, green: 0.82, blue: 0.0)
        return HStack(spacing: 4) {
            if let badge = providerBadge(for: a) {
                // AI action — provider badge with brand color.
                // `isAvailable` flips to false when an image action's
                // resolved provider can't actually do image edits;
                // the badge renders grayscale + diagonal slash so
                // the user sees the mismatch before running.
                ProviderBadgeView(text: badge.label, color: badge.color,
                                  fontSize: sz(9), iconName: badge.icon,
                                  isAvailable: providerAvailable(for: a))
            } else {
                // Built-in or transformation — type icon
                Image(systemName: actionTypeIcon(for: a))
                    .font(.system(size: sz(10), weight: .medium))
                    .foregroundStyle(isActive ? Color.primary : .secondary)
            }
            Text(title)
                .font(.system(size: sz(11), weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : .secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            // #A63 — clip selection (history strip) keeps the solid
            // accent fill because clips ARE objects. Action selection
            // switches to a thinner accent outline + faint tint so it
            // reads as a "command" rather than another contained object
            // — disambiguates the two surfaces visually when both are
            // focused under release-to-paste.
            Capsule().fill(
                traitGated
                ? traitYellow.opacity(isActive ? 0.15 : (isHover ? 0.12 : 0.08))
                : (isActive
                   ? accent.opacity(0.10)
                   : (isHover ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06)))
            )
        )
        .overlay(
            // Trait-gated chips carry a yellow border at all times so they read
            // as "conditional" even when not selected; selection just thickens it.
            Capsule()
                .strokeBorder(
                    traitGated ? traitYellow.opacity(isActive ? 0.8 : 0.5)
                               : (isActive ? accent.opacity(0.95) : Color.clear),
                    lineWidth: isActive ? 1.5 : (traitGated ? 1.0 : 0)
                )
        )
        .contentShape(Capsule())
        .onHover { hovering in hoveredActionID = hovering ? a.id : nil }
        .onTapGesture(count: 2) {
            onPick(state.itemIndex, idx)
            onCommit()
        }
        .onTapGesture(count: 1) {
            onPick(state.itemIndex, idx)
        }
        // #A62 — right-click / Ctrl-click on an action chip surfaces
        // the two power-user routes that previously cost 5 clicks
        // through Settings: "Assign hotkey…" (opens the Edit Action
        // sheet at the action's hotkey field), "Open in Settings…"
        // (same sheet, neutral entry point). Inline-recorder popover
        // anchored to the chip itself is a follow-up polish item;
        // the Edit Action sheet is the canonical path today.
        .contextMenu {
            Button("Assign hotkey…") {
                (NSApp.delegate as? AppDelegate)?
                    .openActionEditorFromHUD(actionID: a.id, focusHotkey: true)
            }
            Button("Open in Settings…") {
                (NSApp.delegate as? AppDelegate)?
                    .openActionEditorFromHUD(actionID: a.id, focusHotkey: false)
            }
        }
    }

    /// SF Symbol icon for non-AI actions (built-in or transformation).
    private func actionTypeIcon(for action: ClipboardAction) -> String {
        if action.id.hasPrefix("user.transform.") {
            // Custom transformation — engine-derived icon if available
            if let desc = AIProviderRegistry.shared.config.providers.first(where: { $0.id == action.id }) {
                _ = desc  // placeholder — engines aren't on AIProviderRegistry
            }
            return "function"
        }
        return BuiltinActionIcons.iconName(for: action.id)
    }

    /// Provider badge for AI actions. Returns label, color, and SF Symbol.
    /// Resolves dynamically — actions with empty / nil providerID follow the current default.
    /// Handles both `AIAction` (text-in/text-out) and `AIImageAction`
    /// (image-in/image-out). Image-AI badges short-circuit to OpenAI
    /// because gpt-image-1 only lives there — the badge reflects the
    /// real routing target, not the chat default which may be a
    /// different provider.
    private func providerBadge(for action: ClipboardAction)
        -> (label: String, color: Color, icon: String)?
    {
        guard let resolved = resolveExecutorProvider(for: action) else {
            // Fallback chip when no provider qualifies — surfaces
            // "AI" generically so the row still parses as AI.
            return action is AIAction || action is AIImageAction || action is AITextToImageAction
                ? ("AI", Color.gray, "sparkle")
                : nil
        }
        return (resolved.providerKind.badgeLabel,
                badgeColor(for: resolved.providerKind),
                resolved.providerKind.iconName)
    }

    /// HUD-side adapter around `ProviderResolver`: every AI badge /
    /// availability indicator consumes the same resolved provider struct as
    /// Settings and the editor hints.
    private func resolveExecutorProvider(for action: ClipboardAction)
        -> ResolvedAIProvider?
    {
        let providerID: String?
        let operationKind: AIOperationKind
        if let ai = action as? AIAction {
            providerID = ai.providerID
            operationKind = .text
        } else if let ai = action as? AIImageAction {
            providerID = ai.providerID
            operationKind = .imageEdit
        } else if let ai = action as? AITextToImageAction {
            providerID = ai.providerID
            operationKind = .textToImage
        } else {
            return nil
        }
        let cfg = AIProviderRegistry.shared.config
        return ProviderResolver.resolve(
            nominalProviderID: providerID,
            operationKind: operationKind,
            config: cfg,
            hasKey: { id in
                ProviderResolver.runtimeHasCredential(providerID: id,
                                                      operationKind: operationKind,
                                                      config: cfg)
            }
        )
    }

    private func badgeColor(for kind: ProviderKind) -> Color {
        // Delegates to the canonical palette on `ProviderKind` so the HUD
        // chips, Settings provider list, and Settings action list all stay
        // in lockstep. Previously this returned a flat `.gray` for every
        // local provider, which made local-AI chips visually
        // indistinguishable from non-AI built-ins.
        kind.brandColor
    }

    /// Whether the action can actually execute right now — i.e.
    /// `resolveExecutorProvider` finds SOMETHING (enabled, right
    /// capability). Returns false only when nothing in the registry
    /// qualifies; the badge then renders in a disabled/slashed
    /// state so the user sees the problem before clicking. Local
    /// (non-AI) actions are always available.
    ///
    /// Using the same resolver as the badge guarantees that the
    /// slash overlay and the icon brand never disagree — if we
    /// have a working provider its icon shows in color, if we
    /// don't we show greyed with the slash.
    private func providerAvailable(for action: ClipboardAction) -> Bool {
        guard action is AIAction
                || action is AIImageAction
                || action is AITextToImageAction else { return true }
        return resolveExecutorProvider(for: action) != nil
    }

    // MARK: footer

    private var footer: some View {
        // S / Space work bare in BOTH modes: Gesture Mode has ⌥⌘ implicitly
        // held (releasing dismisses the HUD); Limited Mode accepts bare key
        // presses too because the HUD has no text-input scope and bare keys
        // remove a friction step. Zoom stays mode-aware — in Gesture Mode
        // ⌘ is already held so +/- alone works; in Limited Mode ⌘+/- is the
        // expected macOS convention.
        let gesture = state.mode == .gesture
        let zoomKey = gesture ? "+/-" : "⌘+/-"
        // Mode-specific legend:
        //
        //   Gesture Mode — ⌥⌘ are physically held the whole time
        //   the HUD is up, so every key the user can press is
        //   implicitly ⌥⌘+key. Putting "⌥⌘" in front of each chip
        //   is just noise — strip it. "Release pastes" isn't
        //   spelled out either; the user will discover it the
        //   first time they let go of ⌥⌘.
        //
        //   Limited Mode — no modifiers are held. ⏎ on its own
        //   pastes; the ⌥⌘ prefix is meaningful and stays on
        //   chords that need it.
        //
        // Either way the row stays one line at the HUD's default
        // width (the previous "⌥⌘C copy preview" / "⌥⌘⏎ paste &
        // keep" / "release paste" wording was wrapping). Spacing
        // tightened from 12 to 10 for the same reason.
        return HStack(spacing: 10) {
            keyHint("↑↓", "hist")
            keyHint("←→", "act")
            keyHint("⌫", "del")
            keyHint("S", "merge")
            if gesture {
                // ⌥⌘ implicitly held — bare letters fire as chords.
                // Label is "save" rather than "copy": semantically C
                // here promotes the current preview into the top of
                // clipboard history (and writes it back to the system
                // pasteboard). The word "copy" reads as system ⌘C
                // and confused users about what the key actually does
                // inside the HUD vs. outside.
                keyHint("C", "save")
                keyHint("⏎", "keep")
            } else {
                // Limited Mode — HUD is the key window, no modifiers
                // held. Local key monitor accepts both bare C and
                // ⌥⌘C for copy (S the same way) so the legend can
                // stay bare-key. ⏎ pastes-and-closes; paste-and-keep
                // is intentionally Gesture-Mode-only.
                keyHint("C", "save")
                keyHint("⏎", "paste")
            }
            // `cancel` is the accurate semantic — esc aborts the
            // commit, not just "closes the window". The HUD also
            // closes, but the user mental model is "cancel without
            // pasting", which is what the word communicates.
            keyHint("esc", "cancel")
            Spacer()
            keyHint(zoomKey, "\(Int(state.fontScale * 100))%")
        }
        .font(.system(size: sz(10), design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            Text(label)
        }
    }

    private var showTraitDebug: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.hudShowTraitDebug)
    }

    private var traitDebugRow: some View {
        let names = state.currentItem.map { ContextDetector.detect($0).activeNames } ?? []
        let text = names.isEmpty ? "traits: none" : "traits: \(names.joined(separator: ", "))"
        return HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.system(size: sz(9)))
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.0))
            Text(text)
                .font(.system(size: sz(9), design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .help(text)
    }

    // MARK: Limited Mode banner

    private var limitedModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited Mode")
                    .font(.system(size: sz(11), weight: .semibold))
                Text("Press Enter to paste. Enable Accessibility for release-to-paste gesture mode.")
                    .font(.system(size: sz(10)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings…") { onOpenAccessibility() }
                .controlSize(.small)
                .font(.system(size: sz(10)))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - VisualEffect

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .active
        v.isEmphasized = false
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material; nsView.blendingMode = blending
    }
}

// MARK: - Image preview

/// Provider badge — a small SF Symbol icon shown to the left of the title in
/// the action chip. Uses the provider's branded color. The `text` parameter
/// is kept for backward compatibility and is shown in the Settings tooltip.
///
/// `isAvailable == false` renders the badge in a grayscale / dimmed
/// "disabled" state with a strikethrough slash overlay — used when an
/// image-AI action's resolved provider can't actually do image edits
/// (e.g., the default chat provider is Anthropic and the user hasn't
/// configured an image-capable fallback, OR they explicitly picked a
/// non-image provider per-action). The icon signals "this won't work"
/// immediately without having to run the action and read the error.
struct ProviderBadgeView: View {
    let text: String
    let color: Color
    let fontSize: CGFloat
    var iconName: String = "sparkle"
    var isAvailable: Bool = true

    var body: some View {
        let effectiveColor: Color = isAvailable ? color : .secondary
        let bgOpacity: Double = isAvailable ? 0.18 : 0.10
        ZStack {
            Image(systemName: iconName)
                .font(.system(size: fontSize + 1, weight: .medium))
                .foregroundStyle(effectiveColor)
                .frame(width: fontSize + 4, height: fontSize + 4)
                .background(Circle().fill(effectiveColor.opacity(bgOpacity)))
                .opacity(isAvailable ? 1.0 : 0.55)
                .saturation(isAvailable ? 1.0 : 0.0)
            // Strikethrough slash when unavailable — drawn over the
            // icon at a slight rotation so it reads as "disabled /
            // not connected" without obscuring the provider glyph.
            if !isAvailable {
                Image(systemName: "line.diagonal")
                    .font(.system(size: fontSize + 4, weight: .heavy))
                    .foregroundStyle(.red)
                    .opacity(0.75)
            }
        }
        .help(isAvailable
              ? text
              : "\(text) — this provider can't run image edits. Pick OpenAI, Gemini, or OpenRouter in the action's provider field.")
    }
}

/// Image preview pane — thumbnail with size constraints and a dimensions label.
/// Never renders the full-size NSImage; uses the cached thumbnail (max 600 pt).
struct ImagePreview: View {
    let item: ClipboardItem

    /// Load via Data (not NSImage(contentsOf:)) to bypass the NSImage URL cache.
    /// This matters for transformed items (grayscale/invert/etc.) — a new file
    /// can have the same URL-like key and NSImage would otherwise return stale data.
    ///
    /// For .pdf items captured before the on-snapshot thumbnail render was
    /// added: if `previewImageRel` is missing, fall back to rendering the first
    /// page lazily here. Result is cached in imagesDir under a deterministic
    /// name keyed on the PDF blob path so subsequent renders are instant.
    private var loadedImage: NSImage? {
        if let rel = item.previewImageRel,
           let data = try? Data(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel)) {
            return NSImage(data: data)
        }
        if item.semantic == .pdf {
            return lazyPDFThumbnail()
        }
        return nil
    }

    private func lazyPDFThumbnail() -> NSImage? {
        guard let rel = item.representations["com.adobe.pdf"] else { return nil }
        let pdfURL = AppStorage.blobsDir.appendingPathComponent(rel)
        let cacheURL = AppStorage.imagesDir.appendingPathComponent(rel + ".thumb.png")
        // Hit the deterministic per-PDF cache first.
        if let data = try? Data(contentsOf: cacheURL), let img = NSImage(data: data) {
            return img
        }
        guard let pdfData = try? Data(contentsOf: pdfURL) else { return nil }
        return renderPDFInline(data: pdfData, cacheTo: cacheURL)
    }

    /// First-page render that writes the resulting PNG to `cacheURL` so
    /// subsequent loads short-circuit.
    private func renderPDFInline(data: Data, cacheTo cacheURL: URL) -> NSImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider),
              let page = doc.page(at: 1)
        else { return nil }
        let pageRect = page.getBoxRect(.cropBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }
        let maxSide: CGFloat = 600
        let scale = min(maxSide / pageRect.width, maxSide / pageRect.height, 2.0)
        let targetSize = CGSize(width: pageRect.width * scale,
                                height: pageRect.height * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil,
                                  width: Int(targetSize.width),
                                  height: Int(targetSize.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: bi)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pageRect.origin.x, y: -pageRect.origin.y)
        ctx.drawPDFPage(page)
        guard let cg = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: cacheURL)
        return NSImage(data: png)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let img = loadedImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Cap to the image's NATIVE size so a small image (e.g. a
                    // resize result) is shown 1:1 instead of being stretched up
                    // to fill the 480×280 pane.
                    .frame(maxWidth: min(480, max(1, img.size.width)),
                           maxHeight: min(280, max(1, img.size.height)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    // Force a fresh view identity whenever the underlying
                    // PNG file changes — image transformations (grayscale,
                    // invert, rotate, resize, compress, strip metadata)
                    // reuse the source item's UUID via saveImage's
                    // `var copy = originalItem`. If we keyed on `item.id`
                    // alone, SwiftUI would treat the transformed result as
                    // the same view as the original and skip the re-render,
                    // leaving the user staring at the pre-transformation
                    // image. previewImageRel is the unique PNG filename the
                    // transformation wrote, so it changes per result.
                    .id("\(item.id)-\(item.previewImageRel ?? "")")
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
