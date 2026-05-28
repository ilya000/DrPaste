//
//  ActionEditor.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Унифицированный action editor (0.7.0): один диалог для трёх режимов:
//  1. Built-in handler — pick pre-made + override metadata
//  2. Transformation engine — regex / find / prepend / append / wrap / line filter
//  3. AI prompt — pick provider, write prompt
//
//  Все режимы делят общие поля: title, hotkey, applicable types, test panel.
//

import SwiftUI

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

    private let allTypes: [SemanticKind] = [.text, .richText, .url, .json, .table, .markdown, .code, .files]

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
        .frame(width: showRegexHelp && kind == .transformation ? 880 : 620, height: 720)
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
            Text("Hotkey").font(.caption).foregroundStyle(.secondary)
            HotkeyRecorderField(
                hotkey: $hotkey,
                onConflict: { msg in conflictMessage = msg },
                conflictChecker: { hk in
                    registry.conflictingAction(for: hk, excludingID: currentActionID)
                }
            )
            if let msg = conflictMessage {
                Text(msg).font(.caption).foregroundStyle(.red)
            } else {
                Text("Direct trigger: pressing hotkey applies action to current clipboard and pastes immediately (no HUD).")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var applicableTypesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Applies to").font(.caption).foregroundStyle(.secondary)
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(allTypes, id: \.self) { type in
                    Toggle(isOn: Binding(
                        get: { applicableTypes.contains(type) },
                        set: { isOn in
                            if isOn { applicableTypes.insert(type) }
                            else { applicableTypes.remove(type) }
                        }
                    )) {
                        Text(type.displayName).font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                }
            }
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

    // Built-in: picker для existing action
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
                    ForEach(availableBuiltins, id: \.id) { action in
                        Text(action.title).tag(action.id)
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
        registry.actions.filter { action in
            action.id.hasPrefix("builtin.")
                && action.id != "builtin.identity"   // identity не пере-настраивается
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
                ForEach(TransformationEngine.allCases) { engine in
                    Label(engine.displayName, systemImage: engine.iconName).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: transformationEngine) { newEngine in
                // Сбрасываем параметры к defaults новой engine, если меняем тип
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
                    ForEach(AIProviderRegistry.shared.config.providers) { p in
                        Text(p.displayName).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
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
            // Delete только для user-created actions (transformation / AI)
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
            if let firstProvider = AIProviderRegistry.shared.config.providers.first {
                aiProviderID = firstProvider.id
            }
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

        switch kind {
        case .builtin:
            // ID built-in либо из context (edit), либо из dropdown (create)
            guard let id = currentActionID else { return }
            let defaultTitle = registry.actions.first(where: { $0.id == id })?.title ?? id
            if trimmedTitle.isEmpty || trimmedTitle == defaultTitle {
                registry.setCustomTitle(nil, forActionID: id)
            } else {
                registry.setCustomTitle(trimmedTitle, forActionID: id)
            }
            registry.setHotkey(hotkey, for: id)
            // Built-in применимость зашита в код — applicableTypes show-only

        case .transformation:
            let id: String
            if case .editTransformation(let existing) = context { id = existing.id }
            else { id = "user.transform.\(UUID().uuidString.prefix(8))" }
            let descriptor = CustomTransformationDescriptor(
                id: id,
                title: trimmedTitle,
                engineID: transformationEngine.rawValue,
                parameters: transformationParams,
                applicableTypes: appliesArray,
                enabled: true
            )
            registry.upsertCustomTransformation(descriptor)
            registry.setHotkey(hotkey, for: id)

        case .ai:
            let id: String
            if case .editAI(let existing) = context { id = existing.id }
            else { id = "user.\(UUID().uuidString.prefix(8))" }
            let descriptor = CustomAIDescriptor(
                id: id,
                title: trimmedTitle,
                promptTemplate: aiPrompt,
                providerID: aiProviderID,
                applicableTypes: appliesArray,
                enabled: true
            )
            registry.upsertCustomAI(descriptor)
            registry.setHotkey(hotkey, for: id)
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
