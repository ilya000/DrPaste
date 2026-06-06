//
//  ActionEditor.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Unified action editor — one dialog for three modes:
//  1. Built-in handler — pick a pre-made action and override metadata.
//  2. Transformation engine — regex / find / prepend / append / wrap / line filter.
//  3. AI prompt — pick a provider and write the prompt.
//
//  All modes share the same fields: title, hotkey, applicable types, test panel.
//

import SwiftUI
import AppKit

// MARK: - Window controller

/// Hosts ActionEditor inside a standalone NSWindow rather than as a SwiftUI
/// `.sheet`. Two reasons for the switch:
///   1. Sheets are attached to their parent window and can't be moved
///      independently — the user couldn't drag the editor by its title bar
///      to get it out of the way of the Settings window underneath.
///   2. Sheet content slides down from the parent's title bar and doesn't
///      know about the Dock. With a 720 pt-tall editor and a Settings
///      window positioned near the top of the screen, the OK/Cancel
///      footer landed behind the Dock and became unclickable.
///
/// A standalone titled NSWindow is draggable by its title bar like any
/// document window, and `clampToVisibleFrame` shifts the initial origin
/// upward if `.center()` would put the bottom edge underneath the Dock.
@MainActor
final class ActionEditorWindowController {
    /// Process-wide controller used by menu-bar / hotkey-triggered edits
    /// (see `main.swift`). The Settings window keeps its own instance for
    /// edits launched from the action list; both share the same windowing
    /// logic, just different owners.
    static let shared = ActionEditorWindowController()

    /// Multiple editor windows can be open simultaneously — opened
    /// either from the Settings list (one per Edit click on a
    /// different action) or from a Duplicate-button click inside an
    /// existing editor (which spawns a sibling window for the
    /// freshly-cloned action without closing the original). Keyed
    /// by `contextKey` so a second Edit click on the same action
    /// raises the existing window instead of stacking duplicates.
    private var windowsByKey: [String: NSWindow] = [:]
    private var delegatesByKey: [String: ActionEditorWindowDelegate] = [:]

    /// Open an editor window for `context`. If a window for the
    /// SAME context is already open, raise it instead of opening
    /// a second one (covers the "user clicked Edit twice" case).
    /// Distinct contexts open in their own windows.
    func show(context: ActionEditorContext,
              registry: ActionRegistry,
              onClose: @escaping () -> Void) {
        let key = Self.contextKey(for: context)
        if let existing = windowsByKey[key] {
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Title reflects whether we're creating or editing — small UX
        // touch, the title bar is the first thing the user reads.
        let title: String = {
            switch context {
            case .createNew:            return "Add Action"
            case .editBuiltin:          return "Edit Built-in Action"
            case .editTransformation:   return "Edit Transformation"
            case .editAI:               return "Edit AI Action"
            }
        }()

        // Wrap the SwiftUI editor so closing the editor tears down
        // ITS OWN window (not all of them) before invoking the
        // caller's onClose — siblings stay open.
        let view = ActionEditor(
            context: context,
            registry: registry,
            onClose: { [weak self] in
                self?.closeWindow(forKey: key)
                onClose()
            },
            onOpenSibling: { [weak self] siblingContext in
                // Spawn a sibling editor window for the duplicated
                // descriptor. No onClose hand-back to the original
                // caller — siblings are independent.
                self?.show(context: siblingContext,
                           registry: registry,
                           onClose: {})
            }
        )
        let host = NSHostingController(rootView: view)

        let w = NSWindow(contentViewController: host)
        w.title = title
        // .titled gives the draggable title bar; .closable lets the red
        // traffic-light dismiss; .resizable means the user can stretch
        // vertically if they want more breathing room around the test
        // panel. No .miniaturizable — this is a dialog, not a document.
        w.styleMask = [.titled, .closable, .resizable]
        // The editor's content view computes its own ideal width (620 pt
        // normally, 880 pt with regex help expanded). Initial content
        // size matches the default; the user can resize either way.
        w.setContentSize(NSSize(width: 620, height: 720))
        w.isReleasedWhenClosed = false
        w.center()
        // Stagger sibling windows so they don't land exactly on top
        // of each other — easier to see both at once.
        if windowsByKey.count > 0 {
            let offset = CGFloat(windowsByKey.count) * 24
            var f = w.frame
            f.origin.x += offset
            f.origin.y -= offset
            w.setFrame(f, display: false)
        }
        // Belt-and-braces against `.center()` placing the bottom edge
        // behind the Dock / menu bar on small displays — clamp into
        // `visibleFrame` (which excludes both).
        clampToVisibleFrame(w)
        // Wire the red traffic-light: dismissing the window with the
        // close button should fire onClose so the caller resets state.
        let delegate = ActionEditorWindowDelegate(onClose: { [weak self] in
            self?.windowsByKey.removeValue(forKey: key)
            self?.delegatesByKey.removeValue(forKey: key)
            onClose()
        })
        w.delegate = delegate
        delegatesByKey[key] = delegate
        windowsByKey[key] = w
        // Triple-layer focus assertion — accessory-app activation
        // is sometimes blocked by macOS focus-stealing protection,
        // so we cover all three handles (orderFrontRegardless,
        // makeKeyAndOrderFront, NSApp.activate) so at least one
        // reliably brings the window to the foreground.
        w.orderFrontRegardless()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close every open editor window. Used by Settings teardown.
    func close() {
        for w in windowsByKey.values { w.orderOut(nil) }
        windowsByKey.removeAll()
        delegatesByKey.removeAll()
    }

    /// Close the single window identified by `key`. Used by the
    /// per-editor Cancel / Save paths so closing one sibling
    /// doesn't drop the rest.
    private func closeWindow(forKey key: String) {
        windowsByKey.removeValue(forKey: key)?.orderOut(nil)
        delegatesByKey.removeValue(forKey: key)
    }

    /// Bring the most recently-shown editor window to the front.
    /// Used by the Settings list's Edit button to handle the re-
    /// click case: clicking Edit on the SAME action a second time
    /// finds the existing window via the contextKey path in
    /// `show()` and raises it there; `raise()` is the catch-all
    /// for any other "ensure something is on top" trigger.
    func raise() {
        guard let w = windowsByKey.values.first(where: { $0.isKeyWindow })
              ?? windowsByKey.values.first else { return }
        w.orderFrontRegardless()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Stable string identifier for a context — same descriptor
    /// produces the same key, so reopening the same action lands
    /// on the existing window rather than spawning a duplicate.
    /// `createNew` always opens a fresh window because every
    /// "Add" click is intentionally a new draft.
    private static func contextKey(for context: ActionEditorContext) -> String {
        switch context {
        case .createNew:                    return "new.\(UUID().uuidString)"
        case .editBuiltin(let id, _, _):    return "builtin.\(id)"
        case .editTransformation(let d):    return "transform.\(d.id)"
        case .editAI(let d):                return "ai.\(d.id)"
        }
    }

    /// Move the window so its frame fits inside the active screen's
    /// `visibleFrame` (which excludes the menu bar and the Dock). Pure
    /// origin adjustment — never shrinks the frame.
    private func clampToVisibleFrame(_ w: NSWindow) {
        guard let screen = w.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var f = w.frame
        if f.height > visible.height {
            // Window is taller than the screen can fit. Resize the
            // content height down so OK/Cancel stay visible; the editor
            // has internal ScrollViews so this only steals breathing
            // room, not functionality.
            f.size.height = visible.height
        }
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height }
        if f.minY < visible.minY { f.origin.y = visible.minY }
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width }
        if f.minX < visible.minX { f.origin.x = visible.minX }
        w.setFrame(f, display: true)
    }
}

/// NSWindow delegate that routes the red traffic-light close button
/// through the controller's onClose closure. Stored as a strong reference
/// in the controller because NSWindow holds its delegate weakly.
private final class ActionEditorWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

// MARK: - Mode

enum ActionEditorKind: String, CaseIterable, Identifiable {
    case builtin       = "Built-in"
    case transformation = "Transformation"
    case ai            = "AI"

    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .builtin: return "gearshape"
        case .transformation: return "function"
        case .ai: return "sparkles"
        }
    }
    var helpText: String {
        switch self {
        case .builtin:
            return "Pre-made handler bundled with DrPaste. Pick one and assign your own title or hotkey."
        case .transformation:
            return "Deterministic text manipulation via regex, find/replace, prepend/append, wrap, or line filter."
        case .ai:
            return "AI-powered transformation via prompt template. Choose any configured provider."
        }
    }
}

enum ActionEditorContext {
    case createNew
    case editBuiltin(actionID: String, defaultTitle: String, description: String)
    case editTransformation(CustomTransformationDescriptor)
    case editAI(CustomAIDescriptor)
}

// MARK: - Main view

struct ActionEditor: View {
    let context: ActionEditorContext
    @ObservedObject var registry: ActionRegistry
    let onClose: () -> Void
    /// Called by Duplicate to spawn a sibling editor window for
    /// the freshly-cloned descriptor. The original window stays
    /// open so the user can keep editing the source action; the
    /// sibling opens with the clone's context. Nil-safe — callers
    /// that don't support sibling windows pass `nil` and the
    /// Duplicate button falls back to its older "save + close +
    /// reopen for new id" behaviour (effectively closing the
    /// current editor).
    var onOpenSibling: ((ActionEditorContext) -> Void)? = nil

    // Mode (segmented picker) — locked when editing existing
    @State private var kind: ActionEditorKind = .builtin

    // Common fields
    @State private var title: String = ""
    @State private var hotkey: ActionHotkey? = nil
    @State private var applicableTypes: Set<SemanticKind> = []
    @State private var requiredTraits: Set<String> = []   // #A75 "Show when…" conditions
    @State private var forbiddenTraits: [String] = []     // preserved across edits (not user-edited yet)

    // Mode-specific state
    @State private var builtinID: String = ""
    @State private var transformationEngine: TransformationEngine = .regexReplace
    @State private var transformationParams: [String: String] = [:]
    @State private var aiPrompt: String = ""
    @State private var aiProviderID: String = "anthropic"
    /// AI mode for the descriptor under construction: text-in/text-out
    /// (default — Translate / Summarize / etc.) or image-in/image-out
    /// (gpt-image-1 style transforms — Pencil sketch / Watercolor /
    /// Cartoon / user-authored "Oil painting" / "Pop art" / …). UI
    /// surfaces this as a segmented picker at the top of the AI
    /// section. For `.editAI(desc)` contexts the picker reads the
    /// descriptor's existing kind on load; for `.createNew` it
    /// defaults to .text and the user flips before composing the
    /// prompt.
    @State private var aiKind: CustomAIDescriptor.Kind = .text

    // Test panel
    @State private var testInput: String = ""
    @State private var testRunning: Bool = false
    /// Image-mode input for image-applicable actions (OCR, AI styles,
    /// Grayscale, …). Populated on dialog open with either the user's
    /// persisted custom image or a procedurally-generated sample.
    /// User can drag-drop a new image onto the Input area to replace
    /// it; the new image is copied to `AppStorage.imagesDir` and
    /// persisted via `registry.setTestImageRel(_:forActionID:)`.
    @State private var testImageItem: ClipboardItem? = nil
    /// True when the editor should render an image preview in the
    /// Input panel instead of the text editor. Set from
    /// `registry.actionAcceptsImage(_:)` in loadInitialState.
    @State private var testInputIsImage: Bool = false
    /// Captured at dialog open via `loadInitialState` — the sample as it
    /// stood before any user typing this session. Diffed against
    /// `testInput` on Save to decide whether to persist a per-action
    /// override: only deliberate changes go to disk.
    @State private var originalTestSample: String? = nil
    /// Outcome of the most recent `runTest`. Drives the new HUD-style
    /// Output pane (spinner / failure notice / image preview / etc.)
    /// in place of the old plain-text TextEditor mirror.
    @State private var testOutcome: ApplyOutcome?
    /// Inflight descriptor for AI actions — feeds the "Provider · Model
    /// · 4.2s" line in the loading panel, same chrome as BigHUD and
    /// MiniHUD use.
    @State private var testInflight: AIInflight?
    @State private var testElapsed: TimeInterval = 0
    /// 10 Hz timer that ticks `testElapsed` while an AI test is running,
    /// same chrome as BigHUD's `aiTickTimer`. Invalidated on completion.
    @State private var testTickTimer: Timer?
    /// #A57 — handle for the in-flight playground test task. Stored so
    /// `runTest()` can cancel an earlier run before starting the next
    /// one (otherwise a fast double-click on Run leaves the prior
    /// `.apply(...)` racing with the second one and the loser stomps
    /// the live testOutcome), and so `.onDisappear` / action-switch can
    /// tear it down without leaking a streaming AI call. Idle when nil.
    @State private var testTask: Task<Void, Never>? = nil

    // Misc
    @State private var conflictMessage: String? = nil
    @State private var showRegexHelp: Bool = false

    /// User-facing content types — the same list the Settings
    /// playground tabs use (single source of truth via
    /// `SemanticKind.userVisibleKinds`). The "Applies to" checkbox
    /// grid mirrors the tabs exactly: ticking a box means "include
    /// this action under the tab for this content type AND fire it
    /// when the focused clip is detected as this kind". Untick to
    /// hide. No greyed-out auto-applicability check — the user
    /// owns the decision.
    private var allTypes: [SemanticKind] { SemanticKind.userVisibleKinds }

    private var isEditing: Bool {
        switch context {
        case .createNew: return false
        default: return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            HStack(alignment: .top, spacing: 16) {
                // Main column
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        modePicker
                        Divider().padding(.vertical, 2)
                        titleSection
                        hotkeySection
                        applicableTypesSection
                        if showsTraitConditions { traitConditionsSection }
                        Divider().padding(.vertical, 2)
                        modeSpecificSection
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity)

                // Sidebar: regex syntax help (visible only when transformation)
                if kind == .transformation && showRegexHelp {
                    RegexSyntaxHelp()
                        .frame(width: 260)
                        .padding(.vertical, 16).padding(.trailing, 16)
                        .background(Color.primary.opacity(0.03))
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            testPanel
            Divider()
            footerButtons
        }
        // Use minWidth/minHeight rather than a hard frame so the hosting
        // NSWindow (ActionEditorWindowController) can resize freely.
        // Width follows the regex-help expansion state — 880 when the
        // sidebar is visible, 620 otherwise.
        .frame(
            minWidth: showRegexHelp && kind == .transformation ? 880 : 620,
            idealWidth: showRegexHelp && kind == .transformation ? 880 : 620,
            minHeight: 560,
            idealHeight: 720
        )
        .onAppear { loadInitialState() }
        // #A57 — cancel the in-flight playground task when the editor
        // window closes. Without this the AI call keeps streaming
        // tokens into a now-stale view, burning provider tokens for a
        // result that has nowhere to land.
        .onDisappear {
            testTask?.cancel()
            testTask = nil
            stopTestTickTimer()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: kind.iconName).foregroundStyle(Color.accentColor)
            Text(isEditing ? "Edit action" : "New action").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Mode picker

    @ViewBuilder
    private var modePicker: some View {
        if !isEditing {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Mode", selection: $kind) {
                    ForEach(ActionEditorKind.allCases) { k in
                        Label(k.rawValue, systemImage: k.iconName).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(kind.helpText)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack {
                Label(kind.rawValue, systemImage: kind.iconName)
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("Mode locked when editing")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Common sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title").font(.caption).foregroundStyle(.secondary)
            TextField(titlePlaceholder, text: $title)
                .textFieldStyle(.roundedBorder)
            if case .editBuiltin(_, let defaultTitle, _) = context, title != defaultTitle {
                HStack(spacing: 6) {
                    Text("Default: \(defaultTitle)")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Button { title = defaultTitle } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                }
            }
        }
    }

    private var titlePlaceholder: String {
        switch kind {
        case .builtin: return "Display name"
        case .transformation: return "My transformation"
        case .ai: return "AI: my action"
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Hotkey").font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Recommendation chip — always visible so the user notices
                // before they pick a combo. Once they pick one, the
                // hudSupportHint below switches between "supported" and
                // "not supported" copy so they can correct it if they
                // wanted hold-preview.
                Text("Tip: ⌥⌘ + letter enables HUD hold-preview")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HotkeyRecorderField(
                hotkey: $hotkey,
                onStatus: { msg in conflictMessage = msg.isEmpty ? nil : msg },
                conflictChecker: { hk in
                    registry.conflictingActionInfo(for: hk, excludingID: currentActionID)
                }
            )
            if let msg = conflictMessage {
                // Reserved-combo errors are red; steal notices are informational
                // (orange). Conflict messages take priority over the HUD-support
                // hint because they require user action to resolve.
                let isReserved = msg.hasPrefix("This combination is reserved")
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(isReserved ? Color.red : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                hudSupportHint
            }
        }
    }

    /// Three-state hint about whether the picked hotkey supports the
    /// hold-to-preview BigHUD gesture from #A10:
    ///   • No hotkey picked   → instructional caption.
    ///   • ⌥⌘ + letter        → green success: HUD ready, explain the hold gesture.
    ///   • Anything else      → orange warning: direct-paste only.
    /// Two-line max; never wraps wider than the recorder field.
    @ViewBuilder
    private var hudSupportHint: some View {
        if let hk = hotkey {
            if hk.isOptCmdOnly {
                Label {
                    Text("HUD ready — tap to paste immediately, or keep ⌥⌘ held after pressing \(hk.keyDisplayName) to preview the result in BigHUD before committing.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(Color.green)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Label {
                    Text("Direct trigger only — paste happens immediately; the BigHUD hold-preview gesture requires ⌥⌘ + letter to compose with the rest of DrPaste's gestures.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("No hotkey set. Pick a combination above — ⌥⌘ + a letter unlocks the BigHUD hold-preview flow; other modifier combos run as pure direct-trigger.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var applicableTypesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Applies to").font(.caption).foregroundStyle(.secondary)
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(allTypes, id: \.self) { type in
                    // Every checkbox is freely toggleable — no
                    // greyed-out "auto-detected as inapplicable"
                    // state. The checkbox is the user's deliberate
                    // choice: "this action belongs under the
                    // <type> tab and fires for clips of that
                    // semantic kind". Removing the disabled-greying
                    // mirrors the Playground UI where every tab is
                    // visible and equal-weight.
                    Toggle(isOn: Binding(
                        get: { applicableTypes.contains(type) },
                        set: { isOn in
                            if isOn { applicableTypes.insert(type) }
                            else { applicableTypes.remove(type) }
                        }
                    )) {
                        Text(type.displayName)
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    /// #A75 — "Show this action when…". Each toggle is one cheap content
    /// condition; the Enabled/Disabled master switch is separate (unchanged).
    /// No condition selected = always shown for the applicable types. To make
    /// a gated action always appear, the user simply unchecks its condition —
    /// there is deliberately no "always" override that ignores conditions.
    /// Trait conditions are text-derived, so the section is hidden for
    /// image-only actions (image→image AI, OCR-style builtins) where they'd
    /// never match.
    private var showsTraitConditions: Bool {
        if kind == .ai && aiKind == .image { return false }
        let textKinds: Set<SemanticKind> = [.text, .richText, .url, .json, .code, .markdown, .table, .email]
        return applicableTypes.isEmpty || !applicableTypes.isDisjoint(with: textKinds)
    }

    @ViewBuilder
    private var traitConditionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Show this action when…").font(.caption).foregroundStyle(.secondary)
            Text(requiredTraits.isEmpty
                 ? "No condition — always shown for the types above."
                 : "Shown only when the clipboard matches any checked condition.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            let columns = [GridItem(.adaptive(minimum: 210), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(ActionTrait.all) { trait in
                    Toggle(isOn: Binding(
                        get: { requiredTraits.contains(trait.key) },
                        set: { isOn in
                            if isOn { requiredTraits.insert(trait.key) }
                            else { requiredTraits.remove(trait.key) }
                        }
                    )) {
                        Text(trait.label).font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                }
            }
            if !requiredTraits.isEmpty && !testInput.isEmpty {
                traitPreviewLine
            }
        }
    }

    /// Live "would this appear for the current sample?" indicator — the
    /// conditions are tuned against a real example, never in the abstract.
    private var traitPreviewLine: some View {
        let stub = ClipboardItem(
            id: UUID(), semantic: .text, createdAt: Date(),
            representations: [:], typesOrdered: [], previewText: testInput,
            previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
            sourceWindowTitle: nil, tags: [])
        let ctx = ContextDetector.detect(stub)
        let passes = ActionTrait.passes(required: Array(requiredTraits), forbidden: [], in: ctx)
        return HStack(spacing: 5) {
            Image(systemName: passes ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(passes ? Color.green : Color.secondary)
            Text(passes ? "Would appear for the current sample"
                        : "Hidden for the current sample")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    // `isTypeApplicable` was removed when the "Applies to" grid
    // switched to fully-toggleable checkboxes — the user owns the
    // decision instead of the editor inferring per-type capability
    // and greying out boxes. The auto-inference for first-open
    // preselection still lives in `inferApplicableTypes(builtinID:)`
    // below; from then on the checkboxes are pure user state.

    // MARK: - Mode-specific config

    @ViewBuilder
    private var modeSpecificSection: some View {
        switch kind {
        case .builtin: builtinConfig
        case .transformation: transformationConfig
        case .ai: aiConfig
        }
    }

    // Built-in: picker for an existing action.
    @ViewBuilder
    private var builtinConfig: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Built-in handler").font(.caption).foregroundStyle(.secondary)
            if case .editBuiltin(let actionID, _, let description) = context {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text(actionID).font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                if !description.isEmpty {
                    Text(description).font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Picker("", selection: $builtinID) {
                    Text("Choose handler…").tag("")
                    ForEach(BuiltinHandlerCategory.allCases) { category in
                        let actions = builtinsByCategory[category] ?? []
                        if !actions.isEmpty {
                            Section(category.title) {
                                ForEach(actions, id: \.id) { action in
                                    Text(action.title).tag(action.id)
                                }
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                if !builtinID.isEmpty, let description = BuiltinActionMetadata.descriptions[builtinID] {
                    Text(description).font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Pre-made handlers are bundled with DrPaste. Picking one here lets you give it a custom title and hotkey.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var availableBuiltins: [ClipboardAction] {
        return registry.actions.filter { action in
            // Every `builtin.*` action is pickable here EXCEPT the identity
            // anchor (`builtin.identity`), which can't be re-created via
            // this dialog. Descriptor-backed bundled handlers
            // (`DefaultTransformationSeed` entries like `builtin.md_to_plain`,
            // `builtin.md_headings`, `builtin.md_links`,
            // `builtin.cyrillic_translit`, the Unicode pseudo-font family,
            // etc.) used to be filtered out of this picker because they
            // already appear as Transformation rows in the Settings list,
            // but that produced an inconsistency: a user adding a NEW
            // Built-in action through "+ New" couldn't see "Markdown →
            // plain" or "Extract links" as options, even though those
            // showed up in Settings. The user asked for a single source
            // of truth — pickers in every surface (Settings list, "+ New"
            // Built-in picker, Playground) draw from the SAME list of
            // bundled handlers.
            guard action.id.hasPrefix("builtin.") else { return false }
            guard action.id != "builtin.identity" else { return false }
            return true
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Available built-in handlers bucketed by category so the picker can
    /// render them as labelled sections rather than one alphabetical list.
    /// Bucketing is namespace-driven (`builtin.image_*` → Image, etc.) with a
    /// small explicit override map for IDs that don't follow the prefix.
    private var builtinsByCategory: [BuiltinHandlerCategory: [ClipboardAction]] {
        Dictionary(grouping: availableBuiltins) { BuiltinHandlerCategory.of($0.id) }
    }

    /// Engines shown in the picker for a NEW custom transformation. Filters
    /// out parameter-less "recipe" engines (camelCase, slugify, mdExtract, …)
    /// that only exist to back specific bundled built-ins — those built-ins
    /// already appear as ready-to-run actions, so re-exposing the underlying
    /// engine in the constructor would just clutter the menu.
    ///
    /// When editing an existing transformation that uses one of the hidden
    /// engines (e.g. opening the bundled `builtin.slugify` to retitle it),
    /// the current engine is added to the list so the Picker can still render
    /// the selected row.
    private var availableEngines: [TransformationEngine] {
        var engines = TransformationEngine.allCases.filter(\.userPickable)
        if !engines.contains(transformationEngine) {
            engines.append(transformationEngine)
        }
        return engines
    }

    // Transformation: engine picker + params
    @ViewBuilder
    private var transformationConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Engine").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { showRegexHelp.toggle() }
                } label: {
                    Label(showRegexHelp ? "Hide help" : "Regex help",
                          systemImage: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Picker("", selection: $transformationEngine) {
                ForEach(availableEngines, id: \.self) { engine in
                    Label(engine.displayName, systemImage: engine.iconName).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: transformationEngine) { newEngine in
                // Reset parameters to the new engine's defaults whenever the engine changes.
                if transformationParams.keys.sorted() != newEngine.defaultParameters.keys.sorted() {
                    transformationParams = newEngine.defaultParameters
                }
            }
            Text(transformationEngine.description)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            transformationParameterFields
        }
    }

    @ViewBuilder
    private var transformationParameterFields: some View {
        switch transformationEngine {
        case .regexReplace:
            paramTextField(label: "Pattern", key: "pattern", placeholder: "regex pattern")
            paramTextField(label: "Replacement", key: "replacement", placeholder: "use $1, $2 for groups")
            paramToggle(label: "Case insensitive", key: "caseInsensitive")
        case .findReplace:
            paramTextField(label: "Find", key: "find", placeholder: "text to find")
            paramTextField(label: "Replace", key: "replace", placeholder: "replacement")
            paramToggle(label: "Case insensitive", key: "caseInsensitive")
        case .prepend:
            paramTextField(label: "Text", key: "text", placeholder: "text added at start")
        case .append:
            paramTextField(label: "Text", key: "text", placeholder: "text added at end")
        case .wrap:
            paramTextField(label: "Prefix", key: "prefix", placeholder: "e.g. ```")
            paramTextField(label: "Suffix", key: "suffix", placeholder: "e.g. ```")
        case .lineFilter:
            paramTextField(label: "Pattern", key: "pattern", placeholder: "regex pattern")
            HStack {
                Text("Mode:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: paramBinding(key: "mode", default: "keep")) {
                    Text("Keep matching").tag("keep")
                    Text("Remove matching").tag("remove")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        case .caseChange:
            HStack {
                Text("Case:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: paramBinding(key: "case", default: "upper")) {
                    Text("UPPER").tag("upper")
                    Text("lower").tag("lower")
                    Text("Title Case").tag("title")
                    Text("Sentence case").tag("sentence")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        case .sortLines:
            HStack {
                Text("Direction:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: paramBinding(key: "direction", default: "asc")) {
                    Text("Ascending").tag("asc")
                    Text("Descending").tag("desc")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            paramToggle(label: "Case insensitive", key: "caseInsensitive")
        case .uniqueLines:
            Text("Removes consecutive duplicate lines, preserves order.")
                .font(.caption).foregroundStyle(.tertiary)
        case .jsonFormat:
            HStack {
                Text("Operation:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: paramBinding(key: "operation", default: "pretty")) {
                    Text("Pretty").tag("pretty")
                    Text("Minify").tag("minify")
                    Text("Extract keys (top-level)").tag("extractKeys")
                    Text("Extract keys (recursive)").tag("extractKeysRecursive")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        case .unicodeStyle:
            // Style picker. Each item shows the style name plus a 6-char
            // styled preview ("𝐀𝐚 𝟏𝟐") so the user sees what each option
            // looks like before committing.
            HStack(alignment: .top) {
                Text("Style:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: paramBinding(
                    key: "style",
                    default: UnicodeFontStyle.bold.rawValue
                )) {
                    ForEach(UnicodeFontStyle.allCases) { style in
                        Text("\(style.displayName)  ·  \(style.sample)")
                            .tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        // Parameter-less engines seeded as built-ins via DefaultTransformationSeed.
        // They expose no editable parameters in the UI — they just show their
        case .latinToCyrillic:
            HStack {
                Text("Language:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: paramBinding(key: "target", default: "auto")) {
                    Text("Auto — by letters & locale").tag("auto")
                    Divider()
                    Text("Russian").tag("russian")
                    Text("Ukrainian").tag("ukrainian")
                    Text("Kazakh").tag("kazakh")
                    Text("Serbian").tag("serbian")
                    Text("Bulgarian").tag("bulgarian")
                    Text("Tajik").tag("tajik")
                    Text("Mongolian").tag("mongolian")
                    Text("Belarusian").tag("belarusian")
                    Text("Kyrgyz").tag("kyrgyz")
                    Text("Tatar").tag("tatar")
                    Text("Chechen").tag("chechen")
                    Text("Macedonian").tag("macedonian")
                    Text("Bashkir").tag("bashkir")
                    Text("Chuvash").tag("chuvash")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        case .leetspeak:
            paramToggle(label: "Aggressive", key: "aggressive")
        case .uwuSpeak:
            paramToggle(label: "Inject faces", key: "faces")
        case .zalgo:
            HStack {
                Text("Intensity:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: paramBinding(key: "intensity", default: "medium")) {
                    Text("Light").tag("light")
                    Text("Medium").tag("medium")
                    Text("Heavy").tag("heavy")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        // description (which the editor already prints above this view) and
        // run on the input as-is.
        case .trim,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking,
             .cyrillicToLatin,
             .prettyCodeLocal,
             .htmlStripTags, .htmlEscape, .htmlUnescape,
             .jsonValidate, .normalizeSpaces, .collapseBlankLines,
             .extractEmails, .extractLinks, .removeLineBreaks:
            Text("This engine has no parameters.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func paramTextField(label: String, key: String, placeholder: String) -> some View {
        HStack {
            Text(label + ":").font(.caption).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            TextField(placeholder, text: paramBinding(key: key, default: ""))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func paramToggle(label: String, key: String) -> some View {
        HStack {
            Spacer().frame(width: 100)
            Toggle(label, isOn: paramBoolBinding(key: key))
        }
    }

    private func paramBinding(key: String, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { transformationParams[key] ?? defaultValue },
            set: { transformationParams[key] = $0 }
        )
    }
    private func paramBoolBinding(key: String) -> Binding<Bool> {
        Binding(
            get: { transformationParams[key] == "true" },
            set: { transformationParams[key] = $0 ? "true" : "false" }
        )
    }

    // AI mode
    @ViewBuilder
    private var aiConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Kind picker — text-in/text-out vs image-in/image-out.
            // Picking Image flips the entire descriptor lane: prompt
            // template hint changes to image-style, Input panel
            // switches to image preview, applicableTypes locks to
            // ["image"], runtime dispatches to AIImageAction →
            // gpt-image-1. The user writes whatever prompt makes
            // sense ("Convert to oil painting", "Add a soft blur",
            // "Make it look like a 1920s photo") and the system
            // routes it correctly.
            HStack {
                Text("Operation:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $aiKind) {
                    Text("Text → text").tag(CustomAIDescriptor.Kind.text)
                    Text("Text → image").tag(CustomAIDescriptor.Kind.textToImage)
                    Text("Image → image").tag(CustomAIDescriptor.Kind.image)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: aiKind) { newKind in
                    // Sync state that depends on kind. Three modes:
                    //   - text       → text input, applicableTypes pickable
                    //   - textToImage → text input, applicableTypes
                    //                   defaults to text-bearing kinds
                    //   - image      → image input panel, applicableTypes
                    //                   locked to [.image]
                    switch newKind {
                    case .image:
                        applicableTypes = [.image]
                        testInputIsImage = true
                        if testImageItem == nil {
                            testImageItem = ActionTestSamples.makeSampleImageItem()
                        }
                    case .textToImage:
                        // Default to text-content kinds for text→image —
                        // user can untick what they don't want. Don't
                        // reset if they've already chosen something.
                        if applicableTypes.isEmpty || applicableTypes == [.image] {
                            applicableTypes = [.text, .markdown, .richText, .code]
                        }
                        testInputIsImage = false
                    case .text:
                        if applicableTypes == [.image] {
                            applicableTypes = [.text, .markdown, .richText]
                        }
                        testInputIsImage = false
                    }
                    // Re-pin the Provider picker selection to a
                    // provider that can actually run THIS operation.
                    // Without this, switching text → image leaves the
                    // selection on (say) Anthropic, which can't run
                    // images at all — the soft-fallback would still
                    // route correctly but the picker would visibly
                    // lie about who's about to fire.
                    autoSelectProviderForCurrentKind()
                }
            }
            if aiKind == .image {
                HStack(spacing: 4) {
                    Spacer().frame(width: 100)
                    Text("Image → image: edits an existing image (clipboard) using your prompt. Runs on OpenAI (gpt-image-1), Google Gemini (gemini-2.5-flash-image-preview), OpenRouter (image-capable model), or a Custom OpenAI-compatible endpoint. The Provider picker below is filtered to image-capable kinds.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if aiKind == .textToImage {
                HStack(spacing: 4) {
                    Spacer().frame(width: 100)
                    Text("Text → image: generates a NEW image from clipboard text + your prompt. Use \"{input}\" in your prompt to mark where the clipboard text goes; otherwise it's appended at the end. Same provider lineup as Image → image.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            providerPickerRow

            // "Effective provider" hint under the picker. Two flavours:
            //
            //   • Default is picked AND it works for this operation →
            //     "Resolves to <resolved.displayName> (the current
            //     default)" so the user sees the actual brand the
            //     action will hit.
            //
            //   • Default is picked but the default can't run this
            //     operation (image mode + Anthropic default) → soft
            //     fallback finds an image-capable provider → "Default
            //     (<chat default>) can't run image actions. Falling
            //     back to <resolved.displayName>." so the user
            //     understands why the badge shows a different brand
            //     than the chat default.
            //
            //   • No working provider at all (image mode + zero
            //     image-capable providers configured) → orange warning
            //     pointing them to Settings → AI.
            providerHintRow
            // #7 Templates menu — quick-fill prompt from common patterns
            HStack {
                Text("Templates:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Menu {
                    ForEach(AIPromptTemplates.all, id: \.title) { template in
                        Button {
                            if title.isEmpty { title = template.title }
                            aiPrompt = template.prompt
                        } label: {
                            Text(template.title)
                        }
                    }
                } label: {
                    Label("Insert template…", systemImage: "sparkles.rectangle.stack")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                Spacer()
            }
            Text("Prompt template").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $aiPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            // Tip text adapts to the kind so the user knows what
            // the prompt is actually being applied to.
            if aiKind == .image {
                Text("Tip: describe how the AI should re-render the image. Examples: \"Convert to oil painting with thick visible brushstrokes\", \"Add a soft vignette and warm sepia tone\", \"Make it look like a 1920s sepia photograph\". The source image is passed as the `image` input to gpt-image-1.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tip: write what the AI should do with the input. The clipboard text is automatically passed as the user message.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Provider picker

    /// Provider row — label with the effective provider's brand
    /// icon, then a menu picker listing EVERY configured provider.
    /// Image-mode disables the rows that can't run image edits
    /// (they're greyed out but still visible so the user sees the
    /// full lineup and understands what's available vs not).
    @ViewBuilder
    private var providerPickerRow: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Provider:").font(.caption).foregroundStyle(.secondary)
                // Brand icon of the EFFECTIVE resolved provider
                // (per-action override → default → image-capable
                // soft fallback). Tells the user at a glance which
                // brand the action will hit — particularly important
                // when "Default" doesn't work for the operation and
                // the soft fallback rerouted to a different provider.
                if let effective = effectiveProvider() {
                    Image(systemName: effective.kind.iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(effective.kind.brandColor)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(effective.kind.brandColor.opacity(0.18)))
                } else {
                    // No working provider for this operation —
                    // small orange warning glyph in the lookup
                    // position so the row visually flags the
                    // missing config.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 100, alignment: .leading)

            // Custom menu picker — built by hand instead of SwiftUI's
            // `Picker` because we want to disable individual entries
            // (per-provider) without filtering them out. SwiftUI's
            // built-in Picker doesn't expose a per-row `.disabled()`
            // hook, so we use a Menu with Buttons and an explicit
            // selection-mirroring label.
            Menu {
                // Default sentinel — always available. Its label
                // shows the effective resolved provider so the user
                // sees what "Default" actually means right now.
                Button {
                    aiProviderID = ""
                } label: {
                    HStack {
                        Text("Default" + defaultEffectiveSuffix)
                        if aiProviderID.isEmpty {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                // Every configured provider — disabled when the
                // current operation needs image-edit capability the
                // provider doesn't have. Still visible so the user
                // sees the full lineup and knows what's available.
                ForEach(AIProviderRegistry.shared.config.providers) { p in
                    let needsImage = (aiKind == .image || aiKind == .textToImage)
                    let usable = !needsImage || p.kind.supportsImageEdit
                    Button {
                        if usable { aiProviderID = p.id }
                    } label: {
                        HStack {
                            Image(systemName: p.kind.iconName)
                                .foregroundStyle(p.kind.brandColor)
                            Text(p.displayName)
                            if !usable {
                                Text("— no image support")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if aiProviderID == p.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!usable)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPickerLabel)
                    // Reroute warning glyph — appears only when the
                    // chip is showing a provider OTHER than what the
                    // user nominally picked (broken explicit, or
                    // Default sentinel landing on a non-default
                    // provider because chat default can't run the
                    // operation). Visible cue that the system
                    // self-corrected so the user isn't surprised
                    // when the Preview HUD names a brand they
                    // didn't choose.
                    if isProviderRerouted {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .help(rerouteTooltip)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
    }

    /// True when what the user picked in the menu doesn't match
    /// what's actually going to run. Two reroute scenarios:
    ///   • Explicit override is missing, disabled, or wrong-
    ///     capability — runtime soft-falls back to a different
    ///     provider.
    ///   • Default sentinel selected, but chat default can't run
    ///     the current operation (e.g. Anthropic + image action)
    ///     — runtime reroutes to a different provider.
    private var isProviderRerouted: Bool {
        let cfg = AIProviderRegistry.shared.config
        let needsImage = (kind == .ai && (aiKind == .image || aiKind == .textToImage))
        guard let effective = effectiveProvider() else { return false }
        if !aiProviderID.isEmpty {
            // Explicit override broken if it doesn't exist, is
            // disabled, or lacks the needed capability.
            if let cp = cfg.providers.first(where: { $0.id == aiProviderID }),
               cp.enabled, (!needsImage || cp.kind.supportsImageEdit) {
                return false
            }
            return true
        }
        // Default sentinel — rerouted when chat default differs
        // from the effective resolved provider.
        if let chatDefault = AIProviderRegistry.shared.defaultProvider {
            return chatDefault.id != effective.id
        }
        return false
    }

    /// Tooltip for the reroute glyph — explains WHY the chip is
    /// showing a different provider than the menu selection.
    private var rerouteTooltip: String {
        let cfg = AIProviderRegistry.shared.config
        let needsImage = (kind == .ai && (aiKind == .image || aiKind == .textToImage))
        let effective = effectiveProvider()
        let effectiveName = effective?.displayName ?? "—"
        if !aiProviderID.isEmpty {
            if let cp = cfg.providers.first(where: { $0.id == aiProviderID }) {
                if !cp.enabled {
                    return "Picked provider “\(cp.displayName)” is disabled. Routed to \(effectiveName) instead."
                }
                if needsImage && !cp.kind.supportsImageEdit {
                    return "Picked provider “\(cp.displayName)” can't run image operations. Routed to \(effectiveName) instead."
                }
            } else {
                return "Picked provider no longer exists. Routed to \(effectiveName) instead."
            }
        }
        // Default sentinel reroute.
        if let chatDefault = AIProviderRegistry.shared.defaultProvider {
            return "Default chat provider “\(chatDefault.displayName)” can't run this. Routed to \(effectiveName) instead."
        }
        return "Routed to \(effectiveName)."
    }

    /// Hint paragraph shown beneath the Provider picker. Four states:
    ///   • Orange "no image-capable provider at all" — nothing in
    ///     the registry can satisfy this operation.
    ///   • Orange reroute notice — Default sentinel or explicit
    ///     override picked something that can't run; system
    ///     auto-routed to a working provider.
    ///   • Grey "Default resolves to X" — Default sentinel works
    ///     fine; just spelling out who that is.
    ///   • Hidden — explicit override is working as picked, no
    ///     need to comment.
    @ViewBuilder
    private var providerHintRow: some View {
        let cfg = AIProviderRegistry.shared.config
        let needsImage = (aiKind == .image || aiKind == .textToImage)
        let effective = effectiveProvider()
        if needsImage && effective == nil {
            HStack(spacing: 4) {
                Spacer().frame(width: 100)
                Label(
                    "No image-capable provider configured. Add OpenAI, Gemini, OpenRouter, or a Custom OpenAI-compatible endpoint in Settings → AI.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else if let effective = effective, isProviderRerouted {
            // Explicit override or Default rerouted — spell out the
            // why so the orange glyph on the chip has context.
            HStack(spacing: 4) {
                Spacer().frame(width: 100)
                if !aiProviderID.isEmpty {
                    // Explicit override broken.
                    if let cp = cfg.providers.first(where: { $0.id == aiProviderID }) {
                        Text("Picked provider “\(cp.displayName)” \(brokenExplicitReason(cp: cp, needsImage: needsImage)). Routed to \(effective.displayName).")
                            .font(.caption2).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Picked provider no longer exists. Routed to \(effective.displayName).")
                            .font(.caption2).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let chatDefault = AIProviderRegistry.shared.defaultProvider {
                    // Default sentinel rerouted.
                    Text("Default chat provider (\(chatDefault.displayName)) can't run this. Routed to \(effective.displayName).")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if aiProviderID.isEmpty, let effective = effective {
            // Default sentinel works fine — just label who that is.
            HStack(spacing: 4) {
                Spacer().frame(width: 100)
                Text("Resolves to \(effective.displayName). Change the default in Settings → AI to switch.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Label shown inside the Menu's selected-value chip.
    ///
    /// Strict-truth rule: the chip MUST name the provider that
    /// will actually fire the request, not whatever sentinel is
    /// stored in `aiProviderID`. The user gets ONE consistent
    /// story across the chip, the leading icon, the hint row,
    /// and the Preview HUD — if any of these three disagree we've
    /// lied about what's about to happen.
    ///
    /// Three cases:
    ///   1. Explicit override picks an enabled, capability-matching
    ///      provider → show its name straight.
    ///   2. Explicit override picks a missing / disabled / non-
    ///      image-capable provider → show the effective fallback's
    ///      name, NOT the broken explicit (the chip would otherwise
    ///      lie). The hint row + icon will flag this as a reroute.
    ///   3. Default sentinel → show "Default · <effective-name>"
    ///      where the effective name is what the runtime chain
    ///      actually lands on (chat default if usable, otherwise
    ///      cheapest image-capable). The sentinel ITSELF in the
    ///      dropdown still names the chat default (see
    ///      `defaultEffectiveSuffix`) — that's the "what would
    ///      happen if you re-pick Default" view — but the chip
    ///      shows what's happening NOW.
    private var currentPickerLabel: String {
        let cfg = AIProviderRegistry.shared.config
        let needsImage = (kind == .ai && (aiKind == .image || aiKind == .textToImage))
        // Case 1 — explicit override is usable as-is.
        if !aiProviderID.isEmpty,
           let cp = cfg.providers.first(where: { $0.id == aiProviderID }),
           cp.enabled,
           (!needsImage || cp.kind.supportsImageEdit) {
            return cp.displayName
        }
        // Case 3 — Default sentinel selected (aiProviderID empty).
        if aiProviderID.isEmpty {
            if let effective = effectiveProvider() {
                return "Default · \(effective.displayName)"
            }
            return "Default"
        }
        // Case 2 — explicit override is broken (missing/disabled/
        // wrong capability). Don't lie; surface the fallback.
        if let effective = effectiveProvider() {
            return effective.displayName
        }
        return "—"
    }

    /// " (Anthropic Claude)" or similar suffix appended after the
    /// word "Default" inside the dropdown. Computed from the live
    /// chat default — not the image-fallback resolution — because
    /// inside the menu we want to surface what "Default" maps to
    /// in the registry, not the image-action override.
    private var defaultEffectiveSuffix: String {
        if let d = AIProviderRegistry.shared.defaultProvider {
            return " (\(d.displayName))"
        }
        return ""
    }

    /// Repair the Provider picker selection. NEVER silently pins
    /// an explicit override — that would change the action's
    /// long-term routing (jumping off Default sentinel means the
    /// action stops following Settings → AI changes, and stops
    /// taking advantage of newly-added cheaper providers). The
    /// only mutation we do is reset a BROKEN explicit (missing /
    /// disabled / wrong-capability) back to the Default sentinel
    /// so the picker doesn't sit on a stale ID.
    ///
    /// Showing the actual worker provider to the user is the chip
    /// label's job — `currentPickerLabel` reads "Default · OpenAI"
    /// when Default resolves to OpenAI via the soft fallback. The
    /// reroute glyph + hint row spell out WHY.
    @MainActor
    private func autoSelectProviderForCurrentKind() {
        guard !aiProviderID.isEmpty else { return }
        let cfg = AIProviderRegistry.shared.config
        let needsImage = (kind == .ai && (aiKind == .image || aiKind == .textToImage))
        // If the explicit override is still valid for the current
        // operation, leave the user's choice alone.
        if let cp = cfg.providers.first(where: { $0.id == aiProviderID }),
           cp.enabled,
           (!needsImage || cp.kind.supportsImageEdit) {
            return
        }
        // Otherwise drop back to Default sentinel. The label, icon,
        // reroute glyph and hint will tell the user what's actually
        // running now (without re-pinning that as a stored override).
        aiProviderID = ""
    }

    /// Plain-English why this explicit override doesn't work for
    /// the current operation. Used by `providerHintRow` and
    /// `rerouteTooltip` so the user gets the same phrasing in
    /// both surfaces. Pulled out of the `@ViewBuilder` body
    /// because Swift's result-builder doesn't tolerate plain
    /// assignments inside its branches.
    private func brokenExplicitReason(cp: ConfiguredProvider, needsImage: Bool) -> String {
        if !cp.enabled { return "is disabled" }
        if needsImage && !cp.kind.supportsImageEdit { return "can't run image actions" }
        return "isn't usable"
    }

    /// Walk the same resolution chain `AIImageAction.resolveProvider`
    /// uses at runtime so the UI shows the real provider that will
    /// fire when the user clicks Run. For text-only actions there's
    /// no capability gate — every configured provider qualifies, so
    /// the default wins outright.
    private func effectiveProvider() -> ConfiguredProvider? {
        let cfg = AIProviderRegistry.shared.config
        let needsImage = (aiKind == .image || aiKind == .textToImage)
        // 1. Per-action explicit override wins if it's usable.
        if !aiProviderID.isEmpty,
           let cp = cfg.providers.first(where: { $0.id == aiProviderID }),
           cp.enabled,
           (!needsImage || cp.kind.supportsImageEdit) {
            return cp
        }
        // 2. Configured default — usable when no operation gate or
        //    when the default itself supports image edits.
        if let defaultID = cfg.defaultProviderID,
           let cp = cfg.providers.first(where: { $0.id == defaultID }),
           cp.enabled,
           (!needsImage || cp.kind.supportsImageEdit) {
            return cp
        }
        // 3. Soft fallback — for image operations only, pick the
        //    cheapest enabled image-capable provider. Matches the
        //    runtime AIImageAction.resolveProvider chain (which
        //    also walks providers in cost-rank order).
        if needsImage {
            return AIProviderRegistry.shared.cheapestEnabledImageProvider()
        }
        // 4. For text-only operations, any enabled provider works.
        return cfg.providers.first { $0.enabled }
    }

    // MARK: - Test panel

    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Test").font(.subheadline)
                Spacer()
                Button("Run test") { runTest() }
                    .disabled(testRunning)
                    .controlSize(.small)
                if testRunning { ProgressView().controlSize(.small) }
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Input").font(.caption2).foregroundStyle(.secondary)
                        if testInputIsImage {
                            Spacer()
                            // Reset only enabled when the user has a
                            // persisted custom image — otherwise the
                            // procedural sample is already in effect.
                            if let id = currentActionID,
                               registry.testImageRel(forActionID: id) != nil {
                                Button("Reset") { resetTestImageToProcedural() }
                                    .controlSize(.mini)
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if testInputIsImage {
                        testImageInputView
                    } else {
                        TextEditor(text: $testInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 160)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output").font(.caption2).foregroundStyle(.secondary)
                    // onRun makes the empty-state play glyph a real
                    // button — click anywhere in the Output pane to
                    // fire the test. Mirrors the toolbar "Run test"
                    // button so the user can reach for whichever
                    // affordance is closer to their pointer.
                    TestOutputPane(
                        outcome: testOutcome,
                        isRunning: testRunning,
                        inflight: testInflight,
                        elapsed: testElapsed,
                        actionTitle: title.isEmpty ? nil : title,
                        onRun: { runTest() }
                    )
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.primary.opacity(0.02))
    }

    /// Image preview for image-applicable actions. Renders the current
    /// `testImageItem` via the same `ImagePreview` view BigHUD uses,
    /// with a drop-target overlay so the user can drag a different
    /// image file in to replace the sample.
    @ViewBuilder
    private var testImageInputView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3))
            if let item = testImageItem {
                ImagePreview(item: item)
                    .padding(4)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("Drop an image here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 160)
        .onDrop(of: ["public.file-url", "public.image"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            // file-url path — user dragged a file from Finder.
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    var fileURL: URL?
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        fileURL = url
                    } else if let url = item as? URL {
                        fileURL = url
                    }
                    if let url = fileURL {
                        DispatchQueue.main.async { handleDroppedImage(at: url) }
                    }
                }
                return true
            }
            // raw image — user dragged from another app's image canvas.
            // Materialise to a tmp file then run through the same
            // re-encode/persist path. Less common than file-URL drops.
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data = data else { return }
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("drpaste-drop-\(UUID().uuidString).png")
                    try? data.write(to: tmp)
                    DispatchQueue.main.async { handleDroppedImage(at: tmp) }
                }
                return true
            }
            return false
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            // Delete + Duplicate available only when editing a user-
            // created action (transformation / AI). Built-ins are
            // immutable — duplicating them would clone something
            // that's already implicitly available to every user.
            if case .editTransformation(let desc) = context {
                Button(role: .destructive) {
                    registry.removeCustomTransformation(id: desc.id)
                    registry.setHotkey(nil, for: desc.id)
                    onClose()
                } label: { Label("Delete", systemImage: "trash") }
                Button { duplicateTransformation(from: desc) } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            } else if case .editAI(let desc) = context {
                Button(role: .destructive) {
                    registry.removeCustomAI(id: desc.id)
                    registry.setHotkey(nil, for: desc.id)
                    onClose()
                } label: { Label("Delete", systemImage: "trash") }
                Button { duplicateAI(from: desc) } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
            Spacer()
            Button("Cancel") { onClose() }
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    /// Clone the action currently being edited into a new entry
    /// with a fresh UUID and a numbered title (`Title 2`, `Title 3`,
    /// …). The clone takes the CURRENT live editor state (title,
    /// prompt, applicable types, provider, kind) rather than the
    /// `desc` snapshot we opened with — so unsaved tweaks the user
    /// just made carry into the copy, matching the "duplicate
    /// what I'm looking at" expectation.
    ///
    /// Behaviour:
    ///   • Original window STAYS OPEN — user might want to keep
    ///     editing the source action separately.
    ///   • Sibling editor window OPENS for the freshly-created
    ///     clone (via `onOpenSibling`), so the user can adjust
    ///     the copy immediately.
    ///   • Hotkey is NOT copied — two actions can't share a
    ///     chord, and silently stealing the user's hotkey for
    ///     the clone would be surprising. Clone starts hotkey-less.
    @MainActor
    private func duplicateTransformation(from original: CustomTransformationDescriptor) {
        let newID = "user.transform.\(UUID().uuidString.prefix(8))"
        let newTitle = nextDuplicateTitle(base: title)
        let appliesArray = applicableTypes.map { $0.rawValue }.sorted()
        let descriptor = CustomTransformationDescriptor(
            id: newID,
            title: newTitle,
            engineID: transformationEngine.rawValue,
            parameters: transformationParams,
            applicableTypes: appliesArray,
            enabled: true,
            requiredTraits: requiredTraits.sorted(),
            forbiddenTraits: forbiddenTraits
        )
        // Insert directly after the original so the clone shows up
        // as the original's right-hand neighbour in the Settings
        // list, in the HUD chips, and in any pinned per-kind order —
        // matches the "here's the source, here are its derivatives"
        // mental model.
        registry.upsertCustomTransformation(descriptor, after: original.id)
        if let onOpenSibling = onOpenSibling {
            onOpenSibling(.editTransformation(descriptor))
        } else {
            // Caller didn't wire sibling-spawn — fall back to the
            // simpler close behaviour so the user at least sees
            // the registry list refresh with the new entry.
            onClose()
        }
    }

    @MainActor
    private func duplicateAI(from original: CustomAIDescriptor) {
        let newID = "user.\(UUID().uuidString.prefix(8))"
        let newTitle = nextDuplicateTitle(base: title)
        let appliesArray = applicableTypes.map { $0.rawValue }.sorted()
        let resolvedApplicableTypes: [String] =
            aiKind == .image ? ["image"] : appliesArray
        let descriptor = CustomAIDescriptor(
            id: newID,
            title: newTitle,
            promptTemplate: aiPrompt,
            providerID: aiProviderID,
            applicableTypes: resolvedApplicableTypes,
            enabled: true,
            kind: aiKind,
            requiredTraits: requiredTraits.sorted(),
            forbiddenTraits: forbiddenTraits
        )
        // Insert directly after the original — see duplicate-
        // Transformation comment above for rationale.
        registry.upsertCustomAI(descriptor, after: original.id)
        if let onOpenSibling = onOpenSibling {
            onOpenSibling(.editAI(descriptor))
        } else {
            onClose()
        }
    }

    /// Produce a fresh "Foo 2" / "Foo 3" style title that doesn't
    /// collide with any existing action in the registry. Two
    /// twists worth spelling out:
    ///
    ///   • If the input already ends in " N" (a trailing space-
    ///     and-integer), we increment N instead of appending a
    ///     fresh " 2" — duplicating "Translate 2" gives
    ///     "Translate 3", not "Translate 2 2".
    ///   • The collision check walks every action title in the
    ///     registry (built-ins + customs + AI), case-sensitive,
    ///     and keeps bumping the suffix until the name is unique.
    @MainActor
    private func nextDuplicateTitle(base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        var root = trimmed
        var n = 2
        // Detect trailing " N" so a second duplicate of "Foo 2"
        // produces "Foo 3" rather than "Foo 2 2".
        if let regex = try? NSRegularExpression(pattern: #"\s+(\d+)$"#),
           let m = regex.firstMatch(in: trimmed,
                                    range: NSRange(trimmed.startIndex..., in: trimmed)),
           let numRange = Range(m.range(at: 1), in: trimmed),
           let parsed = Int(trimmed[numRange]),
           let fullRange = Range(m.range, in: trimmed) {
            root = String(trimmed[trimmed.startIndex..<fullRange.lowerBound])
            n = parsed + 1
        }
        let existingTitles = Set(registry.actions.map { $0.title })
        while existingTitles.contains("\(root) \(n)") { n += 1 }
        return "\(root) \(n)"
    }

    private var canSave: Bool {
        switch kind {
        case .builtin:
            return !builtinID.isEmpty || (isEditing && currentActionID != nil)
        case .transformation:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .ai:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
                && !aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // MARK: - Run / Save / Load

    private var currentActionID: String? {
        switch context {
        case .createNew:
            switch kind {
            case .builtin: return builtinID.isEmpty ? nil : builtinID
            case .transformation, .ai: return nil  // assigned on save
            }
        case .editBuiltin(let id, _, _): return id
        case .editTransformation(let d): return d.id
        case .editAI(let d): return d.id
        }
    }

    private func loadInitialState() {
        switch context {
        case .createNew:
            kind = .transformation
            applicableTypes = [.text]
            transformationParams = transformationEngine.defaultParameters
            // New AI actions default to "" → follow the user's default provider.
            aiProviderID = ""
        case .editBuiltin(let id, let defaultTitle, _):
            kind = .builtin
            builtinID = id
            title = registry.config.customTitles[id] ?? defaultTitle
            hotkey = registry.hotkey(for: id)
            applicableTypes = inferApplicableTypes(builtinID: id)
        case .editTransformation(let d):
            kind = .transformation
            title = d.title
            hotkey = registry.hotkey(for: d.id)
            applicableTypes = Set(d.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
            requiredTraits = Set(d.requiredTraits)
            forbiddenTraits = d.forbiddenTraits
            if let engine = d.engine {
                transformationEngine = engine
                transformationParams = d.parameters
            }
        case .editAI(let d):
            kind = .ai
            title = d.title
            hotkey = registry.hotkey(for: d.id)
            applicableTypes = Set(d.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
            requiredTraits = Set(d.requiredTraits)
            forbiddenTraits = d.forbiddenTraits
            aiPrompt = d.promptTemplate
            aiProviderID = d.providerID
            aiKind = d.kind     // image-mode picker honours existing descriptor
        }
        // Pre-fill the Test panel Input. Two render modes:
        //
        //   • Image-applicable actions (OCR / Grayscale / AI: Watercolor
        //     / …) — Input panel shows an actual image, not text.
        //     Priority for the image: user's persisted custom image,
        //     then a procedurally-generated sample.
        //
        //   • Everything else — Input panel shows a TextEditor.
        //     Priority: user's persisted text override, curated default,
        //     empty (user-defined actions with no example yet).
        if let id = currentActionID {
            // Image-mode actions take their own branch.
            if isImageActionID(id) {
                testInputIsImage = true
                if let rel = registry.testImageRel(forActionID: id),
                   FileManager.default.fileExists(atPath:
                        AppStorage.imagesDir.appendingPathComponent(rel).path) {
                    testImageItem = imageItemFromRel(rel)
                } else {
                    testImageItem = ActionTestSamples.makeSampleImageItem()
                }
                // We still call testSample for the placeholder string so
                // it shows under the image (or in the descriptive text
                // for action types that have both).
                let sample = registry.testSample(forActionID: id)
                originalTestSample = sample
                testInput = sample ?? ""
            } else if testInput.isEmpty {
                testInputIsImage = false
                let sample = registry.testSample(forActionID: id)
                originalTestSample = sample
                testInput = sample ?? ""
            }
        }
        // Pin Provider picker to a working provider for the loaded
        // action's mode. Without this the picker chip in image mode
        // would show "Default · Anthropic Claude" while runtime
        // soft-falls back to OpenAI — visible lie.
        autoSelectProviderForCurrentKind()
    }

    /// Whether the action being edited accepts image INPUT (and so
    /// the Input panel renders an image-preview drop target instead
    /// of a text editor). Image→image actions take an image in;
    /// text→image takes text in (no image preview needed) even
    /// though the output is an image.
    @MainActor
    private func isImageActionID(_ id: String) -> Bool {
        // AI image (image→image) — honour the live `aiKind` picker.
        // textToImage stays text-input so it falls through to the
        // text editor path below.
        if kind == .ai && aiKind == .image { return true }
        // Built-in / transformation actions — probe via registry helper
        // (uses isApplicable against a synthetic image clip).
        return registry.actionAcceptsImage(id)
    }

    /// Build a transient ClipboardItem pointing at an existing image
    /// file in `AppStorage.imagesDir`. Used to load a previously-
    /// persisted custom test image back into the editor.
    @MainActor
    private func imageItemFromRel(_ rel: String) -> ClipboardItem? {
        let url = AppStorage.imagesDir.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return nil }
        // Also write to blobs/ so PasteboardWriter / image actions
        // that look up `public.png` representation find the bytes.
        let blobName = rel + ".bin"
        let blobURL = AppStorage.blobsDir.appendingPathComponent(blobName)
        try? data.write(to: blobURL)
        let s = img.size
        let (w, h): (Int, Int) = {
            if let rep = img.representations.first {
                return (rep.pixelsWide, rep.pixelsHigh)
            }
            return (Int(s.width), Int(s.height))
        }()
        return ClipboardItem(
            id: UUID(),
            semantic: .image,
            createdAt: Date(),
            representations: ["public.png": blobName],
            typesOrdered: ["public.png"],
            previewText: "Custom test image \(data.count / 1024) KB",
            previewImageRel: rel,
            originalImageWidth: w,
            originalImageHeight: h,
            originalImageFileSize: data.count,
            imageFormat: "PNG",
            sourceBundleID: nil,
            sourceAppName: "Editor Test",
            sourceWindowTitle: nil,
            tags: []
        )
    }

    /// Drag-drop handler. Copies the dropped image file into
    /// `AppStorage.imagesDir` under a stable per-action filename so
    /// repeated drops overwrite cleanly, then refreshes the in-
    /// memory `testImageItem` and persists the rel via
    /// `registry.setTestImageRel`.
    @MainActor
    private func handleDroppedImage(at sourceURL: URL) {
        guard let id = currentActionID else { return }
        // Sanity-check the file is a readable image format.
        guard let data = try? Data(contentsOf: sourceURL),
              NSImage(data: data) != nil else { return }
        // Re-encode JPEG / HEIC / etc to PNG so the standard
        // previewImageRel-as-PNG assumption holds throughout the
        // image-action paths. PNG is also what gpt-image-1 wants.
        let pngData: Data = {
            if data.count > 8,
               data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 {
                return data
            }
            if let img = NSImage(data: data),
               let tiff = img.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff),
               let png = bmp.representation(using: .png, properties: [:]) {
                return png
            }
            return data
        }()
        let slug = id.replacingOccurrences(of: ".", with: "_")
        let rel = "drpaste-custom-sample-\(slug).png"
        let url = AppStorage.imagesDir.appendingPathComponent(rel)
        do {
            try pngData.write(to: url, options: .atomic)
        } catch {
            return
        }
        registry.setTestImageRel(rel, forActionID: id)
        testImageItem = imageItemFromRel(rel)
    }

    /// "Reset to default" — drop the user's custom image override and
    /// regenerate the procedural sample. Bound to the small "Reset"
    /// button under the image preview.
    @MainActor
    private func resetTestImageToProcedural() {
        guard let id = currentActionID else { return }
        registry.setTestImageRel(nil, forActionID: id)
        testImageItem = ActionTestSamples.makeSampleImageItem()
    }

    private func inferApplicableTypes(builtinID: String) -> Set<SemanticKind> {
        guard let action = registry.actions.first(where: { $0.id == builtinID }) else {
            return [.text]
        }
        var result: Set<SemanticKind> = []
        for kind in allTypes {
            let sample = SettingsSamples.sample(for: kind)
            let ctx = ContextDetector.detect(sample)
            if action.isApplicable(item: sample, context: ctx) {
                result.insert(kind)
            }
        }
        return result.isEmpty ? [.text] : result
    }

    private func save() {
        let appliesArray = applicableTypes.map { $0.rawValue }.sorted()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve target id first so hotkey conflict resolution can use it.
        let targetID: String
        switch kind {
        case .builtin:
            guard let id = currentActionID else { return }
            targetID = id
        case .transformation:
            if case .editTransformation(let existing) = context { targetID = existing.id }
            else { targetID = "user.transform.\(UUID().uuidString.prefix(8))" }
        case .ai:
            if case .editAI(let existing) = context { targetID = existing.id }
            else { targetID = "user.\(UUID().uuidString.prefix(8))" }
        }

        // Auto-steal: if the hotkey we're about to bind is currently held by
        // another action, unbind it there. The recorder already warned the user.
        if let hk = hotkey,
           let other = registry.conflictingAction(for: hk, excludingID: targetID) {
            registry.setHotkey(nil, for: other)
        }

        switch kind {
        case .builtin:
            let defaultTitle = registry.actions.first(where: { $0.id == targetID })?.title ?? targetID
            if trimmedTitle.isEmpty || trimmedTitle == defaultTitle {
                registry.setCustomTitle(nil, forActionID: targetID)
            } else {
                registry.setCustomTitle(trimmedTitle, forActionID: targetID)
            }
            registry.setHotkey(hotkey, for: targetID)
            // Picking a built-in handler in "+ New" mode is an explicit
            // gesture that the user wants this action in their list —
            // even if it was disabled by curated defaults. Without this,
            // Save would silently no-op on disabled handlers and feel
            // broken ("I picked Save and nothing happened"). Edit-mode
            // saves leave the enabled flag alone — the user can still
            // disable a built-in via the action row toggle afterwards.
            if case .createNew = context {
                registry.setEnabled(true, for: targetID)
            }

        case .transformation:
            let descriptor = CustomTransformationDescriptor(
                id: targetID,
                title: trimmedTitle,
                engineID: transformationEngine.rawValue,
                parameters: transformationParams,
                applicableTypes: appliesArray,
                enabled: true,
                requiredTraits: requiredTraits.sorted(),
                forbiddenTraits: forbiddenTraits
            )
            registry.upsertCustomTransformation(descriptor)
            registry.setHotkey(hotkey, for: targetID)

        case .ai:
            // `aiKind` is the source of truth — picker at the top of
            // the AI section sets it on .createNew, and loadInitialState
            // reads it from the descriptor on .editAI(desc). The user
            // can flip kind at any time and Save honours their choice.
            // applicableTypes is force-set to ["image"] when the user
            // picks Image mode (image-AI routing ignores the field
            // anyway, but storing the matching value keeps actions.json
            // self-consistent).
            let resolvedApplicableTypes: [String] =
                aiKind == .image ? ["image"] : appliesArray
            let descriptor = CustomAIDescriptor(
                id: targetID,
                title: trimmedTitle,
                promptTemplate: aiPrompt,
                providerID: aiProviderID,
                applicableTypes: resolvedApplicableTypes,
                enabled: true,
                kind: aiKind,
                requiredTraits: requiredTraits.sorted(),
                forbiddenTraits: forbiddenTraits
            )
            registry.upsertCustomAI(descriptor)
            registry.setHotkey(hotkey, for: targetID)
        }
        // Persist the test-panel Input sample only if the user actually
        // modified it this session. Diffing against the originalTestSample
        // captured at dialog open avoids writing a stale curated-default
        // value back as an override (which would freeze it against
        // future updates to the curated table). The registry helper
        // further normalises by removing the override when the new
        // value matches the current curated default — so an explicit
        // "type the curated text back in" gesture also clears any
        // prior stale override.
        if testInput != (originalTestSample ?? "") {
            registry.setTestSample(testInput, forActionID: targetID)
        }
        onClose()
    }

    private func runTest() {
        // #A57 — cancel the previous test task before starting a new
        // one. Without this a fast double-click on Run leaves two
        // races running at once and whichever finishes second stomps
        // the live testOutcome with potentially-stale data. For AI
        // calls it also burns tokens on a result that's about to be
        // thrown away.
        testTask?.cancel()
        testTask = nil
        testRunning = true
        testOutcome = nil
        testInflight = nil
        testElapsed = 0
        testTickTimer?.invalidate()
        testTickTimer = nil

        // Build the input clip. Three modes:
        //
        //   • Image actions      — use `testImageItem` (persisted
        //                          custom or procedural sample).
        //   • Rich-text actions  — parse `testInput` as markdown,
        //                          synthesise an RTF blob, build a
        //                          .richText item with public.rtf
        //                          representation. Without this the
        //                          actions (rich_to_wiki / _md / _html
        //                          / _unicode_style / paste_as_text /
        //                          clean_formatting) get no RTF to
        //                          read and produce trivial output.
        //   • Everything else    — plain .text item with testInput
        //                          as previewText.
        let inputItem: ClipboardItem
        if testInputIsImage {
            if let img = testImageItem {
                inputItem = img
            } else if let img = ActionTestSamples.makeSampleImageItem() {
                inputItem = img
                testImageItem = img
            } else {
                testOutcome = .failed(
                    original: makeTextProbe(),
                    reason: "Couldn't generate sample image for the test.",
                    recovery: nil
                )
                testRunning = false
                return
            }
        } else if let id = currentActionID,
                  registry.actionRequiresRichText(id),
                  let rich = ActionTestSamples.makeRichTextItem(markdown: testInput) {
            inputItem = rich
        } else {
            inputItem = ClipboardItem(
                id: UUID(),
                semantic: .text,
                createdAt: Date(),
                representations: [:],
                typesOrdered: [],
                previewText: testInput,
                previewImageRel: nil,
                sourceBundleID: nil,
                sourceAppName: "Editor Test",
                sourceWindowTitle: nil,
                tags: []
            )
        }
        let ctx = ContextDetector.detect(inputItem)
        // `aiKind` is the live source of truth — covers newly-created
        // and existing image/text-to-image AI actions. Three modes:
        //   - text       → AIAction text→text
        //   - image      → AIImageAction image→image
        //   - textToImage → AITextToImageAction text→image
        let isImageAI: Bool = (kind == .ai && aiKind == .image)
        let isTextToImageAI: Bool = (kind == .ai && aiKind == .textToImage)

        switch kind {
        case .builtin:
            guard let id = currentActionID,
                  let action = registry.actions.first(where: { $0.id == id }) else {
                testOutcome = .failed(
                    original: inputItem,
                    reason: "No built-in selected.",
                    recovery: nil
                )
                testRunning = false
                return
            }
            testTask = Task {
                let outcome = await action.apply(item: inputItem, context: ctx)
                await MainActor.run {
                    guard !Task.isCancelled else { return }   // #A57
                    testOutcome = outcome
                    testRunning = false
                    testTask = nil
                }
            }
        case .transformation:
            do {
                let result = try TransformationRuntime.apply(engine: transformationEngine,
                                                              input: testInput,
                                                              params: transformationParams)
                testOutcome = .preview(makeTextItem(result, from: inputItem))
            } catch let TransformationError.invalidRegex(msg) {
                testOutcome = .failed(
                    original: inputItem,
                    reason: "Invalid regex: \(msg)",
                    recovery: nil
                )
            } catch {
                testOutcome = .failed(
                    original: inputItem,
                    reason: error.localizedDescription,
                    recovery: nil
                )
            }
            testRunning = false
        case .ai:
            // Set up the AI inflight chrome so the Output pane shows the
            // same "Provider · Model · 4.2s" loading state as BigHUD/MiniHUD.
            // Resolve the provider label via AIProviderRegistry — same path
            // AppDelegate.makeAIInflight uses for the HUD chrome.
            let defaultTitle: String
            if isImageAI { defaultTitle = "AI image test" }
            else if isTextToImageAI { defaultTitle = "AI text→image test" }
            else { defaultTitle = "AI test" }
            testInflight = resolveTestInflight(actionTitle:
                title.isEmpty ? defaultTitle : title)
            startTestTickTimer()

            let resolvedProviderID: String? = aiProviderID.isEmpty ? nil : aiProviderID
            if isImageAI {
                let action = AIImageAction(
                    id: "test.ai_image",
                    title: title.isEmpty ? defaultTitle : title,
                    promptTemplate: aiPrompt,
                    providerID: resolvedProviderID
                )
                testTask = Task {
                    let outcome = await action.apply(item: inputItem, context: ctx)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }   // #A57
                        testOutcome = outcome
                        testRunning = false
                        stopTestTickTimer()
                        testInflight = nil
                        testTask = nil
                    }
                }
            } else if isTextToImageAI {
                let action = AITextToImageAction(
                    id: "test.ai_text_to_image",
                    title: title.isEmpty ? defaultTitle : title,
                    promptTemplate: aiPrompt,
                    providerID: resolvedProviderID
                )
                testTask = Task {
                    let outcome = await action.apply(item: inputItem, context: ctx)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }   // #A57
                        testOutcome = outcome
                        testRunning = false
                        stopTestTickTimer()
                        testInflight = nil
                        testTask = nil
                    }
                }
            } else {
                let action = AIAction(
                    id: "test.ai",
                    title: title.isEmpty ? "AI test" : title,
                    promptTemplate: aiPrompt,
                    providerID: aiProviderID,
                    applicableTypes: applicableTypes.isEmpty ? [.text] : applicableTypes
                )
                testTask = Task {
                    let outcome = await action.apply(item: inputItem, context: ctx)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }   // #A57
                        testOutcome = outcome
                        testRunning = false
                        stopTestTickTimer()
                        testInflight = nil
                        testTask = nil
                    }
                }
            }
        }
    }

    // MARK: - Test helpers

    /// Probe item used by `runTest` to detect whether a built-in action
    /// is image-applicable. We need a probe with non-zero image content
    /// so the action's `isApplicable` resolves correctly via the
    /// `.image` context.
    @MainActor
    private func makeImageProbe() -> ClipboardItem {
        // 1×1 PNG, smallest valid image — purely for predicate
        // resolution, not actual rendering. The real test input uses
        // `ActionTestSamples.makeSampleImageItem()`.
        var item = ClipboardItem(
            id: UUID(),
            semantic: .image,
            createdAt: Date(),
            representations: [:],
            typesOrdered: [],
            previewText: nil,
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: "Editor probe",
            sourceWindowTitle: nil,
            tags: []
        )
        item.semantic = .image
        return item
    }

    private func makeTextProbe() -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            semantic: .text,
            createdAt: Date(),
            representations: [:],
            typesOrdered: [],
            previewText: "x",
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: "Editor probe",
            sourceWindowTitle: nil,
            tags: []
        )
    }

    /// Build the in-flight descriptor for the loading panel. Resolves the
    /// active provider (per-action override or default) for the
    /// "Provider · Model" line. Matches `AppDelegate.makeAIInflight` so
    /// the user sees identical chrome in Settings as they would in the
    /// live HUD when this action runs.
    @MainActor
    private func resolveTestInflight(actionTitle: String) -> AIInflight {
        let isImageAI: Bool = (kind == .ai
                                && (aiKind == .image || aiKind == .textToImage))
        // Walk the SAME chain runtime uses — `effectiveProvider()`
        // mirrors `AIImageAction.resolveProvider` (per-action override
        // → default → soft-fallback to any enabled image-capable
        // provider when the operation needs images). Without this
        // the Output panel showed "Anthropic Claude · gpt-image-1"
        // for image actions whose chat default was Anthropic but
        // whose REAL execution rerouted to OpenAI via soft fallback
        // — lying about which provider actually ran the request.
        if let cp = effectiveProvider() {
            let modelLabel: String
            if isImageAI {
                modelLabel = (cp.kind == .gemini)
                    ? "gemini-2.5-flash-image-preview"
                    : "gpt-image-1"
            } else {
                modelLabel = cp.model
            }
            return AIInflight(
                providerLabel: cp.displayName,
                modelName: modelLabel,
                actionTitle: actionTitle,
                startedAt: Date()
            )
        }
        return AIInflight(
            providerLabel: "AI",
            modelName: isImageAI ? "gpt-image-1" : "unknown",
            actionTitle: actionTitle,
            startedAt: Date()
        )
    }

    @MainActor
    private func startTestTickTimer() {
        stopTestTickTimer()
        let started = testInflight?.startedAt ?? Date()
        testTickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.testElapsed = Date().timeIntervalSince(started)
            }
        }
    }

    @MainActor
    private func stopTestTickTimer() {
        testTickTimer?.invalidate()
        testTickTimer = nil
    }

    // `describeOutcome` / `describeImageOutcome` were the plain-text
    // summarisers for the legacy `testOutput` TextEditor mirror.
    // Replaced by `TestOutputPane` which renders the live ApplyOutcome
    // (spinner / failure notice / image preview / etc.) directly, so
    // no string flattening is needed.
}

// MARK: - Built-in handler categories

/// Buckets available built-in handlers in the ActionEditor picker so users
/// can scan the menu by functional area (Image, Rich text, URL, …) instead
/// of hunting through one long alphabetical list. Bucketing is
/// namespace-driven (`builtin.image_*` → Image, etc.) with a small explicit
/// override map for IDs that don't follow the prefix.
private enum BuiltinHandlerCategory: String, CaseIterable, Identifiable {
    case image
    case richText
    case url
    case table
    case json
    case files
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image:    return "Image"
        case .richText: return "Rich text"
        case .url:      return "URL"
        case .table:    return "Table"
        case .json:     return "JSON"
        case .files:    return "Files"
        case .text:     return "Text & utility"
        }
    }

    /// IDs that don't follow the namespace prefix get mapped explicitly.
    /// Anything else falls back to prefix detection in `of(_:)`.
    ///
    /// Convention v2 (#A74, 0.56.0): the prefix is
    /// `builtin.<content_kind>.` so the dispatch below maps content_kind
    /// directly to the category. The only overrides are special-purpose
    /// actions whose category in the editor differs from their content
    /// kind (e.g. `text.generate_qr` produces an image so it edits in the
    /// Image category panel).
    private static let overrides: [String: BuiltinHandlerCategory] = [
        "builtin.text.generate_qr": .image
    ]

    static func of(_ actionID: String) -> BuiltinHandlerCategory {
        if let override = overrides[actionID] { return override }
        if actionID.hasPrefix("builtin.image.") { return .image }
        if actionID.hasPrefix("builtin.rich.")  { return .richText }
        if actionID.hasPrefix("builtin.url.")   { return .url }
        if actionID.hasPrefix("builtin.table.") { return .table }
        if actionID.hasPrefix("builtin.json.")  { return .json }
        if actionID.hasPrefix("builtin.files.") { return .files }
        return .text
    }
}

// MARK: - Regex syntax help sidebar

struct RegexSyntaxHelp: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Regex syntax cheatsheet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                section("Character classes", items: [
                    (".", "any character"),
                    ("\\d", "digit"),
                    ("\\D", "non-digit"),
                    ("\\w", "word char"),
                    ("\\W", "non-word"),
                    ("\\s", "whitespace"),
                    ("\\S", "non-whitespace"),
                    ("[abc]", "any of a/b/c"),
                    ("[^abc]", "none of a/b/c"),
                    ("[a-z]", "range")
                ])

                section("Quantifiers", items: [
                    ("*", "0 or more"),
                    ("+", "1 or more"),
                    ("?", "0 or 1"),
                    ("{n}", "exactly n"),
                    ("{n,m}", "n to m")
                ])

                section("Anchors", items: [
                    ("^", "start of line"),
                    ("$", "end of line"),
                    ("\\b", "word boundary"),
                    ("\\B", "non-boundary")
                ])

                section("Groups", items: [
                    ("(...)", "capture group"),
                    ("(?:...)", "non-capturing"),
                    ("$1, $2", "ref in replacement"),
                    ("|", "alternation")
                ])

                section("Special", items: [
                    ("\\n", "newline"),
                    ("\\t", "tab"),
                    ("\\\\", "literal \\"),
                    ("\\.", "literal .")
                ])

                Text("Example: replace \\b\\w+ with [$0] to wrap each word in brackets.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 4)
        }
    }

    private func section(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Text(item.0)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 60, alignment: .leading)
                        .foregroundStyle(Color.accentColor)
                    Text(item.1)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
