//
//  main.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyEngineDelegate, NSMenuDelegate {

    var store: ClipboardStore!
    var watcher: ClipboardWatcher!
    var registry: ActionRegistry!
    var aiProvider: AnthropicProvider!

    var engine: HotkeyEngine!
    var hudPanel: HudPanel?
    var hudState: HudState!
    var statusItem: NSStatusItem!
    var settingsController: SettingsWindowController?

    private var statusMenu: NSMenu!
    private var recentMenu: NSMenu!
    private var previewToken: Int = 0
    private var axTrustPollTimer: Timer?
    private var lastAXTrusted: Bool = false
    private var localKeyMonitor: Any?
    private var savedFrontmostApp: NSRunningApplication?
    private var currentSummonReason: SummonReason = .paste

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipboardStore()
        watcher = ClipboardWatcher(store: store)
        watcher.start()

        registry = ActionRegistry()

        // Content-aware action packs (Backlog #4)
        registry.register(TextActionsPack.all)
        registry.register(URLActionsPack.all)
        registry.register(JSONActionsPack.all)
        registry.register(MarkdownActionsPack.all)
        registry.register(CodeActionsPack.all)
        registry.register(TableActionsPack.all)
        registry.register(RichTextActionsPack.all)
        registry.register(FileActionsPack.all(store: store))

        // Image actions (Backlog #3)
        registry.register(ImageActionsPack.all)

        // Type Slowly (Backlog #7)
        registry.register(TypeSlowlyAction())

        // AI actions всегда регистрируются (Backlog #2): без ключа возвращают .failed
        let cfg = AIProviderConfig.load()
        aiProvider = AnthropicProvider(config: cfg)
        registry.aiProvider = aiProvider
        registry.register(DefaultAIActions.make(provider: aiProvider).map { $0 as ClipboardAction })
        // Build custom AI actions из persisted config (Backlog #8)
        registry.rebuildCustomAI()

        settingsController = SettingsWindowController(registry: registry, store: store)

        hudState = HudState()
        startEngine()
        installStatusItem()
        startAXMonitor()
    }

    // MARK: engine bootstrap

    private func startEngine() {
        let candidate = HotkeyEngineFactory.make(config: .default)
        candidate.delegate = self
        if candidate.start() {
            self.engine = candidate
            self.hudState.mode = candidate.hudMode
            self.hudState.engineLabel = candidate.kind.rawValue
            self.lastAXTrusted = AXIsProcessTrusted()
            return
        }
        if candidate.kind == .eventTap {
            let fallback = CarbonHotKeyEngine(config: .default)
            fallback.delegate = self
            if fallback.start() {
                self.engine = fallback
                self.hudState.mode = .summon
                self.hudState.engineLabel = fallback.kind.rawValue
                self.lastAXTrusted = false
                requestAccessibilityNicely()
                return
            }
        }
        NSLog("DrPaste: no engine could start.")
    }

    private func requestAccessibilityNicely() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: AX trust monitor

    private func startAXMonitor() {
        axTrustPollTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAXTrustChange() }
        }
        RunLoop.main.add(t, forMode: .common)
        self.axTrustPollTimer = t
    }

    private func checkAXTrustChange() {
        let now = AXIsProcessTrusted()
        guard now != lastAXTrusted else { return }
        lastAXTrusted = now
        if now && hudState.mode == .summon {
            offerRestartForGestureMode()
        }
    }

    private func offerRestartForGestureMode() {
        let alert = NSAlert()
        alert.messageText = "Advanced gesture mode is now available"
        alert.informativeText = "DrPaste can now use press-and-hold ⌥⌘V with release-to-paste. Restart the app to enable it."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn { restartApp() }
    }

    private func restartApp() {
        let exePath = Bundle.main.executablePath ?? Bundle.main.bundleURL.path
        let direct = Process()
        direct.executableURL = URL(fileURLWithPath: exePath)
        try? direct.run()
        NSApp.terminate(nil)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: status item (Backlog #5 template icon + #6 menu reorganization)

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = AppBrand.menuBarIcon
        }
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        let modeLabel = engine.hudMode == .gesture ? "Full Gesture Mode" : "Limited Mode"
        let header = NSMenuItem(title: "DrPaste — \(modeLabel)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if engine.hudMode == .summon {
            menu.addItem(withTitle: "Enable advanced gesture mode…",
                         action: #selector(menuOpenAccessibility), keyEquivalent: "")
            menu.addItem(.separator())
        }

        // Recent clipboard submenu
        let recentItem = NSMenuItem(title: "Recent clipboard", action: nil, keyEquivalent: "")
        recentMenu = NSMenu(title: "Recent")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "About DrPaste…", action: #selector(menuShowAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DrPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusMenu = menu
    }

    // MARK: NSMenuDelegate — dynamic Recent submenu

    func menuWillOpen(_ menu: NSMenu) {
        // Запоминаем frontmost ДО открытия меню — нужно для paste-to-frontmost.
        if savedFrontmostApp == nil {
            savedFrontmostApp = NSWorkspace.shared.frontmostApplication
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu { savedFrontmostApp = nil }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()

        // "Clear history" первым, визуальный separator-style.
        let clear = NSMenuItem(title: "──── Clear history ────",
                               action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !store.items.isEmpty
        recentMenu.addItem(clear)
        recentMenu.addItem(.separator())

        if store.items.isEmpty {
            let empty = NSMenuItem(title: "(history is empty)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }

        for (idx, item) in store.items.prefix(15).enumerated() {
            let mi = NSMenuItem(title: recentSnippet(item),
                                action: #selector(recentItemSelected(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = idx
            if let sym = NSImage(systemSymbolName: item.semantic.sfSymbol, accessibilityDescription: nil) {
                sym.size = NSSize(width: 14, height: 14)
                sym.isTemplate = true
                mi.image = sym
            }
            recentMenu.addItem(mi)
        }
    }

    private func recentSnippet(_ item: ClipboardItem) -> String {
        let text = item.previewText ?? item.semantic.displayName
        let oneline = text.replacingOccurrences(of: "\n", with: " ")
        return String(oneline.prefix(50))
    }

    // MARK: status menu actions

    @objc private func clearHistory() { store.clearAll() }

    @objc private func menuOpenAccessibility() { openAccessibilitySettings() }

    @objc private func menuOpenSettings() {
        // Backlog #8 — полное Settings окно с TabView и playground.
        settingsController?.show()
    }

    @objc private func menuShowAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppBrand.name,
            .applicationVersion: AppBrand.version,
            .credits: AppBrand.aboutCredits,
            .applicationIcon: AppBrand.nsIcon
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func recentItemSelected(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0, idx < store.items.count else { return }
        let item = store.items[idx]
        let savedApp = savedFrontmostApp
        savedFrontmostApp = nil

        PasteboardWriter.write(item, store: store)
        watcher.ignoreNextChange = true

        // paste-to-frontmost: активируем saved app + simulatePaste с задержкой
        guard let app = savedApp,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            SoundFeedback.play(.pasteSuccess)
            return
        }
        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if AXIsProcessTrusted() {
                PasteSimulator.simulatePaste()
                SoundFeedback.play(.pasteSuccess)
            } else {
                // Limited Mode: pasteboard write всё что можем
                SoundFeedback.play(.copySuccess)  // signal что в clipboard
            }
        }
    }

    // MARK: HotkeyEngineDelegate

    nonisolated func hotkeyEngineDidSummon(reason: SummonReason) {
        Task { @MainActor in
            self.currentSummonReason = reason
            if reason == .cutAndReplace {
                let frontApp = NSWorkspace.shared.frontmostApplication
                self.savedFrontmostApp = frontApp
                PasteSimulator.simulateCut()
                // Дать macOS обработать cut и watcher подхватить новый payload
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.watcher.forceTick()
                    self.openHUD()
                }
            } else {
                self.openHUD()
            }
        }
    }
    nonisolated func hotkeyEngineDidRelease() { Task { @MainActor in self.commitHUD() } }
    nonisolated func hotkeyEngineDidCancel() { Task { @MainActor in self.closeHUD() } }
    nonisolated func hotkeyEngineDidNavigate(_ direction: NavDirection) {
        Task { @MainActor in self.navigate(direction) }
    }
    nonisolated func hotkeyEngineDidRequestFontChange(_ change: FontChange) {
        Task { @MainActor in self.hudState.adjustFontScale(change) }
    }

    /// Backlog #9 + #10: Quick Copy через ⌥⌘C.
    /// Реальная детекция success/failure через pasteboard.changeCount diff.
    nonisolated func hotkeyEngineDidQuickCopy() {
        Task { @MainActor in
            let countBefore = NSPasteboard.general.changeCount
            PasteSimulator.simulateCopy()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let countAfter = NSPasteboard.general.changeCount
                if countAfter > countBefore {
                    SoundFeedback.play(.copySuccess)
                    self.flashStatusItem()
                } else {
                    SoundFeedback.play(.copyFailure)
                }
            }
        }
    }

    private func flashStatusItem() {
        guard let btn = statusItem.button else { return }
        let original = btn.image
        // Подсветка accent — простая визуальная подтверждение
        btn.appearsDisabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            btn.appearsDisabled = false
            btn.image = original
        }
    }

    // MARK: HUD lifecycle

    private func openHUD() {
        hudState.items = store.items
        hudState.itemIndex = 0
        hudState.actionIndex = 0
        recomputeActions()
        refreshPreview()
        showPanel()
        if engine.hudMode == .summon { installLocalKeyMonitor() }
    }

    private func commitHUD() {
        let outcome = hudState.outcome
        let savedApp = savedFrontmostApp
        savedFrontmostApp = nil
        closeHUD()

        guard let outcome = outcome else { return }

        switch outcome {
        case .preview(let item), .alternativeCommit(let item, .standardPaste):
            performStandardPaste(item, savedApp: savedApp)
        case .alternativeCommit(let item, .typeSlowly(let delay, let jitter)):
            performTypeSlowly(item, savedApp: savedApp, delay: delay, jitter: jitter)
        case .alternativeCommit(let item, .typeFast):
            performTypeSlowly(item, savedApp: savedApp, delay: 0.05, jitter: 0)
        case .failed(let original, _, _):
            // Backlog #2: на commit пишем original, играем failure звук
            performStandardPaste(original, savedApp: savedApp)
            SoundFeedback.play(.pasteFailure)
        case .sideEffect(_, let perform):
            perform()
            SoundFeedback.play(.pasteSuccess)
        }
    }

    private func performStandardPaste(_ item: ClipboardItem, savedApp: NSRunningApplication?) {
        PasteboardWriter.write(item, store: store)
        watcher.ignoreNextChange = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if AXIsProcessTrusted() {
                PasteSimulator.simulatePaste()
            }
            SoundFeedback.play(.pasteSuccess)
        }
    }

    private func performTypeSlowly(_ item: ClipboardItem, savedApp: NSRunningApplication?,
                                   delay: TimeInterval, jitter: Double) {
        guard AXIsProcessTrusted() else {
            SoundFeedback.play(.pasteFailure)
            return
        }
        let text = item.previewText ?? ""
        // Небольшая задержка чтобы HUD успел исчезнуть и focus вернулся
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            TypeSimulator.typeSlowly(text, baseDelay: delay, jitter: jitter)
        }
    }

    private func closeHUD() {
        removeLocalKeyMonitor()
        hudPanel?.orderOut(nil)
    }

    private func navigate(_ direction: NavDirection) {
        switch direction {
        case .up:
            if hudState.itemIndex > 0 {
                hudState.itemIndex -= 1; hudState.actionIndex = 0
                recomputeActions(); refreshPreview()
            }
        case .down:
            if hudState.itemIndex + 1 < hudState.items.count {
                hudState.itemIndex += 1; hudState.actionIndex = 0
                recomputeActions(); refreshPreview()
            }
        case .left:
            if hudState.actionIndex > 0 { hudState.actionIndex -= 1; refreshPreview() }
        case .right:
            if hudState.actionIndex + 1 < hudState.actions.count {
                hudState.actionIndex += 1; refreshPreview()
            }
        }
    }

    private func recomputeActions() {
        guard let item = hudState.currentItem else { hudState.actions = []; return }
        let ctx = ContextDetector.detect(item)
        hudState.actions = registry.applicable(for: item, context: ctx)
    }

    private func refreshPreview() {
        guard let item = hudState.currentItem,
              let action = hudState.currentAction else {
            hudState.outcome = nil
            return
        }
        previewToken &+= 1
        let myToken = previewToken
        let ctx = ContextDetector.detect(item)

        if action.isLocal {
            Task { @MainActor in
                let outcome = await action.apply(item: item, context: ctx)
                if myToken == self.previewToken {
                    self.hudState.outcome = outcome
                    self.hudState.isPreviewLoading = false
                }
            }
        } else {
            hudState.isPreviewLoading = true
            hudState.outcome = .preview(item)
            Task {
                let outcome = await action.apply(item: item, context: ctx)
                await MainActor.run {
                    if myToken == self.previewToken {
                        self.hudState.outcome = outcome
                        self.hudState.isPreviewLoading = false
                    }
                }
            }
        }
    }

    private func showPanel() {
        if hudPanel == nil {
            let view = HudView(
                state: hudState,
                onPick: { [weak self] itemIdx, actionIdx in
                    guard let self = self else { return }
                    self.hudState.itemIndex = itemIdx
                    self.hudState.actionIndex = actionIdx
                    self.refreshPreview()
                },
                onCommit: { [weak self] in self?.commitHUD() },
                onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
                onRecoveryAction: { [weak self] rec in self?.performRecovery(rec) }
            )
            let allowsKey = engine.hudMode == .summon
            let host = HudHostingView(rootView: view)
            let frame = NSRect(x: 0, y: 0, width: 720, height: allowsKey ? 440 : 400)
            let panel = HudPanel(contentRect: frame, allowsKey: allowsKey)
            panel.contentView = host
            hudPanel = panel
        }
        guard let panel = hudPanel else { return }
        centerOnActiveScreen(panel)
        if engine.hudMode == .summon {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func centerOnActiveScreen(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let s = screen else { return }
        let visible = s.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + 80
        )
        panel.setFrameOrigin(origin)
    }

    private func performRecovery(_ rec: RecoveryAction) {
        switch rec {
        case .openProvidersConfig:
            // Закрываем HUD и открываем Settings → AI tab
            closeHUD()
            settingsController?.show()
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .custom(_, let url):
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Limited Mode key monitor

    private func installLocalKeyMonitor() {
        removeLocalKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            let kc = Int(event.keyCode)
            let cmd = event.modifierFlags.contains(.command)
            switch kc {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.commitHUD(); return nil
            case kVK_Escape:
                self.closeHUD(); return nil
            case kVK_UpArrow:    self.navigate(.up);    return nil
            case kVK_DownArrow:  self.navigate(.down);  return nil
            case kVK_LeftArrow:  self.navigate(.left);  return nil
            case kVK_RightArrow: self.navigate(.right); return nil
            default: break
            }
            if cmd {
                switch kc {
                case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus:
                    self.hudState.adjustFontScale(.bigger); return nil
                case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
                    self.hudState.adjustFontScale(.smaller); return nil
                case kVK_ANSI_0, kVK_ANSI_Keypad0:
                    self.hudState.adjustFontScale(.reset); return nil
                default: break
                }
            }
            return event
        }
    }

    private func removeLocalKeyMonitor() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }
}

// MARK: - main

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
