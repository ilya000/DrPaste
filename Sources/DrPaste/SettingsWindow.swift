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

// MARK: - Enabled checkbox style

/// Custom checkbox for the per-action "enabled" toggle. The native macOS
/// checkbox is fixed to the system accent colour (and ignores `.tint` for the
/// checkbox style), so we draw our own box to encode two things at once:
///   • the CHECKMARK = enabled vs disabled (present / absent)
///   • the FILL COLOUR = whether the action is guaranteed in the HUD
///       – green  → always offered (no trait condition)
///       – yellow → conditional (has an active trait; shows only when the
///                  clip matches)
/// Behaviour (click to toggle, disabled state) matches a normal Toggle.
struct EnabledCheckboxToggleStyle: ToggleStyle {
    var onColor: Color = .green
    /// Checkmark colour — kept high-contrast against `onColor` (white on
    /// green, dark on bright yellow).
    var checkColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            // Pad out the hit area to ~20×20 and stamp a rectangular content
            // shape so the WHOLE region (not just the painted box) is
            // clickable. Critical for the OFF state: a `Color.clear` fill is
            // not hit-tested, which made an unchecked action impossible to
            // re-enable.
            box(isOn: configuration.isOn)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }

    private func box(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            // OFF state uses a faint visible fill (never `Color.clear`) so the
            // empty checkbox both reads as clickable and is hit-testable.
            .fill(isOn ? onColor : Color.secondary.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isOn ? onColor : Color.secondary.opacity(0.55),
                                  lineWidth: 1)
            )
            .frame(width: 14, height: 14)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(checkColor)
                    .opacity(isOn ? 1 : 0)
            )
    }
}

// MARK: - Controller (NSWindow lifecycle)

/// Drives which Settings tab is shown. Held by the controller and observed by
/// `SettingsView` so deep links (`drpaste://settings/ai`, …) and the HUD
/// recovery action can jump straight to a specific tab.
@MainActor
final class SettingsNavigation: ObservableObject {
    /// Tab tags: "general", "ai", or a `SemanticKind.rawValue` for content tabs.
    @Published var selectedTab: String = SettingsNavigation.generalTab
    static let generalTab = "general"
    static let aiTab = "ai"
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    let registry: ActionRegistry
    let store: ClipboardStore
    let navigation = SettingsNavigation()

    init(registry: ActionRegistry, store: ClipboardStore) {
        self.registry = registry
        self.store = store
    }

    /// Show Settings, optionally jumping to a specific tab. `tab` is a tag:
    /// "general", "ai", or a `SemanticKind.rawValue` (e.g. "text"). Passing nil
    /// leaves the current tab selection untouched.
    func show(tab: String? = nil) {
        if window == nil {
            let view = SettingsView(registry: registry, store: store, navigation: navigation)
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "DrPaste Settings"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 780, height: 540))
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        }
        if let tab { navigation.selectedTab = tab }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.orderOut(nil) }
}

// MARK: - Root view

struct SettingsView: View {
    @ObservedObject var registry: ActionRegistry
    let store: ClipboardStore
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralTab(registry: registry)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsNavigation.generalTab)
            AIProvidersTab(registry: registry)
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsNavigation.aiTab)
            ForEach(visibleContentTypes, id: \.self) { kind in
                ContentTypeTab(kind: kind, registry: registry, store: store)
                    .tabItem { Label(kind.displayName, systemImage: kind.sfSymbol) }
                    .tag(kind.rawValue)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
    }

    /// Single source of truth — `SemanticKind.userVisibleKinds`.
    /// Keeps the tab list in lock-step with the "Applies to"
    /// checkbox grid in the Edit Action sheet so the user can
    /// reliably reason about what each checkbox enables.
    private var visibleContentTypes: [SemanticKind] {
        SemanticKind.userVisibleKinds
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
    @State private var launchOnLoginEnabled = LoginItemManager.isEnabled
    @State private var launchOnLoginStatus = LoginItemManager.statusMessage

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch DrPaste on login", isOn: launchOnLoginBinding)
                    .disabled(!LoginItemManager.isSupportedBuild)
                    .help(LoginItemManager.statusMessage)
                Text(launchOnLoginStatus)
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
                Text("Hotkey: hold ⌥⌘V to open, release to paste · ⌥⌘C copies · ⌥⌘X cuts & replaces")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Cut & Replace: start cursor on second item (skip just-cut)",
                       isOn: cursorOnSecondBinding)
                Text("When you ⌥⌘X, cursor skips the freshly cut content and starts on the next-older item in history. Default off matches native cut+paste behavior.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show keyboard cheat sheet on ⌥⌘ hold",
                       isOn: cheatSheetEnabledBinding)
                Text("The small corner panel that appears when you hold ⌥⌘ alone — lists global hotkeys and your custom action bindings. Disable if you find it distracting; the hotkeys themselves keep working.")
                    .font(.caption).foregroundStyle(.secondary)
                // #A59 — always-on toggle for the release-to-paste
                // discoverability hint. The hint auto-fades after 5
                // successful commits; this toggle re-enables it
                // permanently for users who want the prompt.
                Toggle("Always show release-to-paste hint in BigHUD",
                       isOn: releaseToPasteHintAlwaysOnBinding)
                Text("The single-line reminder above the history strip in Gesture mode. Quiet by default after the gesture becomes routine; turn this on if you want it permanently visible.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Hold ⌥⌘ after an action hotkey to preview in the HUD",
                       isOn: actionHotkeyHoldPreviewBinding)
                Text("When you fire one of your custom action hotkeys (⌥⌘ + a letter) and keep ⌥⌘ held, the BigHUD opens focused on that action so you can review before pasting. Release quickly and it just runs. Turn this off to always run immediately with no hold-preview.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show detected traits in BigHUD",
                       isOn: traitDebugBinding)
                Text("Developer aid for tuning conditional actions. Shows the ContentContext flags detected on the focused clip; off by default so the HUD stays clean.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sound feedback") {
                HStack {
                    Text("Volume:")
                    Slider(value: $soundVolume, in: 0...1, onEditingChanged: { editing in
                        // Preview only when the user finishes dragging the
                        // slider — never on the programmatic load that happens
                        // every time the Settings window opens (that stray
                        // sound on open was the bug).
                        if !editing { SoundFeedback.playPreview(.copySuccess) }
                    })
                    Text(String(format: "%.0f%%", soundVolume * 100))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                }
                ForEach([SoundCue.copySuccess, .copyFailure, .pasteSuccess, .pasteFailure, .appendCopy, .typeTick, .delete], id: \.rawValue) { cue in
                    Toggle(cueLabel(cue), isOn: cueBinding(cue))
                }
            }

            // #A54 — Per-representation size cap for clipboard captures.
            // Protects index.json + blob storage from massive paste
            // payloads (huge PDFs, video frames, proprietary blobs).
            // Default 16 MB; slider 1–256 MB.
            Section("Capture limits") {
                HStack {
                    Text("Max clipboard item size:")
                    Slider(value: clipboardCapBinding,
                           in: ClipboardSizeCap.minMB...ClipboardSizeCap.maxMB,
                           step: 1)
                    Text("\(Int(clipboardCapBinding.wrappedValue)) MB")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
                Text("Representations above this size are skipped when capturing from the clipboard. The preview text and thumbnail still appear in history; the raw payload is dropped so it doesn't accumulate on disk. Defaults to 16 MB.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // #A60 — explainer for the colored dot on the menu-bar icon
            // and the ⌥⌘S workflow. Without this, a user who hasn't read
            // HELP.md sees "a colored dot appeared on the icon" with no
            // in-product context. Pairs with the dynamic tooltip on the
            // status item itself (set in `updateStatusTooltip`).
            Section("Append Copy") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Red dot — rich-text accumulator")
                                .font(.system(.body, weight: .semibold))
                            Text("Each ⌥⌘S folds the current selection (or last copy) into a running rich-text or image accumulator. ⌥⌘V pastes the merged result.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cyan dot — files accumulator")
                                .font(.system(.body, weight: .semibold))
                            Text("When the first item in the session is a file (or list of files), ⌥⌘S builds a files-only batch — perfect for sending many files to one upload target without copying their bytes.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("The session auto-closes 120 seconds after the last ⌥⌘S, or after any other ⌥⌘ command (⌥⌘V / ⌥⌘C / ⌥⌘X / region capture). Hover the menu-bar icon for a live status tooltip.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                // #A58 — Diagnostics snapshot. Pastes a Markdown report
                // of runtime state to the system clipboard so the user
                // can drop it into an email / GitHub issue without
                // having to open Console.app. The snapshot redacts API
                // keys to last-4 chars; full keys never travel.
                HStack(spacing: 10) {
                    Button {
                        _ = Diagnostics.copyToClipboardViaDelegate()
                        configStatus = "Copied diagnostics to clipboard."
                    } label: {
                        Label("Copy diagnostics", systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                }
                Text("Builds a one-page report (version, runtime state, history stats, configured providers — API keys redacted) and copies it to the clipboard. Paste into a bug report so it's reproducible.")
                    .font(.caption).foregroundStyle(.secondary)

                if let status = configStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.hasPrefix("Failed") ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            refreshLaunchOnLogin()
        }
        .onChange(of: fontScale) { v in
            UserDefaults.standard.set(v, forKey: "drpaste.hud.fontScale")
        }
        .onChange(of: soundVolume) { v in
            // Apply the volume live (both for the slider drag and the
            // programmatic load on open) — but DON'T play a preview here, or
            // opening Settings would chirp every time. The preview fires from
            // the slider's onEditingChanged instead.
            SoundFeedback.setVolume(Float(v))
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

    private var launchOnLoginBinding: Binding<Bool> {
        Binding(
            get: { launchOnLoginEnabled },
            set: { desired in
                do {
                    let result = try LoginItemManager.setEnabled(desired)
                    launchOnLoginEnabled = result.enabled
                    launchOnLoginStatus = result.message
                } catch {
                    let result = LoginItemManager.refresh()
                    launchOnLoginEnabled = result.enabled
                    launchOnLoginStatus = error.localizedDescription
                }
            }
        )
    }

    private func refreshLaunchOnLogin() {
        let result = LoginItemManager.refresh()
        launchOnLoginEnabled = result.enabled
        launchOnLoginStatus = result.message
    }

    private var cursorOnSecondBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: "drpaste.hud.cursorOnSecondOnCut") },
            set: { UserDefaults.standard.set($0, forKey: "drpaste.hud.cursorOnSecondOnCut") }
        )
    }

    /// Default-on toggle for the ⌥⌘-hold corner cheat sheet. Stored
    /// inverted (`disabled` flag) so the cheat sheet keeps appearing
    /// for users who haven't touched the setting — only an explicit
    /// disable persists. `RegionCaptureCheatSheetController.show()`
    /// reads the same key and bails early when disabled.
    private var cheatSheetEnabledBinding: Binding<Bool> {
        Binding(
            get: { !UserDefaults.standard.bool(forKey: "drpaste.cheatSheet.disabled") },
            set: { UserDefaults.standard.set(!$0, forKey: "drpaste.cheatSheet.disabled") }
        )
    }

    /// Default-on toggle for the action-hotkey hold-preview (⌥⌘ + letter
    /// held → BigHUD focused on that action). Stored inverted (`disabled`
    /// flag) so the preview keeps working for users who never touch it —
    /// only an explicit disable persists. `HotkeyEngine` reads the same
    /// key and fires the action immediately when disabled.
    private var actionHotkeyHoldPreviewBinding: Binding<Bool> {
        Binding(
            get: { !UserDefaults.standard.bool(forKey: PreferenceKeys.actionHotkeyHoldPreviewDisabled) },
            set: { UserDefaults.standard.set(!$0, forKey: PreferenceKeys.actionHotkeyHoldPreviewDisabled) }
        )
    }

    private var traitDebugBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: PreferenceKeys.hudShowTraitDebug) },
            set: { UserDefaults.standard.set($0, forKey: PreferenceKeys.hudShowTraitDebug) }
        )
    }

    /// #A59 — toggle binding for "always show release-to-paste hint".
    /// Default off (auto-fade after 5 commits); explicit on forces
    /// the hint permanently visible.
    private var releaseToPasteHintAlwaysOnBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: "drpaste.hint.releaseToPaste.forceShow") },
            set: { UserDefaults.standard.set($0, forKey: "drpaste.hint.releaseToPaste.forceShow") }
        )
    }

    /// #A54 — slider binding for the per-representation clipboard cap.
    /// Stored as MB (double) under `ClipboardSizeCap.key`. Live read —
    /// the next `snapshotPasteboard` call picks up the new value
    /// without restart.
    private var clipboardCapBinding: Binding<Double> {
        Binding(
            get: {
                let raw = UserDefaults.standard.double(forKey: ClipboardSizeCap.key)
                return raw == 0 ? ClipboardSizeCap.defaultMB : raw
            },
            set: { UserDefaults.standard.set($0, forKey: ClipboardSizeCap.key) }
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

    /// Per-provider live usage snapshot (today's cost / requests /
    /// tokens). Populated asynchronously on tab appear and on
    /// manual refresh — see `refreshUsage(for:)`. Providers without
    /// a public usage API (Anthropic / Gemini / local) never get
    /// an entry; the row hides the usage line for those.
    @State private var usageByProvider: [String: UsageSnapshot] = [:]
    /// Per-provider "fetch in flight" flag — drives the small
    /// spinner on the usage line so the user knows a refresh is
    /// happening (rather than thinking the row is stale).
    @State private var usageLoadingByProvider: [String: Bool] = [:]
    /// Providers whose probe returned `notSupportedForKey` (401/403
    /// — key works for inference but lacks the org/billing scope
    /// the usage endpoint wants). We don't surface this as a
    /// permanent error in the UI because the user can't fix it
    /// from inside DrPaste — instead the usage line is hidden
    /// entirely for these providers, same treatment as Anthropic
    /// / Gemini / local providers that have no usage API at all.
    @State private var usageUnsupportedProviders: Set<String> = []

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
        .task {
            // Connection probes and usage probes run in parallel —
            // independent endpoints, no shared rate-limit budget,
            // no reason to serialize. Both populate row chrome
            // (status dot + usage line) as soon as their HTTP
            // round-trips return.
            async let statuses: () = refreshAllStatuses()
            async let usage: () = refreshAllUsage()
            _ = await (statuses, usage)
        }
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
                // Today's usage line — only shown for providers that
                // (a) expose a public usage API at all (OpenAI /
                // OpenRouter so far) AND (b) accepted our key for
                // that endpoint. Hidden entirely otherwise so the
                // row stays compact for providers we can't probe
                // OR whose probe came back 401/403 (no fix path
                // from inside DrPaste — see
                // `usageUnsupportedProviders` doc).
                if UsageProbeRegistry.probe(for: p.kind) != nil,
                   !usageUnsupportedProviders.contains(p.id) {
                    usageLine(for: p, isReady: isReady)
                }
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

    /// Compact "Today: $0.42 · 14 reqs · 12,345 tokens" line under
    /// the provider name. Three states:
    ///   • Loading — small inline spinner + "Today: loading…"
    ///   • Loaded with error — orange dot + truncated error
    ///     (missing admin key, 401, etc.) so the user knows
    ///     what to fix
    ///   • Loaded OK — formatted numbers, clickable to refresh
    ///
    /// The whole line is wrapped in a Button so a click triggers
    /// `refreshUsage(for:)` — gives the user manual control without
    /// a separate refresh icon eating row space.
    @ViewBuilder
    private func usageLine(for p: ConfiguredProvider, isReady: Bool) -> some View {
        let loading = usageLoadingByProvider[p.id] == true
        let snap = usageByProvider[p.id]
        Button {
            Task { await refreshUsage(for: p) }
        } label: {
            HStack(spacing: 4) {
                if loading {
                    ProgressView().controlSize(.mini).scaleEffect(0.55)
                        .frame(width: 8, height: 8)
                    Text("Today: loading…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else if let snap = snap, let err = snap.error {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("Today: \(err)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let snap = snap {
                    Text(formattedUsageLine(snap, providerKind: p.kind))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                } else if isReady {
                    Text("Today: tap to fetch")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isReady)
        .help(usageTooltip(snap: snap))
    }

    /// Compose the numeric line. Cost always shown; requests and
    /// tokens only when the probe populated them (OpenAI costs API
    /// doesn't return tokens; OpenRouter doesn't return per-day
    /// request counts) — we don't print "0 reqs" when we just
    /// don't know.
    private func formattedUsageLine(_ snap: UsageSnapshot, providerKind: ProviderKind) -> String {
        var parts: [String] = []
        parts.append("Today: $\(String(format: "%.3f", snap.costUSD))")
        if snap.requestCount > 0 {
            parts.append("\(snap.requestCount) reqs")
        }
        if snap.tokenCount > 0 {
            // Thousands separator for readability.
            let f = NumberFormatter()
            f.numberStyle = .decimal
            let tk = f.string(from: NSNumber(value: snap.tokenCount)) ?? "\(snap.tokenCount)"
            parts.append("\(tk) tokens")
        }
        return parts.joined(separator: " · ")
    }

    private func usageTooltip(snap: UsageSnapshot?) -> String {
        guard let snap = snap else { return "Click to fetch today's usage from the provider." }
        if let err = snap.error { return "Fetch failed: \(err). Click to retry." }
        let ago = Int(Date().timeIntervalSince(snap.fetchedAt))
        let agoText = ago < 60 ? "\(ago)s ago"
                     : ago < 3600 ? "\(ago/60)m ago"
                     : "\(ago/3600)h ago"
        return "Updated \(agoText). Click to refresh."
    }

    /// Fire one provider's usage probe. Catches all errors and
    /// stores them on the snapshot so the row renders a single
    /// orange dot + reason instead of throwing. Special-cases
    /// `.notSupportedForKey` (401/403): marks the provider as
    /// permanently unsupported for this session so the row hides
    /// the usage line entirely — same UX as Anthropic / Gemini /
    /// local providers that have no usage API to begin with.
    private func refreshUsage(for p: ConfiguredProvider) async {
        guard let probe = UsageProbeRegistry.probe(for: p.kind) else { return }
        await MainActor.run { usageLoadingByProvider[p.id] = true }
        defer { Task { @MainActor in usageLoadingByProvider[p.id] = false } }
        do {
            let snap = try await probe.fetchToday(provider: p)
            await MainActor.run {
                usageByProvider[p.id] = snap
                usageUnsupportedProviders.remove(p.id)
            }
        } catch UsageProbeError.notSupportedForKey {
            await MainActor.run {
                usageUnsupportedProviders.insert(p.id)
                usageByProvider.removeValue(forKey: p.id)
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            await MainActor.run {
                usageByProvider[p.id] = UsageSnapshot(costUSD: 0,
                                                       requestCount: 0,
                                                       tokenCount: 0,
                                                       fetchedAt: Date(),
                                                       error: msg)
            }
        }
    }

    /// Same idea as `refreshAllStatuses` but for usage probes —
    /// fires every enabled provider's probe in parallel so the
    /// tab populates quickly even on slow networks.
    private func refreshAllUsage() async {
        await withTaskGroup(of: Void.self) { group in
            for p in providerRegistry.config.providers {
                guard UsageProbeRegistry.probe(for: p.kind) != nil else { continue }
                let hasKey = APIKeyStorage.load(for: p.id) != nil
                let isReady = p.kind.isLocal || hasKey
                guard isReady else { continue }
                group.addTask { await refreshUsage(for: p) }
            }
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

            // Image-capability note. Tells the user upfront what
            // routing this provider gets when an image action
            // (AI: Watercolor / AI: Whiteboard sketch / etc.) is
            // run against it — particularly important for the
            // `.custom` kind where DrPaste sends OpenAI-shape
            // `/images/edits` and `/images/generations` requests
            // and the user's endpoint may or may not implement
            // them. For Anthropic / Groq / etc. (no image edit)
            // we explicitly say so to set expectations.
            imageCapabilityNote
                .padding(.vertical, 2)

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

    /// Per-provider note explaining the image-action routing —
    /// shown above "Test connection" so the user knows ahead of time
    /// what shape of HTTP request their endpoint will receive when
    /// an image action targets it. Critical for `.custom` where the
    /// user picks the URL and we can't probe what it speaks; useful
    /// for all kinds so the picture is consistent.
    @ViewBuilder
    private var imageCapabilityNote: some View {
        let kind = provider.kind
        if kind == .custom {
            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: 110)
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image actions: OpenAI wire format")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("If you target this provider from an image action (Pencil sketch, Watercolor, Whiteboard sketch, …), DrPaste sends OpenAI-shape requests to `<Base URL>/images/edits` (image→image) and `<Base URL>/images/generations` (text→image). Works against proxies that mirror the OpenAI API. If your endpoint doesn't implement those routes, image actions will fail with an HTTP error — text actions still work normally.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        } else if kind.supportsImageEdit {
            // OpenAI / Gemini / OpenRouter — native routing handled
            // by AIImageHTTP per-kind dispatch.
            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: 110)
                Image(systemName: "photo.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image actions: supported")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(imageRouteDescription(for: kind))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        } else {
            // Text-only providers (Anthropic / Ollama / Groq / etc.).
            // Explicit "won't work" message — sets expectations so
            // the user doesn't waste time wiring this provider into
            // an image action and watching it fail.
            HStack(alignment: .top, spacing: 6) {
                Spacer().frame(width: 110)
                Image(systemName: "photo.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image actions: not supported")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(kind.displayName) doesn't have an image-edit / generation API in DrPaste. Use it for text actions (Translate, Summarize, etc.) — image actions need OpenAI, Google Gemini, OpenRouter (with an image-capable model), or a Custom OpenAI-compatible endpoint.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    /// Per-kind short description of the image-route DrPaste uses.
    /// Surfaced in the green "Image actions: supported" note so the
    /// user can see which model their image actions actually hit.
    private func imageRouteDescription(for kind: ProviderKind) -> String {
        switch kind {
        case .openai:
            return "Routes to `gpt-image-1` via `/v1/images/edits` (image→image) and `/v1/images/generations` (text→image). ~$0.04 per 1024×1024 image, standard quality."
        case .gemini:
            return "Routes to `gemini-2.5-flash-image-preview` via `:generateContent`. Image returned as inlineData base64 in the response. Cheap (~$0.005-0.01 per image)."
        case .openrouter:
            return "Routes to your configured model via `/v1/chat/completions` with multimodal content. Works only if the model supports image output (e.g. `google/gemini-2.5-flash-image-preview`, Flux via `fal-ai/*`). Text-only chat models will fail with “no image returned”."
        default:
            return ""
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
    /// For image-kind tabs only: the current Sample Input image. Loaded
    /// on appear from `ActionTestSamples.makeSampleImageItem()` (bundled
    /// Mandrill if present, else procedural portrait), drag-drop-
    /// replaceable. nil for non-image tabs.
    @State private var sampleImageItem: ClipboardItem? = nil
    @State private var result: ApplyOutcome? = nil
    @State private var runningID: String? = nil
    /// Action title shown in the Result loading panel so the user
    /// always sees WHAT is currently processing — not just an
    /// anonymous "processing…" spinner. Cleared on completion.
    @State private var runningActionTitle: String? = nil
    /// AI inflight chrome for the Result pane — populated when an AI
    /// action is running, cleared on completion. nil for local
    /// transformations (the action-title path covers those instead).
    @State private var resultInflight: AIInflight? = nil
    @State private var resultElapsed: TimeInterval = 0
    @State private var resultTickTask: Task<Void, Never>? = nil
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
        .onAppear {
            // Load persisted user overrides before falling back to
            // the curated defaults. Sample input edits and dropped
            // images now survive app restart (actions.json).
            if kind == .image {
                if let rel = registry.playgroundImageRel(forKind: kind),
                   FileManager.default.fileExists(atPath:
                        AppStorage.imagesDir.appendingPathComponent(rel).path),
                   let item = loadPlaygroundImageItem(rel: rel) {
                    sampleImageItem = item
                } else {
                    sampleImageItem = SettingsSamples.sample(for: kind)
                }
            } else {
                if let override = registry.playgroundSample(forKind: kind) {
                    sampleText = override
                } else {
                    sampleText = SettingsSamples.sample(for: kind).previewText ?? ""
                }
            }
        }
        .onChange(of: sampleText) { newValue in
            // Persist on every keystroke. Cheap — actions.json is
            // tiny (~few KB) and JSONEncoder is fast. The registry
            // helper diffs against the curated default and removes
            // the override when the text matches, so just hammering
            // Reset never leaves stale entries behind.
            guard kind != .image else { return }
            registry.setPlaygroundSample(newValue, forKind: kind)
        }
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Sample input").font(.headline)
                // Kind-specific affordance hint — tells the user what
                // they can do here without having to discover it.
                // Image tab: drop a picture from Finder. Other tabs:
                // editable text. Keeps the header compact (caption2)
                // while still being legible.
                Text(sampleInputHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button("Reset") { resetSample() }
                    .controlSize(.small)
            }
            // Per-kind Sample input:
            //   • image    → live image preview + drop target
            //   • richText → read-only rendered RTF preview. The
            //                curated sample is a hand-built
            //                NSAttributedString with headings, bold,
            //                italic, and hyperlinks; rendering it
            //                through a plain TextEditor would strip
            //                the formatting on display, so the user
            //                needs RichTextPreviewView to actually
            //                see the sample.
            //   • all other → standard editable monospaced text
            //                editor. Markdown stays plain text here
            //                — its source IS plain text with markers;
            //                if the user wants to see the rendered
            //                version they click Run on any markdown
            //                action (md_to_plain, a custom AI, etc.)
            //                and the Result pane already renders
            //                action output. No need for a redundant
            //                second preview panel.
            switch kind {
            case .image:
                sampleImagePanel
            case .richText:
                sampleRichTextPreview
            default:
                TextEditor(text: $sampleText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            Text("Result").font(.headline).padding(.top, 6)
            // Replace the legacy ResultPane (text-only switch on
            // ApplyOutcome) with TestOutputPane, the same HUD-style
            // renderer the Edit Action sheet uses. Gives the
            // Playground identical chrome: spinner with "Provider ·
            // Model · 4.2s" for AI actions, failure notices, image /
            // rich-text / files preview, etc.
            // Playground Result pane has many actions on the right
            // — no single "the action to run" mapping for an empty-
            // state play button. Keep onRun nil so the placeholder
            // stays text-only ("Click Run next to an action…"); the
            // user picks which action to fire via the explicit Run
            // buttons in the actions list. Edit Action sheet (one
            // action under test) is where the play-button affordance
            // is meaningful — it passes onRun there.
            //
            // `actionTitle` flows into the loading panel so the user
            // sees WHICH action is currently running (Translate, AI:
            // Watercolor, Slugify, …) — even local transformations
            // get a meaningful title above the spinner instead of
            // an anonymous "processing…".
            TestOutputPane(
                outcome: result,
                isRunning: runningID != nil,
                inflight: resultInflight,
                elapsed: resultElapsed,
                actionTitle: runningActionTitle
            )
            .frame(maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    /// Per-kind affordance hint shown next to the "Sample input"
    /// header — discoverability for drag-drop and "you can edit
    /// this" semantics. Most users don't think to try a drop until
    /// you tell them, and the Image tab in particular was looking
    /// like a static preview before the hint was added.
    private var sampleInputHint: String {
        switch kind {
        case .image:
            return "— drop an image here to replace the sample"
        case .richText:
            return "— read-only rich-text preview"
        default:
            return "— edit the text or drag text content in"
        }
    }

    /// Rich-text Sample input: read-only rendered preview of the
    /// curated NSAttributedString sample. We display the actual
    /// formatted text (headings, bold, italic, hyperlink) through
    /// the same NSTextView wrapper BigHUD uses — gives the user a
    /// honest visual of what gets fed into rich_to_md / rich_to_html /
    /// rich_to_wiki when they click Run. Read-only because the
    /// curated sample is built programmatically (`richTextSample()`
    /// in ActionConfig.swift) and a TextEditor would only allow plain-
    /// text edits, destroying the formatting on first keystroke.
    @ViewBuilder
    private var sampleRichTextPreview: some View {
        let sampleItem = SettingsSamples.sample(for: .richText)
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3))
            if let attr = RichTextLoader.attributedString(from: sampleItem) {
                RichTextPreviewView(attributedString: attr, fontScale: 1.0)
                    .padding(6)
            } else {
                Text("(no rich text sample available)")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Image-kind Sample input: live preview of the current sample
    /// image with a drop target overlay so the user can replace the
    /// bundled / procedural default with their own picture by dragging
    /// it in from Finder or another app.
    @ViewBuilder
    private var sampleImagePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3))
            if let item = sampleImageItem {
                ImagePreview(item: item)
                    .padding(6)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("Drop an image here").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: ["public.file-url", "public.image"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
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
                        DispatchQueue.main.async { handleDroppedSampleImage(at: url) }
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data = data else { return }
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("drpaste-playground-drop-\(UUID().uuidString).png")
                    try? data.write(to: tmp)
                    DispatchQueue.main.async { handleDroppedSampleImage(at: tmp) }
                }
                return true
            }
            return false
        }
    }

    /// Drop handler — copies the dropped image into AppStorage.imagesDir
    /// under a stable per-tab filename so repeated runs reuse the
    /// bytes, then refreshes the in-memory sampleImageItem so the
    /// preview updates immediately.
    @MainActor
    private func handleDroppedSampleImage(at sourceURL: URL) {
        guard let data = try? Data(contentsOf: sourceURL),
              let img = NSImage(data: data) else { return }
        let pngData: Data = {
            if data.count > 8,
               data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 {
                return data
            }
            if let tiff = img.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff),
               let png = bmp.representation(using: .png, properties: [:]) {
                return png
            }
            return data
        }()
        let rel = "drpaste-playground-image-sample.png"
        let imagesURL = AppStorage.imagesDir.appendingPathComponent(rel)
        let blobName = rel + ".bin"
        let blobURL = AppStorage.blobsDir.appendingPathComponent(blobName)
        do {
            try pngData.write(to: imagesURL, options: .atomic)
            try pngData.write(to: blobURL, options: .atomic)
        } catch {
            return
        }
        let (w, h): (Int, Int) = {
            if let rep = img.representations.first {
                return (rep.pixelsWide, rep.pixelsHigh)
            }
            return (Int(img.size.width), Int(img.size.height))
        }()
        sampleImageItem = ClipboardItem(
            id: UUID(),
            semantic: .image,
            createdAt: Date(),
            representations: ["public.png": blobName],
            typesOrdered: ["public.png"],
            previewText: "Custom playground image \(pngData.count / 1024) KB",
            previewImageRel: rel,
            originalImageWidth: w,
            originalImageHeight: h,
            originalImageFileSize: pngData.count,
            imageFormat: "PNG",
            sourceBundleID: nil,
            sourceAppName: "Settings Playground",
            sourceWindowTitle: nil,
            tags: []
        )
        // Persist the drop so the next Settings open shows the same
        // custom picture instead of resetting to Mandrill / wallpaper.
        registry.setPlaygroundImageRel(rel, forKind: kind)
    }

    /// Reconstruct a ClipboardItem from a persisted image rel for the
    /// Playground onAppear path. Mirrors handleDroppedSampleImage's
    /// item shape so the live UI is identical after restart.
    @MainActor
    private func loadPlaygroundImageItem(rel: String) -> ClipboardItem? {
        let url = AppStorage.imagesDir.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return nil }
        let blobName = rel + ".bin"
        let blobURL = AppStorage.blobsDir.appendingPathComponent(blobName)
        if !FileManager.default.fileExists(atPath: blobURL.path) {
            try? data.write(to: blobURL)
        }
        let (w, h): (Int, Int) = {
            if let rep = img.representations.first {
                return (rep.pixelsWide, rep.pixelsHigh)
            }
            return (Int(img.size.width), Int(img.size.height))
        }()
        return ClipboardItem(
            id: UUID(),
            semantic: .image,
            createdAt: Date(),
            representations: ["public.png": blobName],
            typesOrdered: ["public.png"],
            previewText: "Custom playground image \(data.count / 1024) KB",
            previewImageRel: rel,
            originalImageWidth: w,
            originalImageHeight: h,
            originalImageFileSize: data.count,
            imageFormat: "PNG",
            sourceBundleID: nil,
            sourceAppName: "Settings Playground",
            sourceWindowTitle: nil,
            tags: []
        )
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
        // Membership is by content TYPE ("Applies to"), NOT by live trait
        // conditions. A trait gates HUD visibility against the real clip; in
        // Settings the user must still see and manage every action for the
        // tab's type — otherwise setting a condition makes the action vanish
        // from the list and become impossible to find / edit again.
        let applicable = registry.actions.filter { $0.appliesToContentType(item: item, context: ctx) }
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
                .toggleStyle(registry.hasActiveTraits(action.id)
                    ? EnabledCheckboxToggleStyle(onColor: Color(red: 1.0, green: 0.82, blue: 0.0),
                                                 checkColor: .black)
                    : EnabledCheckboxToggleStyle(onColor: Color(red: 0.56, green: 0.85, blue: 0.40),
                                                 checkColor: .black))
                .help(registry.hasActiveTraits(action.id)
                    ? "Conditional — shown in the HUD only when the clip matches this action’s trait condition."
                    : "Always offered in the HUD when enabled.")
            leadingIcon(for: action)
            // Title row. When the user has renamed the action, the
            // factory default appears inline to the right of the
            // custom title in tertiary colour. Earlier this lived on
            // its own second line ("default: <title>"), which doubled
            // the row's vertical footprint just to remind the user
            // what they overrode. Inline + colour difference is
            // enough — no "default:" prefix needed, the dimmer text
            // already reads as "the original".
            // Title + second-line description. The blurb (resolved per
            // action type) gives the user a one-line reminder of what the
            // action does without opening the editor — the list reads like
            // a captioned menu instead of a column of bare titles.
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayTitle)
                        .lineLimit(1)
                    if isCustomized {
                        Text(action.title)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                if let subtitle = actionSubtitle(action) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            // Let the title/description column claim all the slack up to the
            // controls (instead of a Spacer eating it) so the truncated text
            // gets the empty room on the right.
            .frame(maxWidth: .infinity, alignment: .leading)
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
            // Plain "Edit" — the pencil glyph was identical on every row and
            // just ate horizontal space, so it's dropped (text label only).
            Button {
                openEditor(for: action)
                // Always raise the editor window after setting the
                // context — handles the "same action re-clicked"
                // case where editorContext doesn't change so the
                // SwiftUI `onChange(of: editorContextKey)` handler
                // never fires and the window stays buried behind
                // Settings. Dispatched on the next runloop tick so
                // the onChange-driven show() (if any) has a chance
                // to build / replace the window first; raise() then
                // hits whatever window ended up there.
                DispatchQueue.main.async {
                    editorWindow.raise()
                }
            } label: {
                Text("Edit")
            }
            .controlSize(.small)
            .help("Edit this action — title, prompt, provider, hotkey, applicable types")
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
        // Disabled rows are dimmed but must stay legible — 0.45 made the
        // (already secondary) description unreadable, so 0.6.
        .opacity(isEnabled ? 1.0 : 0.6)
    }

    /// Background tint distinguishes user-defined actions (subtle accent) from
    /// built-ins (neutral) without breaking the unified list visual rhythm.
    private func rowBackground(for action: ClipboardAction) -> Color {
        if action is AIAction
            || action is AIImageAction
            || action is CustomTransformationAction {
            return Color.accentColor.opacity(0.06)
        }
        return Color.primary.opacity(0.03)
    }

    /// Leading type icon — provider badge for AI, engine glyph for transformations,
    /// built-in SF Symbol otherwise. Provider badge resolves the default dynamically,
    /// so seeded actions follow whichever provider is currently default.
    @ViewBuilder
    private func leadingIcon(for action: ClipboardAction) -> some View {
        // Both AIAction (text) and AIImageAction (image) deserve the
        // provider badge — they're both AI calls and the user wants
        // to know which provider runs them. Bug: image actions used
        // to fall through to the generic gear-icon BuiltinActionIcons
        // path because the cast `action as? AIAction` missed
        // AIImageAction (separate struct, not subclass). Fixed by
        // checking both casts and feeding the resolved providerID
        // through the same `providerBadge` helper.
        if let ai = action as? AIAction {
            let badge = providerBadge(providerID: ai.providerID, isImage: false)
            ProviderBadgeView(text: badge.label, color: badge.color,
                              fontSize: 11, iconName: badge.icon)
        } else if let ai = action as? AIImageAction {
            let badge = providerBadge(providerID: ai.providerID, isImage: true)
            // Disabled state when the resolved provider can't actually
            // do image edits — the badge renders grayscale + slash so
            // the user spots the mismatch without running.
            ProviderBadgeView(text: badge.label, color: badge.color,
                              fontSize: 11, iconName: badge.icon,
                              isAvailable: imageProviderAvailable(forID: ai.providerID))
        } else if let ai = action as? AITextToImageAction {
            // Same image-capable provider check as AIImageAction —
            // text→image generation also requires an image-output
            // provider, just doesn't take an image as input.
            let badge = providerBadge(providerID: ai.providerID, isImage: true)
            ProviderBadgeView(text: badge.label, color: badge.color,
                              fontSize: 11, iconName: badge.icon,
                              isAvailable: imageProviderAvailable(forID: ai.providerID))
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

    /// One-line description shown as the row's second line in the action list.
    /// Resolves per action type:
    /// - Custom AI → the prompt template (a reminder of what it asks the model),
    /// - Custom transformation → its engine's generic description,
    /// - Built-in → the bundled `BuiltinActionMetadata` blurb.
    /// Returns nil when nothing meaningful is available (row stays single-line).
    private func actionSubtitle(_ action: ClipboardAction) -> String? {
        // 1. User override wins over any bundled default.
        if let custom = registry.customDescription(forActionID: action.id) {
            let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        // 2. Bundled short descriptor (built-in AND default AI / image actions
        //    are keyed by id here). Beats the raw AI prompt template.
        if let d = BuiltinActionMetadata.descriptions[action.id]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        // 3. Custom (user-authored) AI action — fall back to its prompt.
        if let desc = registry.config.customAI.first(where: { $0.id == action.id }) {
            if let d = desc.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !d.isEmpty {
                return d
            }
            let p = desc.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            return p.isEmpty ? nil : p
        }
        // 4. Custom transformation — its engine's description.
        if let tx = action as? CustomTransformationAction {
            if let d = tx.descriptor.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !d.isEmpty {
                return d
            }
            let d = (tx.descriptor.engine?.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return d.isEmpty ? nil : d
        }
        return nil
    }

    /// Routes the pencil button to the correct editor sheet for the action's type.
    /// Both `AIAction` (text-in/text-out) and `AIImageAction` (image-in/image-out)
    /// are materialised from `CustomAIDescriptor` entries with different `kind`
    /// values, so the editor route is the same `.editAI(desc)` for both — the
    /// ActionEditor sheet preserves `kind` on save and renders the prompt /
    /// provider picker / hotkey fields the same way regardless. Checking by
    /// descriptor membership instead of concrete type also covers any future
    /// AIAction variants that ship as customAI without us having to update
    /// this routing arm.
    private func openEditor(for action: ClipboardAction) {
        if let desc = registry.config.customAI.first(where: { $0.id == action.id }) {
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

    /// Provider badge for an AI action in the Settings list (mirrors
    /// HUD chip). Resolves dynamically: nil/empty providerID means
    /// "follow whatever is currently default" so seeded actions
    /// always show the live default provider's brand. When the user
    /// flips the default in Settings → AI, every default-bound row
    /// repaints because `@ObservedObject providerRegistry` republishes.
    ///
    /// Whether an AI action can actually execute — runs the same
    /// resolver as the badge and returns true iff a valid worker
    /// provider exists. Used by the row's leading icon to render
    /// disabled (greyscale + slash) when nothing in the registry
    /// can handle the action's capability requirement.
    private func imageProviderAvailable(forID providerID: String?) -> Bool {
        resolveExecutorProvider(explicitID: providerID, operationKind: .imageEdit) != nil
    }

    /// Settings-side adapter around `ProviderResolver`: action row badges and
    /// availability slashes now use the same resolved provider struct as BigHUD.
    private func resolveExecutorProvider(explicitID: String?, operationKind: AIOperationKind)
        -> ResolvedAIProvider?
    {
        let cfg = AIProviderRegistry.shared.config
        return ProviderResolver.resolve(
            nominalProviderID: explicitID,
            operationKind: operationKind,
            config: cfg,
            hasKey: { id in
                ProviderResolver.runtimeHasCredential(providerID: id,
                                                      operationKind: operationKind,
                                                      config: cfg)
            }
        )
    }

    private func providerBadge(providerID: String?, isImage: Bool)
        -> (label: String, color: Color, icon: String)
    {
        let operationKind: AIOperationKind = isImage ? .imageEdit : .text
        guard let resolved = resolveExecutorProvider(explicitID: providerID,
                                                     operationKind: operationKind) else {
            return ("AI", .gray, "sparkle")
        }
        // Single source of truth for the brand palette — see
        // `ProviderKind.brandColor`. Used here in the Settings actions
        // list, in HUD chip badges, and in the Settings provider list,
        // so the same brand always paints the same hue.
        return (resolved.providerKind.badgeLabel,
                resolved.providerKind.brandColor,
                resolved.providerKind.iconName)
    }

    private func enabledBinding(_ actionID: String) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled(actionID) },
            set: { registry.setEnabled($0, for: actionID) }
        )
    }

    private func makeSampleItem() -> ClipboardItem {
        // Image tab uses the in-memory sampleImageItem (bundled
        // Mandrill / procedural portrait / user-dropped picture).
        // Text-based tabs use the text from the editor, wrapped in
        // the kind-appropriate ClipboardItem shape.
        if kind == .image, let img = sampleImageItem {
            return img
        }
        var item = SettingsSamples.sample(for: kind)
        item.previewText = sampleText
        return item
    }

    private func resetSample() {
        // Drop any persisted override BEFORE rebuilding the in-memory
        // sample — registry.set*(nil, ...) removes the entry from
        // actions.json so the next Settings open reads the curated
        // default fresh. The onChange handler would otherwise re-
        // persist the curated value because the in-memory text just
        // changed.
        if kind == .image {
            registry.setPlaygroundImageRel(nil, forKind: kind)
        } else {
            registry.setPlaygroundSample(nil, forKind: kind)
        }
        let fresh = SettingsSamples.sample(for: kind)
        if kind == .image {
            sampleImageItem = fresh
        } else {
            sampleText = fresh.previewText ?? ""
        }
    }

    private func run(_ action: ClipboardAction) {
        // Image-info and Strip-metadata need an input that actually carries
        // metadata to demonstrate anything — the standard PNG sample is
        // metadata-free.
        let metadataActions: Set<String> = ["builtin.image.strip_metadata", "builtin.image.info"]
        let item: ClipboardItem = {
            if metadataActions.contains(action.id), kind == .image,
               let rich = ActionTestSamples.makeMetadataRichSampleItem() {
                return rich
            }
            return makeSampleItem()
        }()
        let ctx = ContextDetector.detect(item)
        runningID = action.id
        runningActionTitle = registry.displayTitle(forActionID: action.id,
                                                    defaultTitle: action.title)
        result = nil
        resultElapsed = 0
        resultTickTask?.cancel()
        resultTickTask = nil
        // Populate AI chrome for the Result pane spinner when the
        // action talks to a provider — text AIAction, AIImageAction,
        // and AITextToImageAction all route through here. Reach into
        // AIProviderRegistry directly so the Playground doesn't
        // depend on AppDelegate.
        resultInflight = inflight(for: action)
        // Always start the tick — even local actions get an
        // elapsed counter and the action-title chrome via
        // TestOutputPane. Spinner without context is unhelpful;
        // spinner with "Trim · 0.1s" tells the user what's running.
        startResultTick()
        Task {
            let outcome = await action.apply(item: item, context: ctx)
            await MainActor.run {
                self.result = outcome
                self.runningID = nil
                self.runningActionTitle = nil
                self.stopResultTick()
                self.resultInflight = nil
                // NB: do NOT auto-perform side effects here. Running the test
                // should only PREVIEW the result; opening Finder on every Run
                // is intrusive. The side-effect notice itself is a button the
                // user clicks to actually fire it.
            }
        }
    }

    /// Build the loading-panel inflight descriptor for an AI action,
    /// or return nil for local actions (which still get an action-
    /// title + elapsed-time chrome via TestOutputPane's title path).
    ///
    /// Resolution follows the SAME chain runtime uses (per-action
    /// override → default → image-capable soft fallback). Without
    /// this the Result panel lies — showing "Anthropic Claude" for
    /// an image action whose chat default is Anthropic but whose
    /// REAL execution rerouted to OpenAI via the soft fallback in
    /// `AIImageAction.resolveProvider`.
    private func inflight(for action: ClipboardAction) -> AIInflight? {
        let explicitID: String?
        let operationKind: AIOperationKind
        if let ai = action as? AIAction {
            explicitID = ai.providerID
            operationKind = .text
        } else if let ai = action as? AIImageAction {
            explicitID = ai.providerID
            operationKind = .imageEdit
        } else if let ai = action as? AITextToImageAction {
            explicitID = ai.providerID
            operationKind = .textToImage
        } else {
            return nil
        }
        let cfg = AIProviderRegistry.shared.config
        let resolved = ProviderResolver.resolve(
            nominalProviderID: explicitID,
            operationKind: operationKind,
            config: cfg,
            hasKey: { id in
                ProviderResolver.runtimeHasCredential(providerID: id,
                                                      operationKind: operationKind,
                                                      config: cfg)
            }
        )
        guard let resolved else {
            return AIInflight(providerLabel: "AI",
                              modelName: "unknown",
                              actionTitle: action.title,
                              startedAt: Date())
        }
        let modelLabel = operationKind == .text
            ? resolved.modelLabel
            : (resolved.providerKind == .gemini ? "gemini-2.5-flash-image-preview" : "gpt-image-1")
        return AIInflight(providerLabel: resolved.providerLabel,
                          modelName: modelLabel,
                          actionTitle: action.title,
                          startedAt: Date())
    }

    @MainActor
    private func startResultTick() {
        stopResultTick()
        let started = resultInflight?.startedAt ?? Date()
        resultTickTask = ElapsedTicker.start(startedAt: started) { elapsed in
            self.resultElapsed = elapsed
        }
    }

    @MainActor
    private func stopResultTick() {
        resultTickTask?.cancel()
        resultTickTask = nil
    }

}

// Legacy `ResultPane` was replaced by `TestOutputPane` (file
// TestOutputPane.swift) — the same HUD-style component the Edit
// Action sheet uses. One renderer for both surfaces guarantees
// identical chrome (spinner / Provider · Model · 4.2s / failure
// notice / image-and-rich-text preview) so the user sees the same
// result presentation everywhere.

// Import/Export controls live in GeneralTab → "Configuration" section.
