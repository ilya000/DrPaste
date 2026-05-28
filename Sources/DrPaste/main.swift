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
final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyEngineDelegate, NSMenuDelegate,
                         ActionHotkeyManagerDelegate {

    var store: ClipboardStore!
    var watcher: ClipboardWatcher!
    var registry: ActionRegistry!
    // AI provider теперь резолвится через AIProviderRegistry.shared (multi-provider, Правка #4)

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

    // #2: Append Copy session tracking. Each ⌥⌘S press is "subsequent" only if
    // the immediately previous DrPaste hotkey was ⌥⌘S AND ≤5 min ago.
    private var lastAppendCopyTime: Date? = nil
    private enum LastDrPasteAction { case none, appendCopy, other }
    private var lastDrPasteAction: LastDrPasteAction = .none
    private let appendSessionTimeout: TimeInterval = 300  // 5 minutes

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("DrPaste: launch started")
        store = ClipboardStore()
        watcher = ClipboardWatcher(store: store)
        watcher.start()
        NSLog("DrPaste: store + watcher ready")

        registry = ActionRegistry()
        NSLog("DrPaste: registry init complete")

        // Content-aware action packs
        registry.register(TextActionsPack.all)
        registry.register(URLActionsPack.all)
        registry.register(JSONActionsPack.all)
        registry.register(MarkdownActionsPack.all)
        registry.register(CodeActionsPack.all)
        registry.register(TableActionsPack.all)
        registry.register(RichTextActionsPack.all)
        registry.register(FileActionsPack.all(store: store))
        registry.register(ImageActionsPack.all)
        registry.register(TypeSlowlyAction())
        NSLog("DrPaste: packs registered")

        // AI provider registry singleton init
        _ = AIProviderRegistry.shared
        NSLog("DrPaste: AIProviderRegistry ready")

        // Seed defaults (post-init to avoid didSet on partially-initialized state).
        registry.runFirstLaunchSeeds()
        NSLog("DrPaste: seed complete")

        registry.rebuildCustomAI()
        registry.rebuildCustomTransformations()
        NSLog("DrPaste: rebuild complete")

        // Per-action hotkeys
        ActionHotkeyManager.shared.registry = registry
        ActionHotkeyManager.shared.delegate = self
        ActionHotkeyManager.shared.install()
        ActionHotkeyManager.shared.reload()
        NSLog("DrPaste: hotkey manager ready")

        settingsController = SettingsWindowController(registry: registry, store: store)
        hudState = HudState()
        NSLog("DrPaste: state objects ready")

        startEngine()
        NSLog("DrPaste: engine started")

        installStatusItem()
        NSLog("DrPaste: status item installed")

        startAXMonitor()
        NSLog("DrPaste: AX monitor started")

        // Welcome window — auto-shown on first launch, suppressible via "Don't show again".
        WelcomeWindowController.shared.configure(registry: registry)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WelcomeWindowController.shared.showIfNeeded()
        }
        NSLog("DrPaste: launch complete")
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
        menu.addItem(withTitle: "Welcome / Hotkeys…", action: #selector(menuShowWelcome), keyEquivalent: "")
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
        AboutWindowController.shared.show()
    }

    @objc private func menuShowWelcome() {
        WelcomeWindowController.shared.show()
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
            self.markOtherDrPasteAction()
            self.currentSummonReason = reason
            if reason == .cutAndReplace {
                // Правка #16 слой 5: event-driven verification вместо fixed asyncAfter.
                // Polling до 250 ms ждём изменение pasteboard, дальше openHUD.
                // Если не дождались — silent fail, не зависаем в opening.
                let frontApp = NSWorkspace.shared.frontmostApplication
                self.savedFrontmostApp = frontApp
                let before = NSPasteboard.general.changeCount
                PasteSimulator.simulateCut()
                self.pollClipboardChangeThenOpenHUD(changeCountBefore: before)
            } else {
                self.openHUD()
            }
        }
    }

    /// Правка #16 слой 5 + 3: poll pasteboard для cut verification +
    /// watchdog таймер. Если cut не сработал — silent fail без HUD opening.
    @MainActor
    private func pollClipboardChangeThenOpenHUD(changeCountBefore: Int) {
        let start = Date()
        let deadline: TimeInterval = 0.25
        Task { @MainActor in
            while Date().timeIntervalSince(start) < deadline {
                try? await Task.sleep(nanoseconds: 20_000_000)  // 20 ms
                if NSPasteboard.general.changeCount > changeCountBefore {
                    self.watcher.forceTick()
                    self.openHUD()
                    return
                }
            }
            // Timeout — нет selection или app заблокировал cut
            SoundFeedback.play(.copyFailure)
            // Force reset hudIsActive в engine — мы туда уже его установили в summon
            if let tap = self.engine as? EventTapEngine { tap.resetHudActive() }
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

    /// Правка #14: Backspace в HUD → delete focused item.
    nonisolated func hotkeyEngineDidDeleteFocused() {
        Task { @MainActor in
            guard let item = self.hudState.currentItem else { return }
            let position = self.hudState.itemIndex
            self.store.remove(item.id)
            self.hudState.items = self.store.items
            SoundFeedback.play(.delete)
            if self.hudState.items.isEmpty {
                self.closeHUD()
                return
            }
            self.hudState.itemIndex = min(position, self.hudState.items.count - 1)
            self.hudState.actionIndex = 0
            self.recomputeActions()
            self.refreshPreview()
            self.updateContentMeta()
        }
    }

    /// Backlog #9 + #10: Quick Copy через ⌥⌘C.
    /// Реальная детекция success/failure через pasteboard.changeCount diff.
    // MARK: - Per-action hotkey direct trigger (0.6.0)

    /// Hotkey assigned to action was pressed. Without HUD: apply action to current
    /// clipboard content and paste result into frontmost app.
    func actionHotkeyDidFire(actionID: String) {
        markOtherDrPasteAction()
        guard let action = registry.actions.first(where: { $0.id == actionID }) else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        // Snapshot текущего pasteboard как ClipboardItem
        let pb = NSPasteboard.general
        let textValue = pb.string(forType: .string) ?? ""
        var item = ClipboardItem(
            id: UUID(),
            semantic: SemanticClassifier.classify(types: pb.types?.map(\.rawValue) ?? [],
                                                  pasteboard: pb),
            createdAt: Date(),
            representations: [:],
            typesOrdered: [],
            previewText: textValue,
            previewImageRel: nil,
            sourceBundleID: frontmost.bundleIdentifier,
            sourceAppName: frontmost.localizedName,
            sourceWindowTitle: nil,
            tags: []
        )
        // Re-build representations из pasteboard для lossless paste
        if let types = pb.types {
            for t in types {
                guard let data = pb.data(forType: t) else { continue }
                let rel = store.writeRawBlob(data, type: t.rawValue)
                item.representations[t.rawValue] = rel
                item.typesOrdered.append(t.rawValue)
            }
        }
        let ctx = ContextDetector.detect(item)

        Task { @MainActor in
            let outcome = await action.apply(item: item, context: ctx)
            switch outcome {
            case .preview(let result), .alternativeCommit(let result, _):
                self.performStandardPaste(result, savedApp: frontmost)
            case .sideEffect(_, let perform):
                perform()
                SoundFeedback.play(.pasteSuccess)
            case .failed(_, let reason, _):
                SoundFeedback.play(.pasteFailure)
                NSLog("DrPaste hotkey action failed: \(reason)")
            }
        }
    }

    /// ⌥⌘S — Sum/Append Copy with session-based reset (#2):
    /// • First press in a session (>5 min gap OR previous DrPaste action was not ⌥⌘S):
    ///   pushes current clipboard to history, clears it, captures selection as fresh start.
    /// • Subsequent presses in same session: append to accumulator with separator.
    /// Files: append URL list. Other types: text concatenation with \n.
    nonisolated func hotkeyEngineDidAppendCopy() {
        Task { @MainActor in
            let pb = NSPasteboard.general
            let separator = "\n"

            // Determine session state
            let isNewSession: Bool = {
                if self.lastDrPasteAction != .appendCopy { return true }
                if let last = self.lastAppendCopyTime,
                   Date().timeIntervalSince(last) > self.appendSessionTimeout { return true }
                return false
            }()

            if isNewSession {
                // Push existing clipboard to history (watcher will pick it up if changed)
                self.watcher.forceTick()
                pb.clearContents()
            }

            // Capture previous accumulator (only relevant for subsequent presses)
            let previousText = isNewSession ? nil : pb.string(forType: .string)
            let previousFiles = isNewSession ? nil :
                pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]

            let countBefore = pb.changeCount
            PasteSimulator.simulateCopy()

            // Poll pasteboard change up to 250ms
            let start = Date()
            while Date().timeIntervalSince(start) < 0.25 {
                try? await Task.sleep(nanoseconds: 20_000_000)
                if pb.changeCount > countBefore { break }
            }
            self.lastAppendCopyTime = Date()
            self.lastDrPasteAction = .appendCopy

            if pb.changeCount == countBefore {
                SoundFeedback.play(.copyFailure)
                return
            }

            // For new session — clipboard already holds the just-copied selection. Done.
            if isNewSession {
                self.watcher.ignoreNextChange = false
                self.watcher.forceTick()
                SoundFeedback.play(.copySuccess)
                self.flashStatusItem()
                return
            }

            // Subsequent press — merge previous with newly captured
            let newText = pb.string(forType: .string)
            let newFiles = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]

            if let prev = previousText, let new = newText, !prev.isEmpty {
                let combined = prev + separator + new
                pb.clearContents()
                pb.setString(combined, forType: .string)
                self.watcher.ignoreNextChange = false
                self.watcher.forceTick()
                SoundFeedback.play(.copySuccess)
                self.flashStatusItem()
                return
            }
            if let prev = previousFiles, let new = newFiles, !prev.isEmpty {
                let combined = prev + new
                pb.clearContents()
                pb.writeObjects(combined as [NSPasteboardWriting])
                self.watcher.ignoreNextChange = false
                self.watcher.forceTick()
                SoundFeedback.play(.copySuccess)
                self.flashStatusItem()
                return
            }
            SoundFeedback.play(.copySuccess)
            self.flashStatusItem()
        }
    }

    /// Mark that some DrPaste hotkey other than ⌥⌘S was used.
    /// Causes next ⌥⌘S to be treated as a new session (#2).
    @MainActor
    private func markOtherDrPasteAction() {
        lastDrPasteAction = .other
        lastAppendCopyTime = Date()
    }

    nonisolated func hotkeyEngineDidQuickCopy() {
        Task { @MainActor in
            self.markOtherDrPasteAction()
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
        // Cut & Replace UX: если cursorOnSecondOnCut включён и есть >1 item,
        // курсор стартует на втором (skip just-cut). Default = false (native).
        let skipCutItem = currentSummonReason == .cutAndReplace
            && UserDefaults.standard.bool(forKey: "drpaste.hud.cursorOnSecondOnCut")
            && hudState.items.count > 1
        hudState.itemIndex = skipCutItem ? 1 : 0
        hudState.actionIndex = 0
        hudState.contentMeta = nil
        recomputeActions()
        refreshPreview()
        updateContentMeta()
        showPanel()
        if engine.hudMode == .summon { installLocalKeyMonitor() }
    }

    /// Правка #15: вычислить content meta для focused item (async, lazy, cached).
    private func updateContentMeta() {
        guard let item = hudState.currentItem else {
            hudState.contentMeta = nil
            return
        }
        hudState.contentMeta = nil   // placeholder "…"
        let itemID = item.id
        Task { [weak self] in
            // Background compute через detached child task, потом await обратно на MainActor.
            // Это избегает Swift 6 warning про concurrent var capture self в MainActor.run.
            let meta = await Task.detached(priority: .userInitiated) {
                ContentMetaCache.shared.computeSync(for: item)
            }.value
            guard let self = self else { return }
            if self.hudState.currentItem?.id == itemID {
                self.hudState.contentMeta = meta
            }
        }
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
                recomputeActions(); refreshPreview(); updateContentMeta()
            }
        case .down:
            if hudState.itemIndex + 1 < hudState.items.count {
                hudState.itemIndex += 1; hudState.actionIndex = 0
                recomputeActions(); refreshPreview(); updateContentMeta()
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
            // Provider для custom titles (правка #6 lite)
            hudState.actionTitleProvider = { [weak self] (id, defaultTitle) in
                self?.registry.displayTitle(forActionID: id, defaultTitle: defaultTitle) ?? defaultTitle
            }
            let view = HudView(
                state: hudState,
                onPick: { [weak self] itemIdx, actionIdx in
                    guard let self = self else { return }
                    let itemChanged = itemIdx != self.hudState.itemIndex
                    self.hudState.itemIndex = itemIdx
                    self.hudState.actionIndex = actionIdx
                    self.refreshPreview()
                    if itemChanged { self.updateContentMeta() }
                },
                onCommit: { [weak self] in self?.commitHUD() },
                onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
                onRecoveryAction: { [weak self] rec in self?.performRecovery(rec) },
                onClose: { [weak self] in self?.closeHUD() }   // Правка #15: close button
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
        // Правка #16 слой 4: verify visibility, retry если не успел
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if let p = self.hudPanel, !p.isVisible {
                NSLog("DrPaste: HUD did not become visible, retry")
                if self.engine.hudMode == .summon {
                    p.makeKeyAndOrderFront(nil)
                } else {
                    p.orderFrontRegardless()
                }
            }
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
            case kVK_Delete:                       // Правка #14: Backspace в Limited Mode
                self.hotkeyEngineDidDeleteFocused(); return nil
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
