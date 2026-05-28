//
//  SettingsWindow.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Settings UI (Backlog #8): SwiftUI TabView с General, AI Providers, per-content-type tabs.
//  Каждый content tab — playground: sample input + Result pane + actions list с Run buttons.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Controller (NSWindow lifecycle)

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    let registry: ActionRegistry
    let store: ClipboardStore

    init(registry: ActionRegistry, store: ClipboardStore) {
        self.registry = registry
        self.store = store
    }

    func show() {
        if window == nil {
            let view = SettingsView(registry: registry, store: store)
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "DrPaste Settings"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 780, height: 540))
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.orderOut(nil) }
}

// MARK: - Root view

struct SettingsView: View {
    @ObservedObject var registry: ActionRegistry
    let store: ClipboardStore

    var body: some View {
        TabView {
            GeneralTab(registry: registry)
                .tabItem { Label("General", systemImage: "gear") }
            AIProvidersTab(registry: registry)
                .tabItem { Label("AI", systemImage: "sparkles") }
            ForEach(visibleContentTypes, id: \.self) { kind in
                ContentTypeTab(kind: kind, registry: registry, store: store)
                    .tabItem { Label(kind.displayName, systemImage: kind.sfSymbol) }
            }
            ImportExportTab(registry: registry)
                .tabItem { Label("Import/Export", systemImage: "square.and.arrow.up.on.square") }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
    }

    private var visibleContentTypes: [SemanticKind] {
        [.text, .richText, .url, .json, .table, .markdown, .code, .image, .files]
    }
}

// MARK: - General tab

struct GeneralTab: View {
    @ObservedObject var registry: ActionRegistry
    @State private var fontScale: Double = 1.0
    @State private var soundVolume: Double = 0.6

    var body: some View {
        Form {
            Section("Startup") {
                HStack {
                    Toggle("Launch DrPaste on login", isOn: .constant(false))
                        .disabled(true)
                        .help("Coming soon — will be available once DrPaste ships signed.")
                    Text("(coming soon)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            Section("iCloud sync") {
                HStack {
                    Toggle("Sync settings via iCloud", isOn: .constant(false))
                        .disabled(true)
                    Text("(coming soon)")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Text("When enabled, your action presets, AI provider configs, API keys, and preferences sync across all Macs signed in to the same Apple ID. Clipboard history stays local.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Include API keys (via iCloud Keychain)", isOn: .constant(true))
                    .disabled(true)
                Text("API keys are end-to-end encrypted by Apple. Requires iCloud Keychain to be enabled in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("HUD") {
                HStack {
                    Text("Font size:")
                    Slider(value: $fontScale, in: 0.7...1.6, step: 0.1)
                    Text(String(format: "%.1f×", fontScale))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                }
                Text("Hotkey: ⌥⌘V (V to paste, C to copy, X to cut & replace)")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Cut & Replace: start cursor on second item (skip just-cut)",
                       isOn: cursorOnSecondBinding)
                Text("When you ⌥⌘X, cursor jumps over the freshly cut content to the previous item in history. Default off matches native cut+paste behavior.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sound feedback") {
                HStack {
                    Text("Volume:")
                    Slider(value: $soundVolume, in: 0...1)
                    Text(String(format: "%.0f%%", soundVolume * 100))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                }
                ForEach([SoundCue.copySuccess, .copyFailure, .pasteSuccess, .pasteFailure, .typeTick, .delete], id: \.rawValue) { cue in
                    Toggle(cueLabel(cue), isOn: cueBinding(cue))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
        .onChange(of: fontScale) { v in
            UserDefaults.standard.set(v, forKey: "drpaste.hud.fontScale")
        }
        .onChange(of: soundVolume) { v in
            SoundFeedback.setVolume(Float(v))
            // #1 Sound preview — играем при изменении volume
            SoundFeedback.playPreview(.copySuccess)
        }
    }

    private func reload() {
        let v = UserDefaults.standard.double(forKey: "drpaste.hud.fontScale")
        fontScale = v == 0 ? 1.0 : v
        soundVolume = Double(SoundFeedback.currentVolume())
    }

    private var cursorOnSecondBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: "drpaste.hud.cursorOnSecondOnCut") },
            set: { UserDefaults.standard.set($0, forKey: "drpaste.hud.cursorOnSecondOnCut") }
        )
    }

    private func cueLabel(_ cue: SoundCue) -> String {
        switch cue {
        case .copySuccess: return "Play sound on copy success"
        case .copyFailure: return "Play sound on copy failure"
        case .pasteSuccess: return "Play sound on paste"
        case .pasteFailure: return "Play sound on action failure"
        case .typeTick: return "Play tick on Type Slowly characters"
        case .delete: return "Play sound on delete from history"
        }
    }

    private func cueBinding(_ cue: SoundCue) -> Binding<Bool> {
        Binding(
            get: { SoundFeedback.isEnabled(cue) },
            set: { newValue in
                SoundFeedback.setEnabled(newValue, for: cue)
                // #1 Sound preview: играем sample когда тогглят (всегда, чтобы user
                // услышал что это за звук, даже при выключении — последний preview)
                SoundFeedback.playPreview(cue)
            }
        )
    }
}

// MARK: - AI Providers tab (Multi-provider, правка #4)

struct AIProvidersTab: View {
    @ObservedObject var registry: ActionRegistry
    @ObservedObject private var providerRegistry = AIProviderRegistry.shared
    @State private var editingProvider: ConfiguredProvider? = nil
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Default provider:")
                Picker("", selection: defaultBinding) {
                    ForEach(providerRegistry.config.providers) { p in
                        Text(p.displayName).tag(p.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
                Spacer()
            }
            Text("Used for all custom AI actions unless overridden per action.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    let cloud = providerRegistry.config.providers.filter { !$0.kind.isLocal && $0.kind != .custom }
                    let local = providerRegistry.config.providers.filter { $0.kind.isLocal }
                    let custom = providerRegistry.config.providers.filter { $0.kind == .custom }

                    if !cloud.isEmpty {
                        sectionHeader("Cloud providers")
                        ForEach(cloud) { providerRow($0) }
                    }
                    if !local.isEmpty {
                        sectionHeader("Local providers")
                        ForEach(local) { providerRow($0) }
                    }
                    if !custom.isEmpty {
                        sectionHeader("Custom")
                        ForEach(custom) { providerRow($0) }
                    }
                }
            }

            HStack(spacing: 12) {
                Button { showingAddSheet = true } label: {
                    Label("Add provider…", systemImage: "plus.circle")
                }
                .controlSize(.small)
                Spacer()
            }
        }
        .padding()
        .sheet(item: $editingProvider) { p in
            ProviderEditor(provider: p) { result in
                if let cp = result.config {
                    providerRegistry.upsert(cp, apiKey: result.apiKey)
                    providerRegistry.invalidateCache()
                }
                editingProvider = nil
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ProviderAddSheet { kind in
                showingAddSheet = false
                if let kind = kind {
                    let id = newProviderID(for: kind)
                    let cp = ConfiguredProvider(
                        id: id, kind: kind,
                        displayName: kind.displayName,
                        model: kind.defaultModel,
                        baseURL: kind.defaultBaseURL
                    )
                    editingProvider = cp
                }
            }
        }
    }

    private var defaultBinding: Binding<String?> {
        Binding(
            get: { providerRegistry.config.defaultProviderID },
            set: { providerRegistry.setDefault(providerID: $0 ?? "") }
        )
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func providerRow(_ p: ConfiguredProvider) -> some View {
        HStack(spacing: 10) {
            let hasKey = APIKeyStorage.load(for: p.id) != nil
            let isReady = p.kind.isLocal || hasKey
            Circle()
                .fill(isReady ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.displayName).font(.system(size: 13, weight: .medium))
                Text(p.kind.isLocal
                     ? "Local · \(p.baseURL ?? "no URL") · \(p.model)"
                     : "\(isReady ? "Configured" : "Not configured") · \(p.model)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: enabledBinding(p))
                .labelsHidden()
            Button(isReady ? "Edit" : "Setup") { editingProvider = p }
                .controlSize(.small)
            Button(role: .destructive) {
                providerRegistry.remove(providerID: p.id)
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    private func enabledBinding(_ p: ConfiguredProvider) -> Binding<Bool> {
        Binding(
            get: { p.enabled },
            set: { newValue in
                var cp = p
                cp.enabled = newValue
                providerRegistry.upsert(cp)
            }
        )
    }

    private func newProviderID(for kind: ProviderKind) -> String {
        let base = kind.rawValue
        let existing = providerRegistry.config.providers.map { $0.id }
        if !existing.contains(base) { return base }
        var i = 2
        while existing.contains("\(base)\(i)") { i += 1 }
        return "\(base)\(i)"
    }
}

// MARK: - Provider editor sheet

struct ProviderEditorResult {
    var config: ConfiguredProvider?
    var apiKey: String?
}

struct ProviderEditor: View {
    @State var provider: ConfiguredProvider
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var testResult: String? = nil
    @State private var testing = false
    @State private var initialKey: String? = nil
    @State private var initialProvider: ConfiguredProvider? = nil
    let onClose: (ProviderEditorResult) -> Void

    /// True if auth-relevant fields differ from initial state — save must re-test.
    private var authDirty: Bool {
        guard let initial = initialProvider else { return true }
        if apiKey != (initialKey ?? "") { return true }
        if provider.model != initial.model { return true }
        if provider.baseURL != initial.baseURL { return true }
        if provider.kind != initial.kind { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(provider.kind.displayName).font(.headline)

            HStack {
                Text("Display name:").frame(width: 110, alignment: .trailing)
                TextField("", text: $provider.displayName)
            }

            if provider.kind.requiresBaseURL || provider.kind == .custom {
                HStack {
                    Text("Base URL:").frame(width: 110, alignment: .trailing)
                    TextField(provider.kind.defaultBaseURL ?? "https://example.com/v1",
                              text: Binding(get: { provider.baseURL ?? "" },
                                            set: { provider.baseURL = $0.isEmpty ? nil : $0 }))
                }
            }

            if provider.kind.requiresAPIKey || provider.kind == .custom {
                HStack {
                    Text("API Key:").frame(width: 110, alignment: .trailing)
                    if showKey {
                        TextField("sk-...", text: $apiKey)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                if APIKeyStorage.load(for: provider.id) != nil && apiKey.isEmpty {
                    Text("A key is already saved in Keychain. Leave blank to keep it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Model:").frame(width: 110, alignment: .trailing)
                TextField(provider.kind.defaultModel, text: $provider.model)
            }
            if !provider.kind.suggestedModels.isEmpty {
                HStack {
                    Spacer().frame(width: 110)
                    HStack(spacing: 4) {
                        ForEach(provider.kind.suggestedModels, id: \.self) { m in
                            Button(m) { provider.model = m }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                    Spacer()
                }
            }

            HStack {
                Button("Test connection") { runTest() }
                    .disabled(testing)
                if testing { ProgressView().controlSize(.small) }
                if let r = testResult {
                    Text(r)
                        .font(.caption)
                        .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel") { onClose(ProviderEditorResult(config: nil, apiKey: nil)) }
                Button(testing ? "Testing…" : "Save") {
                    saveWithTest()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(testing)
            }
            Text("Save runs the connection test first. Save only succeeds if the test passes.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            initialKey = APIKeyStorage.load(for: provider.id)
            initialProvider = provider
        }
    }

    /// #5: Save now runs test connection first. Editor stays open if test fails.
    private func saveWithTest() {
        // If auth-relevant fields didn't change AND existing key works — skip test, commit immediately.
        if !authDirty && testResult?.hasPrefix("✓") == true {
            commit()
            return
        }
        testing = true; testResult = nil
        let providerCopy = provider
        let keyForTest = apiKey.isEmpty ? (initialKey ?? "") : apiKey
        Task { @MainActor in
            if !keyForTest.isEmpty {
                APIKeyStorage.save(keyForTest, for: providerCopy.id)
            }
            AIProviderRegistry.shared.upsert(providerCopy)
            let result = await AIProviderRegistry.shared.testConnection(providerID: providerCopy.id)
            testing = false
            switch result {
            case .success(let msg):
                testResult = "✓ \(msg)"
                commit()
            case .failure(let e):
                testResult = "✗ \(errorMessage(e))"
                // Editor remains open — user can adjust and retry.
            }
        }
    }

    private func commit() {
        onClose(ProviderEditorResult(config: provider,
                                     apiKey: apiKey.isEmpty ? nil : apiKey))
    }

    private func errorMessage(_ e: AIProviderError) -> String {
        switch e {
        case .missingAPIKey: return "API key required"
        case .missingBaseURL: return "Base URL required"
        case .http(let status, _): return "HTTP \(status)"
        case .networkUnreachable: return "Network unreachable"
        case .decode(let s): return s
        }
    }

    /// Manual standalone test (без save) — keeps editor open regardless of result.
    private func runTest() {
        testing = true; testResult = nil
        let temp = provider
        let keyToSave = apiKey
        Task { @MainActor in
            if !keyToSave.isEmpty {
                APIKeyStorage.save(keyToSave, for: temp.id)
            }
            AIProviderRegistry.shared.upsert(temp)
            let result = await AIProviderRegistry.shared.testConnection(providerID: temp.id)
            testing = false
            switch result {
            case .success(let msg): testResult = "✓ \(msg)"
            case .failure(let e): testResult = "✗ \(errorMessage(e))"
            }
        }
    }
}

// MARK: - Provider add sheet

struct ProviderAddSheet: View {
    let onClose: (ProviderKind?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add provider").font(.headline)

            ScrollView {
                VStack(spacing: 4) {
                    sectionHeader("Cloud")
                    ForEach([ProviderKind.anthropic, .openai, .gemini, .grok, .mistral, .deepseek], id: \.self) {
                        kindRow($0)
                    }
                    sectionHeader("Local")
                    ForEach([ProviderKind.ollama, .lmstudio, .llamaCpp], id: \.self) {
                        kindRow($0)
                    }
                    sectionHeader("Other")
                    kindRow(.custom)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onClose(nil) }
            }
        }
        .padding(20)
        .frame(width: 420, height: 460)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func kindRow(_ kind: ProviderKind) -> some View {
        Button { onClose(kind) } label: {
            HStack {
                Image(systemName: kind.isLocal ? "desktopcomputer" : "cloud")
                    .foregroundStyle(.secondary)
                Text(kind.displayName)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content type tab (playground)

struct ContentTypeTab: View {
    let kind: SemanticKind
    @ObservedObject var registry: ActionRegistry
    let store: ClipboardStore

    @State private var sampleText: String = ""
    @State private var result: ApplyOutcome? = nil
    @State private var runningID: String? = nil
    @State private var editorContext: ActionEditorContext? = nil
    @State private var showingPalette: Bool = false

    var body: some View {
        // 2-колоночная вёрстка (Правка #5):
        // left = Sample input сверху + Result снизу
        // right = scrollable Actions list
        HStack(alignment: .top, spacing: 16) {
            leftColumn
                .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity)
            Divider()
            rightColumn
                .frame(minWidth: 340, idealWidth: 400, maxWidth: .infinity)
        }
        .padding()
        .onAppear { sampleText = SettingsSamples.sample(for: kind).previewText ?? "" }
        .sheet(item: Binding<EditorPresentation?>(
            get: { editorContext.map { EditorPresentation(context: $0) } },
            set: { editorContext = $0?.context }
        )) { presentation in
            ActionEditor(context: presentation.context, registry: registry) {
                editorContext = nil
            }
        }
    }

    private struct EditorPresentation: Identifiable {
        let context: ActionEditorContext
        var id: String {
            switch context {
            case .createNew: return "createNew"
            case .editBuiltin(let id, _, _): return "builtin:\(id)"
            case .editTransformation(let d): return "transform:\(d.id)"
            case .editAI(let d): return "ai:\(d.id)"
            }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sample input").font(.headline)
                Spacer()
                Button("Reset") { resetSample() }
                    .controlSize(.small)
            }
            TextEditor(text: $sampleText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            Text("Result").font(.headline).padding(.top, 6)
            ResultPane(outcome: result, kind: kind)
                .frame(maxHeight: .infinity)
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Actions").font(.headline)
                Spacer()
                Text("\(orderedActions.count + customAIDescriptors.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Button { editorContext = .createNew } label: {
                    Label("New", systemImage: "plus.circle")
                }
                .controlSize(.small)
                Button { showingPalette = true } label: {
                    Label("Browse", systemImage: "list.bullet.rectangle")
                }
                .controlSize(.small)
            }
            // Drag-to-reorder через SwiftUI List (правка #5).
            // Paste as is (identity) всегда первый и не двигается.
            List {
                ForEach(orderedActions, id: \.id) { action in
                    actionRow(action)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: moveActions)

                if !customTransformationDescriptors.isEmpty {
                    Section("Custom transformations") {
                        ForEach(customTransformationDescriptors) { desc in
                            customTransformationRow(desc)
                                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                if !customAIDescriptors.isEmpty {
                    Section("Custom AI actions") {
                        ForEach(customAIDescriptors) { desc in
                            customAIRow(desc)
                                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $showingPalette) {
            ActionPaletteSheet(kind: kind, registry: registry) { showingPalette = false }
        }
    }

    @ViewBuilder
    private func customTransformationRow(_ desc: CustomTransformationDescriptor) -> some View {
        let hotkey = registry.hotkey(for: desc.id)
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Toggle("", isOn: Binding(
                get: { desc.enabled },
                set: { newValue in
                    var copy = desc
                    copy.enabled = newValue
                    registry.upsertCustomTransformation(copy)
                }
            ))
            .labelsHidden()
            if let engine = desc.engine {
                Image(systemName: engine.iconName).foregroundStyle(.secondary).frame(width: 16)
            }
            Text(desc.title).lineLimit(1)
            Spacer()
            if let hk = hotkey {
                Text(hk.displayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Button("Edit") { editorContext = .editTransformation(desc) }
                .controlSize(.small)
            Button("Run") { runTransformation(desc) }
                .controlSize(.small)
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
    }

    private func runTransformation(_ desc: CustomTransformationDescriptor) {
        let kinds = Set(desc.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
        let action = CustomTransformationAction(
            id: desc.id,
            title: desc.title,
            descriptor: desc,
            applicableSet: kinds.isEmpty ? [.text] : kinds
        )
        run(action)
    }

    private func moveActions(from source: IndexSet, to destination: Int) {
        var ids = orderedActions.map { $0.id }
        // Запретить перемещать identity и помещать что-либо в позицию 0
        if source.contains(0) { return }
        let safeDest = max(1, destination)
        ids.move(fromOffsets: source, toOffset: safeDest)
        registry.setActionOrder(ids, for: kind)
    }

    /// Actions в порядке текущего config (или default) + identity первая.
    private var orderedActions: [ClipboardAction] {
        let item = makeSampleItem()
        let ctx = ContextDetector.detect(item)
        let applicable = registry.actions.filter {
            $0.isApplicable(item: item, context: ctx) && !$0.id.hasPrefix("user.")
        }
        return registry.reorder(applicable, forContentType: kind)
    }

    private var applicableActions: [ClipboardAction] {
        let item = makeSampleItem()
        let ctx = ContextDetector.detect(item)
        return registry.actions.filter { $0.isApplicable(item: item, context: ctx) && !$0.id.hasPrefix("user.") }
    }

    private var customAIDescriptors: [CustomAIDescriptor] {
        registry.config.customAI.filter { $0.applicableTypes.contains(kind.rawValue) }
    }

    private var customTransformationDescriptors: [CustomTransformationDescriptor] {
        registry.config.customTransformations.filter { $0.applicableTypes.contains(kind.rawValue) }
    }

    private func actionRow(_ action: ClipboardAction) -> some View {
        let displayTitle = registry.displayTitle(forActionID: action.id,
                                                  defaultTitle: action.title)
        let isCustomized = displayTitle != action.title
        let hotkey = registry.hotkey(for: action.id)
        let isLocked = action.id == "builtin.identity"
        let rowBg: Color = Color.primary.opacity(0.03)
        return HStack(spacing: 8) {
            // #2 Drag handle affordance — visual grip
            // Identity (Paste as is) shown as locked (cannot be moved).
            Image(systemName: isLocked ? "lock.fill" : "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Toggle("", isOn: enabledBinding(action.id))
                .labelsHidden()
            // #11 Type icon — visual consistency across all action rows.
            Image(systemName: BuiltinActionIcons.iconName(for: action.id))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle)
                    .lineLimit(1)
                if isCustomized {
                    Text("default: \(action.title)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let hk = hotkey {
                Text(hk.displayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            // Identity (Paste as is) поддерживает rename (#3), но не drag/delete.
            Button {
                editorContext = .editBuiltin(
                    actionID: action.id,
                    defaultTitle: action.title,
                    description: BuiltinActionMetadata.descriptions[action.id] ?? ""
                )
            } label: {
                Image(systemName: "pencil")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            if runningID == action.id {
                ProgressView().controlSize(.small)
            } else {
                Button("Run") { run(action) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(rowBg))
    }

    private func customAIRow(_ desc: CustomAIDescriptor) -> some View {
        let badge = providerBadge(for: desc.providerID)
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Toggle("", isOn: customEnabledBinding(desc.id))
                .labelsHidden()
            ProviderBadgeView(text: badge.label, color: badge.color,
                              fontSize: 11, iconName: badge.icon)
            Text(desc.title)
                .lineLimit(1)
            Spacer()
            Button("Edit") { editorContext = .editAI(desc) }
                .controlSize(.small)
            Button("Run") { runCustomAI(desc) }
                .controlSize(.small)
            Button { registry.removeCustomAI(id: desc.id) } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.06)))
    }

    /// Provider badge для AI action в Settings list (симметрия с HUD).
    private func providerBadge(for providerID: String)
        -> (label: String, color: Color, icon: String)
    {
        guard let cp = AIProviderRegistry.shared.config.providers.first(where: { $0.id == providerID })
        else {
            return ("AI", .gray, "sparkle")
        }
        let kind = cp.kind
        let color: Color
        switch kind {
        case .anthropic: color = .orange
        case .openai:    color = .green
        case .gemini:    color = .blue
        case .grok:      color = .primary
        case .mistral:   color = .purple
        case .deepseek:  color = .indigo
        case .ollama, .lmstudio, .llamaCpp, .custom: color = .gray
        }
        return (kind.badgeLabel, color, kind.iconName)
    }

    private func enabledBinding(_ actionID: String) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled(actionID) },
            set: { registry.setEnabled($0, for: actionID) }
        )
    }

    private func customEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { registry.config.customAI.first(where: { $0.id == id })?.enabled ?? true },
            set: { newValue in
                if var desc = registry.config.customAI.first(where: { $0.id == id }) {
                    desc.enabled = newValue
                    registry.upsertCustomAI(desc)
                }
            }
        )
    }

    private func makeSampleItem() -> ClipboardItem {
        var item = SettingsSamples.sample(for: kind)
        item.previewText = sampleText
        return item
    }

    private func resetSample() {
        sampleText = SettingsSamples.sample(for: kind).previewText ?? ""
    }

    private func run(_ action: ClipboardAction) {
        let item = makeSampleItem()
        let ctx = ContextDetector.detect(item)
        runningID = action.id
        Task {
            let outcome = await action.apply(item: item, context: ctx)
            await MainActor.run {
                self.result = outcome
                self.runningID = nil
            }
        }
    }

    private func runCustomAI(_ desc: CustomAIDescriptor) {
        let kinds = Set(desc.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
        let action = AIAction(
            id: desc.id,
            title: desc.title,
            promptTemplate: desc.promptTemplate,
            providerID: desc.providerID,
            applicableTypes: kinds.isEmpty ? [.text, .richText, .markdown] : kinds
        )
        run(action)
    }

}

// MARK: - Result pane

struct ResultPane: View {
    let outcome: ApplyOutcome?
    let kind: SemanticKind

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    private var content: some View {
        switch outcome {
        case .none:
            Text("(click Run to see result)").foregroundStyle(.secondary)
        case .preview(let item):
            preview(item)
        case .failed(_, let reason, _):
            HStack {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(reason)
            }
        case .sideEffect(let desc, _):
            HStack {
                Image(systemName: "bolt").foregroundStyle(Color.accentColor)
                Text(desc)
            }
        case .alternativeCommit(let item, let style):
            VStack(alignment: .leading) {
                Text("Will commit as \(styleLabel(style))")
                    .font(.caption).foregroundStyle(Color.accentColor)
                preview(item)
            }
        }
    }

    @ViewBuilder
    private func preview(_ item: ClipboardItem) -> some View {
        if item.semantic == .image, let rel = item.previewImageRel,
           let img = NSImage(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel)) {
            Image(nsImage: img)
                .resizable().aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
        } else if item.semantic == .richText,
                  let attr = RichTextLoader.attributedString(from: item) {
            // #7: native NSTextView rendering preserves bold/italic/links/colors.
            RichTextPreviewView(attributedString: attr)
        } else {
            ScrollView {
                Text(item.previewText ?? "")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func styleLabel(_ style: CommitStyle) -> String {
        switch style {
        case .standardPaste: return "standard paste"
        case .typeSlowly(let d, _): return "Type Slowly (\(Int(d * 1000)) ms/char)"
        case .typeFast: return "Type Fast"
        }
    }

}

// MARK: - Import/Export tab

struct ImportExportTab: View {
    @ObservedObject var registry: ActionRegistry
    @State private var status: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Export your DrPaste configuration to a JSON file you can back up or share.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Button("Export…") { exportConfig() }
                Button("Import…") { importConfig(strategy: .merge) }
                Button("Replace all from file…") { importConfig(strategy: .replace) }
                    .foregroundStyle(.red)
            }

            Text("API keys are not included in export for security reasons.")
                .font(.caption).foregroundStyle(.secondary)

            if let status = status {
                Text(status).font(.caption).foregroundStyle(.green)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exportConfig() {
        guard let data = registry.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "drpaste-config-\(dateStamp()).json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
            status = "Exported to \(url.lastPathComponent)"
        }
    }

    private func importConfig(strategy: ActionRegistry.ImportStrategy) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            if registry.importJSON(data, strategy: strategy) {
                status = strategy == .replace ? "Replaced" : "Merged"
            } else {
                status = "Import failed — invalid JSON"
            }
        }
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
