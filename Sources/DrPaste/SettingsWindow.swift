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
            }

            Section("Sound feedback") {
                HStack {
                    Text("Volume:")
                    Slider(value: $soundVolume, in: 0...1)
                    Text(String(format: "%.0f%%", soundVolume * 100))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                }
                ForEach([SoundCue.copySuccess, .copyFailure, .pasteSuccess, .pasteFailure, .typeTick], id: \.rawValue) { cue in
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
        }
    }

    private func reload() {
        let v = UserDefaults.standard.double(forKey: "drpaste.hud.fontScale")
        fontScale = v == 0 ? 1.0 : v
        soundVolume = Double(SoundFeedback.currentVolume())
    }

    private func cueLabel(_ cue: SoundCue) -> String {
        switch cue {
        case .copySuccess: return "Play sound on copy success"
        case .copyFailure: return "Play sound on copy failure"
        case .pasteSuccess: return "Play sound on paste"
        case .pasteFailure: return "Play sound on action failure"
        case .typeTick: return "Play tick on Type Slowly characters"
        }
    }

    private func cueBinding(_ cue: SoundCue) -> Binding<Bool> {
        Binding(
            get: { SoundFeedback.isEnabled(cue) },
            set: { SoundFeedback.setEnabled($0, for: cue) }
        )
    }
}

// MARK: - AI Providers tab

struct AIProvidersTab: View {
    @ObservedObject var registry: ActionRegistry
    @State private var anthropicKey: String = ""
    @State private var anthropicModel: String = "claude-sonnet-4-6"
    @State private var saved = false

    var body: some View {
        Form {
            Section("Anthropic (Claude)") {
                SecureField("API Key", text: $anthropicKey)
                TextField("Model", text: $anthropicModel)
                Button("Save") {
                    var cfg = AIProviderConfig.load()
                    cfg.anthropicAPIKey = anthropicKey.isEmpty ? nil : anthropicKey
                    cfg.anthropicModel = anthropicModel
                    if let data = try? JSONEncoder().encode(cfg) {
                        try? data.write(to: AIProviderConfig.configURL())
                    }
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                }
                if saved {
                    Text("Saved. Restart DrPaste to apply.")
                        .font(.caption).foregroundStyle(.green)
                }
                Text("Or set ANTHROPIC_API_KEY environment variable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let cfg = AIProviderConfig.load()
            anthropicKey = cfg.anthropicAPIKey ?? ""
            anthropicModel = cfg.anthropicModel ?? "claude-sonnet-4-6"
        }
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
    @State private var editingAI: CustomAIDescriptor? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sample input")
                .font(.headline)
            TextEditor(text: $sampleText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button("Reset to default") { resetSample() }
                    .controlSize(.small)
                Spacer()
            }

            Text("Result")
                .font(.headline)
            ResultPane(outcome: result, kind: kind)

            Divider()

            Text("Actions")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(applicableActions, id: \.id) { action in
                        actionRow(action)
                    }

                    if !customAIDescriptors.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("Custom AI actions").font(.caption).foregroundStyle(.secondary)
                        ForEach(customAIDescriptors) { desc in
                            customAIRow(desc)
                        }
                    }

                    Button { editingAI = newCustomAITemplate() } label: {
                        Label("Add custom AI action…", systemImage: "plus.circle")
                    }
                    .controlSize(.small)
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .onAppear { sampleText = SettingsSamples.sample(for: kind).previewText ?? "" }
        .sheet(item: $editingAI) { desc in
            AIActionEditor(descriptor: desc, registry: registry) { saved in
                if let saved = saved { registry.upsertCustomAI(saved) }
                editingAI = nil
            }
        }
    }

    private var applicableActions: [ClipboardAction] {
        let item = makeSampleItem()
        let ctx = ContextDetector.detect(item)
        return registry.actions.filter { $0.isApplicable(item: item, context: ctx) && !$0.id.hasPrefix("user.") }
    }

    private var customAIDescriptors: [CustomAIDescriptor] {
        registry.config.customAI.filter { $0.applicableTypes.contains(kind.rawValue) }
    }

    private func actionRow(_ action: ClipboardAction) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabledBinding(action.id))
                .labelsHidden()
            Text(action.title)
                .lineLimit(1)
            Spacer()
            if runningID == action.id {
                ProgressView().controlSize(.small)
            } else {
                Button("Run") { run(action) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.03)))
    }

    private func customAIRow(_ desc: CustomAIDescriptor) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: customEnabledBinding(desc.id))
                .labelsHidden()
            Text(desc.title)
                .lineLimit(1)
            Text("[custom]").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Edit") { editingAI = desc }
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
        guard let provider = registry.aiProvider else { return }
        let action = AIAction(id: desc.id, title: desc.title,
                              promptTemplate: desc.promptTemplate, provider: provider)
        run(action)
    }

    private func newCustomAITemplate() -> CustomAIDescriptor {
        CustomAIDescriptor(
            id: "user.\(UUID().uuidString.prefix(8))",
            title: "AI: my action",
            promptTemplate: "Rewrite the user's input. Reply with the result only, no preamble.",
            providerID: "anthropic",
            applicableTypes: [kind.rawValue],
            enabled: true
        )
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

// MARK: - AI editor

struct AIActionEditor: View {
    @State var descriptor: CustomAIDescriptor
    @ObservedObject var registry: ActionRegistry
    let onClose: (CustomAIDescriptor?) -> Void

    private let allTypes: [SemanticKind] = [.text, .richText, .url, .json, .table, .markdown, .code]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom AI action").font(.headline)

            HStack {
                Text("Title:").frame(width: 90, alignment: .trailing)
                TextField("AI: …", text: $descriptor.title)
            }

            HStack(alignment: .top) {
                Text("Prompt:").frame(width: 90, alignment: .trailing)
                TextEditor(text: $descriptor.promptTemplate)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }

            HStack {
                Text("Provider:").frame(width: 90, alignment: .trailing)
                Picker("", selection: $descriptor.providerID) {
                    Text("Anthropic (Claude)").tag("anthropic")
                }
                .pickerStyle(.menu)
            }

            HStack(alignment: .top) {
                Text("Applies to:").frame(width: 90, alignment: .trailing)
                VStack(alignment: .leading) {
                    ForEach(allTypes, id: \.self) { type in
                        Toggle(type.displayName, isOn: typeBinding(type.rawValue))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onClose(nil) }
                Button("Save") { onClose(descriptor) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func typeBinding(_ raw: String) -> Binding<Bool> {
        Binding(
            get: { descriptor.applicableTypes.contains(raw) },
            set: { isOn in
                if isOn {
                    if !descriptor.applicableTypes.contains(raw) { descriptor.applicableTypes.append(raw) }
                } else {
                    descriptor.applicableTypes.removeAll { $0 == raw }
                }
            }
        )
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
