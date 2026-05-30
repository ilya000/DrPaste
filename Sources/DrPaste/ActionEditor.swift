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
    private var window: NSWindow?

    /// Open a new editor window for `context`. Any previously-opened
    /// editor is closed first — the editor is intended to be modal-ish
    /// (only one at a time). `onClose` is invoked once the user clicks
    /// Cancel / Save / closes the window via the red traffic-light
    /// button so the caller can reset its `editorContext` state.
    func show(context: ActionEditorContext,
              registry: ActionRegistry,
              onClose: @escaping () -> Void) {
        close()

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

        // Wrap the SwiftUI editor so closing always tears down the
        // window before invoking the caller's onClose — otherwise the
        // SwiftUI state would race with our window teardown.
        let view = ActionEditor(context: context, registry: registry) { [weak self] in
            self?.close()
            onClose()
        }
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
        // Belt-and-braces against `.center()` placing the bottom edge
        // behind the Dock / menu bar on small displays — clamp into
        // `visibleFrame` (which excludes both).
        clampToVisibleFrame(w)
        // Wire the red traffic-light: dismissing the window with the
        // close button should fire onClose so the caller resets state.
        let delegate = ActionEditorWindowDelegate(onClose: { [weak self] in
            self?.window = nil
            onClose()
        })
        w.delegate = delegate
        retainDelegate = delegate
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        retainDelegate = nil
    }

    /// Retain the delegate alongside the window — NSWindow.delegate is
    /// weak. Without this the delegate would deallocate as soon as the
    /// outer scope returned.
    private var retainDelegate: ActionEditorWindowDelegate?

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

    // Mode (segmented picker) — locked when editing existing
    @State private var kind: ActionEditorKind = .builtin

    // Common fields
    @State private var title: String = ""
    @State private var hotkey: ActionHotkey? = nil
    @State private var applicableTypes: Set<SemanticKind> = []

    // Mode-specific state
    @State private var builtinID: String = ""
    @State private var transformationEngine: TransformationEngine = .regexReplace
    @State private var transformationParams: [String: String] = [:]
    @State private var aiPrompt: String = ""
    @State private var aiProviderID: String = "anthropic"

    // Test panel
    @State private var testInput: String = ""
    @State private var testOutput: String = ""
    @State private var testRunning: Bool = false

    // Misc
    @State private var conflictMessage: String? = nil
    @State private var showRegexHelp: Bool = false

    private let allTypes: [SemanticKind] = [
        .text, .richText, .url, .email, .json, .code, .markdown, .table, .image, .pdf, .files
    ]

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
                    let applicable = isTypeApplicable(type)
                    Toggle(isOn: Binding(
                        get: { applicableTypes.contains(type) },
                        set: { isOn in
                            guard applicable else { return }
                            if isOn { applicableTypes.insert(type) }
                            else { applicableTypes.remove(type) }
                        }
                    )) {
                        Text(type.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(applicable ? .primary : .tertiary)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!applicable)
                }
            }
        }
    }

    /// #12: Is the action capable of handling this content type at all?
    /// Inapplicable types are shown disabled and unchecked.
    private func isTypeApplicable(_ type: SemanticKind) -> Bool {
        switch kind {
        case .builtin:
            let id: String
            if case .editBuiltin(let actionID, _, _) = context { id = actionID }
            else if !builtinID.isEmpty { id = builtinID }
            else { return true }
            guard let action = registry.actions.first(where: { $0.id == id }) else { return true }
            let sample = SettingsSamples.sample(for: type)
            let ctx = ContextDetector.detect(sample)
            return action.isApplicable(item: sample, context: ctx)
        case .transformation:
            // Text-based engines apply to text-based content. Image/files engines not yet defined.
            return [.text, .richText, .markdown, .code, .table, .url, .email, .json].contains(type)
        case .ai:
            // AI prompts operate on text content. Images/PDF/files require extraction first.
            return [.text, .richText, .markdown, .code, .url, .email, .json, .table].contains(type)
        }
    }

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
        let descriptorBackedIDs = Set(registry.config.customTransformations.map(\.id))
        return registry.actions.filter { action in
            // Genuine hardcoded built-ins only. Identity is the pinned anchor
            // (cannot be re-created via this dialog). Descriptor-backed ones
            // (`DefaultTransformationSeed` entries) are edited through the
            // Transformation mode pencil in the Actions list; surfacing them
            // here too just clutters the menu.
            guard action.id.hasPrefix("builtin.") else { return false }
            guard action.id != "builtin.identity" else { return false }
            guard !descriptorBackedIDs.contains(action.id) else { return false }
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
        // description (which the editor already prints above this view) and
        // run on the input as-is.
        case .trim,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking,
             .cyrillicToLatin:
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
            HStack {
                Text("Provider:").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: $aiProviderID) {
                    // Sentinel "" maps to "use whatever is set as default".
                    let defaultName = AIProviderRegistry.shared.defaultProvider?.displayName
                    Text("Default" + (defaultName.map { " (\($0))" } ?? "")).tag("")
                    Divider()
                    ForEach(AIProviderRegistry.shared.config.providers) { p in
                        Text(p.displayName).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if aiProviderID.isEmpty {
                HStack(spacing: 4) {
                    Spacer().frame(width: 100)
                    Text("This action follows the default provider. Change the default in Settings → AI and this action follows automatically.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
            Text("Tip: write what the AI should do with the input. The clipboard text is automatically passed as the user message.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    Text("Input").font(.caption2).foregroundStyle(.secondary)
                    TextEditor(text: $testInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output").font(.caption2).foregroundStyle(.secondary)
                    TextEditor(text: .constant(testOutput))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            // Delete is available only for user-created actions (transformation / AI).
            if case .editTransformation(let desc) = context {
                Button(role: .destructive) {
                    registry.removeCustomTransformation(id: desc.id)
                    registry.setHotkey(nil, for: desc.id)
                    onClose()
                } label: { Label("Delete", systemImage: "trash") }
            } else if case .editAI(let desc) = context {
                Button(role: .destructive) {
                    registry.removeCustomAI(id: desc.id)
                    registry.setHotkey(nil, for: desc.id)
                    onClose()
                } label: { Label("Delete", systemImage: "trash") }
            }
            Spacer()
            Button("Cancel") { onClose() }
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
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
            if let engine = d.engine {
                transformationEngine = engine
                transformationParams = d.parameters
            }
        case .editAI(let d):
            kind = .ai
            title = d.title
            hotkey = registry.hotkey(for: d.id)
            applicableTypes = Set(d.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
            aiPrompt = d.promptTemplate
            aiProviderID = d.providerID
        }
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

        case .transformation:
            let descriptor = CustomTransformationDescriptor(
                id: targetID,
                title: trimmedTitle,
                engineID: transformationEngine.rawValue,
                parameters: transformationParams,
                applicableTypes: appliesArray,
                enabled: true
            )
            registry.upsertCustomTransformation(descriptor)
            registry.setHotkey(hotkey, for: targetID)

        case .ai:
            let descriptor = CustomAIDescriptor(
                id: targetID,
                title: trimmedTitle,
                promptTemplate: aiPrompt,
                providerID: aiProviderID,
                applicableTypes: appliesArray,
                enabled: true
            )
            registry.upsertCustomAI(descriptor)
            registry.setHotkey(hotkey, for: targetID)
        }
        onClose()
    }

    private func runTest() {
        testRunning = true
        testOutput = ""

        let inputItem = ClipboardItem(
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
        let ctx = ContextDetector.detect(inputItem)

        switch kind {
        case .builtin:
            guard let id = currentActionID,
                  let action = registry.actions.first(where: { $0.id == id }) else {
                testOutput = "(no built-in selected)"
                testRunning = false
                return
            }
            Task {
                let outcome = await action.apply(item: inputItem, context: ctx)
                await MainActor.run {
                    testOutput = describeOutcome(outcome)
                    testRunning = false
                }
            }
        case .transformation:
            do {
                let result = try TransformationRuntime.apply(engine: transformationEngine,
                                                              input: testInput,
                                                              params: transformationParams)
                testOutput = result
            } catch let TransformationError.invalidRegex(msg) {
                testOutput = "⚠ Invalid regex: \(msg)"
            } catch {
                testOutput = "⚠ \(error.localizedDescription)"
            }
            testRunning = false
        case .ai:
            let action = AIAction(
                id: "test.ai",
                title: title.isEmpty ? "AI test" : title,
                promptTemplate: aiPrompt,
                providerID: aiProviderID,
                applicableTypes: applicableTypes.isEmpty ? [.text] : applicableTypes
            )
            Task {
                let outcome = await action.apply(item: inputItem, context: ctx)
                await MainActor.run {
                    testOutput = describeOutcome(outcome)
                    testRunning = false
                }
            }
        }
    }

    private func describeOutcome(_ outcome: ApplyOutcome) -> String {
        switch outcome {
        case .preview(let item): return item.previewText ?? ""
        case .failed(_, let reason, _): return "⚠ \(reason)"
        case .sideEffect(let desc, _): return "→ \(desc)"
        case .alternativeCommit(let item, _): return item.previewText ?? ""
        }
    }
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
    private static let overrides: [String: BuiltinHandlerCategory] = [
        "builtin.layout_repair":    .text,
        "builtin.paste_as_text":    .richText,
        "builtin.clean_formatting": .richText,
        "builtin.generate_qr":      .image,
        "builtin.type_slowly":      .text
    ]

    static func of(_ actionID: String) -> BuiltinHandlerCategory {
        if let override = overrides[actionID] { return override }
        if actionID.hasPrefix("builtin.image_") { return .image }
        if actionID.hasPrefix("builtin.rich_")  { return .richText }
        if actionID.hasPrefix("builtin.url_")   { return .url }
        if actionID.hasPrefix("builtin.table_") { return .table }
        if actionID.hasPrefix("builtin.json_")  { return .json }
        if actionID.hasPrefix("builtin.files_") { return .files }
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
