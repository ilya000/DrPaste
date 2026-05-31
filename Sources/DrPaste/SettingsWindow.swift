//
//  SettingsWindow.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Settings UI: SwiftUI TabView with General, AI Providers, and per-content-type
//  tabs. Each content tab is a playground with sample input, a Result pane, and
//  an action list with Run buttons.
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
    @State private var configStatus: String? = nil
    @State private var confirmReplace = false
    @State private var confirmFactoryReset = false

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

            Section("Appearance") {
                AppearancePicker()
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
                ForEach([SoundCue.copySuccess, .copyFailure, .pasteSuccess, .pasteFailure, .appendCopy, .typeTick, .delete], id: \.rawValue) { cue in
                    Toggle(cueLabel(cue), isOn: cueBinding(cue))
                }
            }

            Section("Configuration") {
                HStack(spacing: 10) {
                    Button("Export…") { exportConfig() }
                    Button("Import…") { importConfig(strategy: .merge) }
                    Button("Replace from file…") { confirmReplace = true }
                    Spacer()
                }
                Text("Export saves your actions, hotkeys, and preferences to a JSON file. API keys are kept separately and never written to the export.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        confirmFactoryReset = true
                    } label: {
                        Label("Factory Reset", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
                Text("Factory Reset wipes all action customizations, custom AI prompts and transformations, per-action hotkeys, configured AI providers, and saved API keys, then reseeds the bundled defaults. This cannot be undone.")
                    .font(.caption).foregroundStyle(.secondary)

                if let status = configStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.hasPrefix("Failed") ? .red : .green)
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
            // Sound preview while the volume slider moves.
            SoundFeedback.playPreview(.copySuccess)
        }
        .confirmationDialog(
            "Replace configuration from file?",
            isPresented: $confirmReplace,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) { importConfig(strategy: .replace) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current actions, hotkeys, and preferences will be replaced with the contents of the selected file. Your stored API keys are not touched.")
        }
        .confirmationDialog(
            "Reset DrPaste to factory defaults?",
            isPresented: $confirmFactoryReset,
            titleVisibility: .visible
        ) {
            Button("Reset everything", role: .destructive) { factoryReset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All custom actions, hotkeys, AI provider configs, API keys, and preferences will be erased. This cannot be undone.")
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
        case .appendCopy: return "Play sound on ⌥⌘S append copy"
        case .typeTick: return "Play tick on Type Slowly characters"
        case .delete: return "Play sound on delete from history"
        }
    }

    private func cueBinding(_ cue: SoundCue) -> Binding<Bool> {
        Binding(
            get: { SoundFeedback.isEnabled(cue) },
            set: { newValue in
                SoundFeedback.setEnabled(newValue, for: cue)
                // Sound preview on every toggle so the user always hears the
                // sample — even when disabling (gives them a final preview).
                SoundFeedback.playPreview(cue)
            }
        )
    }

    // MARK: - Configuration (Export / Import / Factory Reset)

    private func exportConfig() {
        guard let data = registry.exportJSON() else {
            configStatus = "Failed to encode configuration"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "drpaste-config-\(Self.dateStamp()).json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                configStatus = "Exported to \(url.lastPathComponent)"
            } catch {
                configStatus = "Failed to write file: \(error.localizedDescription)"
            }
        }
    }

    private func importConfig(strategy: ActionRegistry.ImportStrategy) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        if registry.importJSON(data, strategy: strategy) {
            configStatus = strategy == .replace ? "Replaced from \(url.lastPathComponent)"
                                                : "Merged from \(url.lastPathComponent)"
        } else {
            configStatus = "Failed: file is not a valid DrPaste configuration"
        }
    }

    private func factoryReset() {
        registry.factoryReset()
        // Pull UserDefaults-backed local state back to defaults so the inputs
        // displayed in this same view reflect the reset immediately.
        fontScale = 1.0
        soundVolume = Double(SoundFeedback.currentVolume())
        configStatus = "Factory reset complete"
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Appearance picker (Fantastical-style theme thumbnails)

/// Five-up row of theme preview thumbnails with selection state and a
/// caption explaining the active theme. Wired to `ThemeManager.shared`
/// so picking a thumbnail immediately re-skins every open panel.
struct AppearancePicker: View {
    @ObservedObject private var manager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Horizontal scroll lets the picker survive future
            // additions without re-fighting layout. At current 78 pt
            // thumbnail + 8 pt spacing, 6 themes (Auto / Light /
            // Dark / Vivid / Soft / Ocean) fit cleanly in a typical
            // Settings tab width; the scroll only engages if the
            // window is narrowed or more themes get added later.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            manager.setTheme(theme)
                        } label: {
                            ThemeThumbnail(theme: theme,
                                           selected: theme == manager.current)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 1)
            }
            Text(manager.current.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - AI Providers tab (multi-provider)

struct AIProvidersTab: View {
    @ObservedObject var registry: ActionRegistry
    @ObservedObject private var providerRegistry = AIProviderRegistry.shared
    @State private var editingProvider: ConfiguredProvider? = nil
    @State private var showingAddSheet = false
    /// Mirror of `APIKeyStorage.fallbackOnly`. Toggled by the user via the
    /// "Skip macOS Keychain" switch at the bottom of this tab; persisted via
    /// the static setter on `APIKeyStorage` (UserDefaults-backed).
    @State private var fallbackOnly: Bool = APIKeyStorage.fallbackOnly
    /// Per-provider live connection status. Refreshed on tab appearance and
    /// after each successful Save (Edit dialog). The coloured dot to the
    /// left of each row reflects whatever's here: gray when never tested,
    /// yellow while a probe is in flight, green for a passing test, red
    /// when the last test failed (with the reason in the tooltip).
    @State private var statusByProvider: [String: ConnectionStatus] = [:]

    enum ConnectionStatus: Equatable {
        case unknown
        case checking
        case ok
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text("Select a default provider with the radio button on the left. AI actions use the default unless overridden per-action. The default is set automatically after the first successful connection test.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            Divider()

            // TEMPORARY (#A1): Keychain is fully disabled in 0.14.0, so the
            // user-controllable "Skip macOS Keychain" toggle has no remaining
            // purpose — every key is in the JSON fallback file regardless.
            // The section returns when #A1 ships a signed `.app`; the
            // implementation below is preserved verbatim and ready to
            // re-enable by uncommenting this single line.
            //
            // keyStorageSection
            keyStorageDisabledNotice
        }
        .padding()
        .task { await refreshAllStatuses() }
        .sheet(item: $editingProvider) { p in
            ProviderEditor(provider: p) { result in
                if result.delete {
                    providerRegistry.remove(providerID: p.id)
                    statusByProvider.removeValue(forKey: p.id)
                } else if let cp = result.config {
                    providerRegistry.upsert(cp, apiKey: result.apiKey)
                    providerRegistry.invalidateCache()
                    // The editor only commits when its in-dialog test passed,
                    // so reflect that immediately in the row dot without
                    // running another full probe. The next .task refresh
                    // (next tab appearance) will reconfirm.
                    statusByProvider[cp.id] = .ok
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


    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    /// API-key storage policy section. Defaults to Keychain. The user can
    /// flip to a plain-JSON fallback file when Keychain triggers a login
    /// password prompt on every launch (typical for unsigned development
    /// builds — Keychain ACL is bound to the binary's code signature and
    /// every rebuild changes the hash).
    /// Replacement for `keyStorageSection` while Keychain is disabled
    /// (#A1). Tells the user where keys actually live in 0.14.0 so the
    /// absence of the toggle doesn't read as a bug, and pins the
    /// expectation that storage will move back into Keychain in a
    /// future release.
    @ViewBuilder
    private var keyStorageDisabledNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("API key storage")
                    .font(.subheadline)
                Spacer()
            }
            Text("Keys are stored in ~/Library/Application Support/DrPaste/provider-keys-fallback.json with user-only file permissions (0o600). macOS Keychain integration is temporarily disabled and returns in a future release alongside the signed `.app` distribution.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var keyStorageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("API key storage")
                    .font(.subheadline)
                Spacer()
            }
            Toggle("Skip macOS Keychain — store API keys in a local file",
                   isOn: $fallbackOnly)
                .onChange(of: fallbackOnly) { newValue in
                    APIKeyStorage.setFallbackOnly(newValue)
                    AIProviderRegistry.shared.invalidateCache()
                }
            Text("Useful for unsigned development builds. Keychain ties its ACL to the app's code signature; every rebuild changes the binary hash and triggers the login password prompt on next launch. With this enabled, keys are saved to ~/Library/Application Support/DrPaste/provider-keys-fallback.json with user-only file permissions (0o600).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if fallbackOnly {
                Text("File storage active. New API keys are written to the fallback file. Any existing Keychain entries are ignored — re-enter the key in the provider editor if a provider stops working.")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ p: ConfiguredProvider) -> some View {
        let hasKey = APIKeyStorage.load(for: p.id) != nil
        let isReady = p.kind.isLocal || hasKey
        let isDefault = providerRegistry.config.defaultProviderID == p.id
        let status = statusByProvider[p.id] ?? .unknown
        HStack(spacing: 10) {
            // Default radio — clickable if provider is ready.
            Button {
                if isReady {
                    providerRegistry.setDefault(providerID: p.id)
                }
            } label: {
                Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(radioColor(isDefault: isDefault, isReady: isReady))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(isReady ? "Set as default provider for AI actions" : "Configure the provider first")

            // Connection-health dot. Reflects the last `testConnection` result:
            // gray = never probed, yellow (pulse) = probe in flight, green = OK,
            // red = failed (hover for the reason). Probes fire on tab open and
            // after each successful Save.
            statusDot(for: status, isReady: isReady)
                .help(statusTooltip(for: status, isReady: isReady))

            // Provider brand icon — consistent across the HUD action list and
            // the Settings provider list so the user can spot which AI is which
            // at a glance without reading the name.
            Image(systemName: p.kind.iconName)
                .font(.system(size: 16))
                .foregroundStyle(p.kind.brandColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.displayName).font(.system(size: 13, weight: .medium))
                    if isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
                Text(p.kind.isLocal
                     ? "Local · \(p.baseURL ?? "no URL") · \(p.model)"
                     : "\(isReady ? "Configured" : "Not configured") · \(p.model)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Delete moved into the editor footer (matches the Action editor's
            // "destructive gravity inside the dialog" pattern from 0.12.0).
            // Edit (or Setup, when unconfigured) is now the only row-level
            // action besides the default radio.
            Button(isReady ? "Edit" : "Setup") { editingProvider = p }
                .controlSize(.small)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    private func statusDot(for status: ConnectionStatus, isReady: Bool) -> some View {
        switch status {
        case .unknown:
            Circle()
                .fill(isReady ? Color.gray.opacity(0.45) : Color.gray.opacity(0.25))
                .frame(width: 8, height: 8)
        case .checking:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
                .frame(width: 8, height: 8)
        case .ok:
            Circle().fill(Color.green).frame(width: 8, height: 8)
        case .failed:
            Circle().fill(Color.red).frame(width: 8, height: 8)
        }
    }

    private func statusTooltip(for status: ConnectionStatus, isReady: Bool) -> String {
        switch status {
        case .unknown:
            return isReady ? "Not tested yet — probe will run automatically." : "Provider not configured."
        case .checking: return "Testing connection…"
        case .ok: return "Last test passed."
        case .failed(let reason): return "Last test failed: \(reason)"
        }
    }

    /// Fires `testConnection` for every provider that's configured (has an API
    /// key for cloud providers, or a base URL for local). Skips providers
    /// that have nothing to test against to avoid a parade of red dots on
    /// fresh installs. Runs in parallel — each provider's check is
    /// independent so slow providers don't gate fast ones.
    private func refreshAllStatuses() async {
        let providers = providerRegistry.config.providers
        await withTaskGroup(of: Void.self) { group in
            for p in providers {
                let hasKey = APIKeyStorage.load(for: p.id) != nil
                let isReady = p.kind.isLocal || hasKey
                guard isReady else { continue }
                group.addTask { @MainActor in
                    statusByProvider[p.id] = .checking
                    let result = await AIProviderRegistry.shared.testConnection(providerID: p.id)
                    switch result {
                    case .success: statusByProvider[p.id] = .ok
                    case .failure(let e): statusByProvider[p.id] = .failed(errorMessage(e))
                    }
                }
            }
        }
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

    /// Returns explicit Color for the radio icon to avoid HierarchicalShapeStyle vs Color
    /// type inference issues in the ternary expression.
    private func radioColor(isDefault: Bool, isReady: Bool) -> Color {
        if isDefault { return .accentColor }
        if isReady { return Color.primary.opacity(0.55) }
        return Color.primary.opacity(0.25)
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
    /// True when the editor's footer Delete was confirmed. The sheet handler
    /// in `AIProvidersTab` routes through `providerRegistry.remove(...)` and
    /// ignores `config` / `apiKey`. Mutually exclusive with a Save result.
    var delete: Bool = false
}

struct ProviderEditor: View {
    @State var provider: ConfiguredProvider
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var testResult: String? = nil
    @State private var testing = false
    @State private var initialKey: String? = nil
    @State private var initialProvider: ConfiguredProvider? = nil
    @State private var confirmDelete = false
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
                // "Get an API key" deep-link to the provider's dashboard.
                // Saves the user a Google search every time they need a key
                // for a fresh provider — most providers bury this URL
                // several clicks deep under "Documentation" or "Developers".
                if let docsURL = provider.kind.apiKeyDocsURL {
                    HStack {
                        Spacer().frame(width: 110)
                        Link(destination: docsURL) {
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                    .font(.caption2)
                                Text("Get an API key from \(provider.kind.displayName) →")
                                    .font(.caption)
                            }
                        }
                        Spacer()
                    }
                }
                if APIKeyStorage.load(for: provider.id) != nil && apiKey.isEmpty {
                    Text("A key is already saved. Leave blank to keep it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Model:").frame(width: 110, alignment: .trailing)
                TextField(provider.kind.defaultModel, text: $provider.model)
            }
            if !provider.kind.suggestedModels.isEmpty {
                HStack(alignment: .top) {
                    Spacer().frame(width: 110)
                    // Long model slugs like `meta-llama/Llama-3.3-70B-...`
                    // wreck the previous fixed-grid layout — SwiftUI
                    // wrapped them mid-word into 6-character columns of
                    // ladder text. Switch to a horizontally-scrolling
                    // row of capsule chips: each chip stays on one line
                    // at its natural width (`.fixedSize`), the row
                    // scrolls right if the total exceeds the dialog
                    // width. User can read the full slug they're
                    // clicking and pick by skim, instead of decoding
                    // hieroglyphic word-wraps.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(provider.kind.suggestedModels, id: \.self) { m in
                                Button { provider.model = m } label: {
                                    Text(m)
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule().fill(Color.accentColor.opacity(0.10))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
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
                // Destructive action stays on the left, separated from the
                // non-destructive Cancel / Save cluster on the right.
                // Confirmation dialog protects against misclicks since
                // removal also deletes the saved API key.
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.regular)
                .disabled(testing)
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
        .confirmationDialog(
            "Delete \(provider.displayName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onClose(ProviderEditorResult(config: nil, apiKey: nil, delete: true))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the provider's configuration and its stored API key. Any AI actions that follow the default will fall back to the next configured provider. This cannot be undone.")
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
        // Same intent guard as runTest: Save implies the user wants this
        // provider live — force-enable in case the row toggle was flipped
        // off by accident.
        var providerCopy = provider
        providerCopy.enabled = true
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
                // Auto-promote to default if no default is set, default is empty,
                // or the current default is not ready (no key / no local URL).
                if Self.shouldAutoPromoteDefault() {
                    AIProviderRegistry.shared.setDefault(providerID: providerCopy.id)
                }
                commit()
            case .failure(let e):
                testResult = "✗ \(errorMessage(e))"
                // Editor remains open — user can adjust and retry.
            }
        }
    }

    /// Returns true if the just-passed provider should claim the default slot:
    /// either no default exists, or the current default has no key / is unconfigured.
    private static func shouldAutoPromoteDefault() -> Bool {
        let cfg = AIProviderRegistry.shared.config
        guard let currentID = cfg.defaultProviderID, !currentID.isEmpty,
              let currentDefault = cfg.providers.first(where: { $0.id == currentID })
        else { return true }
        let hasKey = APIKeyStorage.load(for: currentDefault.id) != nil
        let isReady = currentDefault.kind.isLocal || hasKey
        return !isReady
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

    /// Manual standalone test (no save) — keeps the editor open regardless of result.
    private func runTest() {
        testing = true; testResult = nil
        // If the user is testing a key, they obviously intend the provider
        // to be active. Force-enable to recover from accidental clicks on
        // the per-row enable Toggle (a tiny unlabeled control sandwiched
        // between Edit and Trash buttons — easy to flip by mistake).
        var temp = provider
        temp.enabled = true
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
                    // Gateways — one account, many models. OpenRouter
                    // and Together AI are aggregators; Cloudflare
                    // Workers AI is a cloud platform that exposes
                    // many models through one account. Same UX shape
                    // (one auth, many model slugs), so same section.
                    sectionHeader("Gateway")
                    ForEach([ProviderKind.openrouter, .together, .cloudflareWorkers], id: \.self) {
                        kindRow($0)
                    }
                    // Fast-inference platforms — specialised hardware
                    // (Groq's LPU, Cerebras's wafer-scale chip)
                    // optimised for ultra-fast token generation.
                    // Smaller model selection than gateways but much
                    // lower latency — well suited to quick paste-
                    // action flows where speed matters most.
                    sectionHeader("Fast inference")
                    ForEach([ProviderKind.groq, .cerebras], id: \.self) {
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
            HStack(spacing: 10) {
                // Each provider gets its own per-kind icon + brand
                // colour — same glyph the HUD action chips show — so
                // the picker reads as a row of distinct identities
                // instead of a column of identical clouds. Icon sits
                // inside a soft tinted circle so brand colours stay
                // legible against the row's neutral grey background.
                ZStack {
                    Circle()
                        .fill(kind.brandColor.opacity(0.16))
                        .frame(width: 26, height: 26)
                    Image(systemName: kind.iconName)
                        .foregroundStyle(kind.brandColor)
                        .font(.system(size: 13, weight: .medium))
                }
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
    /// Observed so AI action rows re-render when the default provider changes —
    /// default-bound rows show whichever provider's icon is currently default.
    @ObservedObject private var providerRegistry = AIProviderRegistry.shared
    let store: ClipboardStore

    @State private var sampleText: String = ""
    @State private var result: ApplyOutcome? = nil
    @State private var runningID: String? = nil
    @State private var editorContext: ActionEditorContext? = nil

    /// Standalone NSWindow that hosts ActionEditor. Replaces the previous
    /// `.sheet(item:)` modifier because sheets can't be dragged
    /// independently of their parent and don't clamp themselves against
    /// the Dock — the editor's footer with OK/Cancel was landing behind
    /// the Dock on small screens or when Settings was positioned near
    /// the top of the display. Standalone NSWindow is movable by its
    /// title bar and clamped to `visibleFrame`.
    @State private var editorWindow = ActionEditorWindowController()

    var body: some View {
        // Two-column layout:
        // left  = Sample input on top, Result below
        // right = scrollable Actions list.
        HStack(alignment: .top, spacing: 16) {
            leftColumn
                .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity)
            Divider()
            rightColumn
                .frame(minWidth: 340, idealWidth: 400, maxWidth: .infinity)
        }
        .padding()
        .onAppear { sampleText = SettingsSamples.sample(for: kind).previewText ?? "" }
        .onChange(of: editorContextKey) { _ in
            // Whenever editorContext flips from nil → non-nil, open a
            // window for the new context. Going non-nil → nil closes it
            // (handles cases where the user clicks Save/Cancel inside
            // the editor, which sets editorContext = nil).
            if let context = editorContext {
                editorWindow.show(context: context, registry: registry) {
                    // onClose may fire from the editor (Save / Cancel
                    // button) or from the window's red traffic-light.
                    // Either way, reset state so the next click on
                    // Add / Edit reopens cleanly.
                    if editorContext != nil { editorContext = nil }
                }
            } else {
                editorWindow.close()
            }
        }
    }

    /// String-id derived from editorContext for SwiftUI's `onChange`
    /// (ActionEditorContext has associated values so it isn't Equatable
    /// without an explicit conformance). Different keys ↔ different
    /// dialogs; same key ↔ no-op.
    private var editorContextKey: String {
        guard let ctx = editorContext else { return "" }
        switch ctx {
        case .createNew: return "createNew"
        case .editBuiltin(let id, _, _): return "builtin:\(id)"
        case .editTransformation(let d): return "transform:\(d.id)"
        case .editAI(let d): return "ai:\(d.id)"
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
                Text("\(orderedActions.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Button { editorContext = .createNew } label: {
                    Label("New", systemImage: "plus.circle")
                }
                .controlSize(.small)
            }
            // Single drag-to-reorder list. Identity is always first.
            // Built-in, custom AI, and custom transformations all live here together —
            // user can intermix and reorder freely.
            List {
                ForEach(orderedActions, id: \.id) { action in
                    actionRow(action)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: moveActions)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func moveActions(from source: IndexSet, to destination: Int) {
        var ids = orderedActions.map { $0.id }
        // Identity must stay at position 0 and cannot be moved.
        if source.contains(0) { return }
        let safeDest = max(1, destination)
        ids.move(fromOffsets: source, toOffset: safeDest)
        registry.setActionOrder(ids, for: kind)
    }

    /// All applicable actions in saved order (or default). Identity stays first.
    /// Includes built-ins, custom AI actions, and custom transformations in a single list —
    /// user can reorder freely.
    private var orderedActions: [ClipboardAction] {
        let item = makeSampleItem()
        let ctx = ContextDetector.detect(item)
        let applicable = registry.actions.filter { $0.isApplicable(item: item, context: ctx) }
        return registry.reorder(applicable, forContentType: kind)
    }

    /// Polymorphic row renderer — branches on action type so built-in, custom AI,
    /// and custom transformation rows live together in a single reorderable list.
    /// - Built-in: BuiltinActionIcons type icon; pencil → editBuiltin; no delete.
    /// - Custom AI: provider badge that resolves the current default dynamically when
    ///   the action follows the default; pencil → editAI; delete removes the AI descriptor.
    /// - Custom transformation: engine SF Symbol; pencil → editTransformation; delete
    ///   removes the transformation descriptor.
    @ViewBuilder
    private func actionRow(_ action: ClipboardAction) -> some View {
        let displayTitle = registry.displayTitle(forActionID: action.id,
                                                  defaultTitle: action.title)
        let isCustomized = displayTitle != action.title
        let isLocked = action.id == "builtin.identity"
        let isEnabled = registry.isEnabled(action.id)
        let rowBg = rowBackground(for: action)
        HStack(spacing: 8) {
            // Drag handle. Identity (Paste as is) shown as locked (cannot be moved).
            Image(systemName: isLocked ? "lock.fill" : "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Toggle("", isOn: enabledBinding(action.id))
                .labelsHidden()
            leadingIcon(for: action)
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
            // Compact read-only badge when a hotkey is assigned — keeps the
            // row legible. Inline recording was tried (and reverted) because a
            // 130pt "Click to record" field crushed long titles. Assigning /
            // changing hotkeys is done through the editor (pencil) for now.
            // A future iteration may bring this back as a popover-on-tap so
            // the row stays compact when nothing is bound.
            if let hk = registry.hotkey(for: action.id) {
                Text(hk.displayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Button { openEditor(for: action) } label: {
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
            // Delete intentionally lives only inside the editor (pencil →
            // Delete in the editor footer). The row's checkbox is a reversible
            // visibility toggle; full deletion is a destructive permanent
            // operation and should require the heavier interaction of opening
            // the editor and reading the action before clicking the
            // destructive button.
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(rowBg))
        .opacity(isEnabled ? 1.0 : 0.45)
    }

    /// Background tint distinguishes user-defined actions (subtle accent) from
    /// built-ins (neutral) without breaking the unified list visual rhythm.
    private func rowBackground(for action: ClipboardAction) -> Color {
        if action is AIAction || action is CustomTransformationAction {
            return Color.accentColor.opacity(0.06)
        }
        return Color.primary.opacity(0.03)
    }

    /// Leading type icon — provider badge for AI, engine glyph for transformations,
    /// built-in SF Symbol otherwise. Provider badge resolves the default dynamically,
    /// so seeded actions follow whichever provider is currently default.
    @ViewBuilder
    private func leadingIcon(for action: ClipboardAction) -> some View {
        if let aiAction = action as? AIAction {
            let badge = providerBadge(for: aiAction)
            ProviderBadgeView(text: badge.label, color: badge.color,
                              fontSize: 11, iconName: badge.icon)
        } else if let tx = action as? CustomTransformationAction {
            Image(systemName: tx.descriptor.engine?.iconName ?? "function")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
        } else {
            Image(systemName: BuiltinActionIcons.iconName(for: action.id))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
    }

    /// Routes the pencil button to the correct editor sheet for the action's type.
    private func openEditor(for action: ClipboardAction) {
        if action is AIAction,
           let desc = registry.config.customAI.first(where: { $0.id == action.id }) {
            editorContext = .editAI(desc)
            return
        }
        if let tx = action as? CustomTransformationAction {
            editorContext = .editTransformation(tx.descriptor)
            return
        }
        editorContext = .editBuiltin(
            actionID: action.id,
            defaultTitle: action.title,
            description: BuiltinActionMetadata.descriptions[action.id] ?? ""
        )
    }

    /// Provider badge for AI action in Settings list (mirrors HUD chip).
    /// Resolves dynamically: actions with nil or empty providerID follow the current
    /// default provider — when the user changes the default, every default-bound row
    /// updates because @ObservedObject on the provider registry republishes.
    private func providerBadge(for ai: AIAction)
        -> (label: String, color: Color, icon: String)
    {
        let resolvedKind: ProviderKind? = {
            if let id = ai.providerID, !id.isEmpty,
               let cp = AIProviderRegistry.shared.config.providers.first(where: { $0.id == id }) {
                return cp.kind
            }
            if let defaultID = AIProviderRegistry.shared.config.defaultProviderID,
               !defaultID.isEmpty,
               let cp = AIProviderRegistry.shared.config.providers.first(where: { $0.id == defaultID }) {
                return cp.kind
            }
            return nil
        }()
        guard let kind = resolvedKind else { return ("AI", .gray, "sparkle") }
        // Single source of truth for the brand palette — see
        // `ProviderKind.brandColor`. Used here in the Settings actions
        // list, in HUD chip badges, and in the Settings provider list,
        // so the same brand always paints the same hue.
        return (kind.badgeLabel, kind.brandColor, kind.iconName)
    }

    private func enabledBinding(_ actionID: String) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled(actionID) },
            set: { registry.setEnabled($0, for: actionID) }
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

// Import/Export controls live in GeneralTab → "Configuration" section.
