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
    // AI provider is resolved through AIProviderRegistry.shared (multi-provider).

    var engine: HotkeyEngine!
    var bigHUDPanel: BigHUDPanel?
    var bigHUDState: BigHUDState!
    var statusItem: NSStatusItem!
    var settingsController: SettingsWindowController?

    private var statusMenu: NSMenu!
    private var recentMenu: NSMenu!
    private var previewToken: Int = 0
    private var axTrustPollTimer: Timer?
    /// Repeating timer that ticks `bigHUDState.aiElapsed` while an AI request is
    /// in flight. Owned by AppDelegate so it can be invalidated when the HUD
    /// closes or the user navigates between actions before the response arrives.
    private var aiTickTimer: Timer?
    /// Outstanding AI streaming task — kept so we can explicitly cancel it
    /// when the user navigates to a different action mid-stream or closes
    /// the HUD. Cancellation propagates to the underlying URLSession via
    /// the provider's `continuation.onTermination` hook, closing the
    /// connection promptly and stopping token usage from running away.
    private var aiStreamingTask: Task<Void, Never>?
    /// Outstanding LOCAL preview task (image filters, transformations,
    /// OCR / QR — anything where `action.isLocal == true`). Tracked so
    /// fast navigation between actions can cancel the previous task
    /// instead of letting heavy CPU work pile up on the background
    /// queue. Previously local previews were fire-and-forget; running
    /// Grayscale on a 4K image then immediately arrowing to Rotate
    /// queued two full CIFilter renders, doubling the latency to
    /// the user-visible result.
    private var localPreviewTask: Task<Void, Never>?
    /// Outstanding direct-trigger action task (the Task spawned by
    /// `actionHotkeyDidFire` to run a per-action hotkey's ⌘C →
    /// transform → paste pipeline). Tracked so opening the BigHUD
    /// while a previous direct-trigger AI action is still in flight
    /// can cancel it — otherwise the AI eventually completes and
    /// pastes into whatever the user was looking at when they fired
    /// the hotkey, surprising them after they've already moved on.
    /// Also lets us hide the MiniHUD when BigHUD takes over the
    /// screen, eliminating the visual overlap user-reported as
    /// "both MiniHUD and BigHUD showed at once".
    private var actionHotkeyTask: Task<Void, Never>?

    /// Outstanding inner Task spawned by `openBigHUDFocusedOnAction` to
    /// run its selection-first ⌘C + BigHUD open. Tracked so a second
    /// hold-preview fire (user releases ⌥⌘ then quickly re-holds, or
    /// any other rapid-fire sequence) cancels the prior in-flight open
    /// instead of stacking two BigHUDs / two simulateCopy polls. Same
    /// reasoning as `actionHotkeyTask` — keep at most one of each
    /// surface-opening task in flight.
    private var bigHUDOpenTask: Task<Void, Never>?

    /// Generation counter for `showBigHUD`'s 80 ms visibility retry.
    /// Incremented on every successful show AND on every teardown
    /// (`closeBigHUD`, `deferPasteAfterAILoad`). A retry block
    /// captures the current value at schedule time and bails when
    /// the captured value no longer matches — prevents a stale retry
    /// from resurrecting an orderOut'd BigHUD on top of a deferred-
    /// paste MiniHUD. Wrap-around at 2^64 is a non-issue in practice.
    private var bigHUDShowSession: UInt64 = 0

    /// Deferred-paste target. Set by `commitBigHUD()` when the user releases
    /// ⌥⌘ while an AI action is still loading: instead of pasting the
    /// placeholder (the un-transformed original clipboard, which is what
    /// `bigHUDState.outcome` holds until the stream completes), we keep the
    /// streaming task alive, take down HUD chrome, promote ProgressHUD as
    /// the in-flight indicator, and let the task's completion handler do
    /// the paste. Result: a single consistent rule — "press hotkey, the
    /// AI result pastes when ready, regardless of how long you held ⌥⌘".
    private var pendingDeferredPasteApp: NSRunningApplication?

    /// #A11 — screen-region capture controller. Owns the cursor (C2) and
    /// selection (C1) overlay panels. Instantiated lazily on first arm
    /// because most launches never trigger it.
    private var regionCapture: ScreenRegionCaptureController?
    /// Frontmost app snapshot taken at region-capture arm time, carried
    /// through to the BigHUD as the savedFrontmostApp so the eventual
    /// paste lands in the right window (the user may click elsewhere
    /// during the drag-vs-capture interval).
    private var regionCaptureSourceApp: NSRunningApplication?
    private var lastAXTrusted: Bool = false
    private var localKeyMonitor: Any?
    private var savedFrontmostApp: NSRunningApplication?
    private var currentSummonReason: SummonReason = .paste

    /// Set by `commitBigHUDKeepingOpen()` to suppress the duplicate
    /// paste that `hotkeyEngineDidRelease` (Gesture Mode ⌥⌘ release)
    /// would otherwise fire — ⌥⌘⏎ already pasted the row, the
    /// release should only tear the HUD down. Reset after consumption.
    private var pasteAndKeepDidFire: Bool = false

    // #2: Append Copy session tracking. Each ⌥⌘S press is "subsequent" only if
    // the immediately previous DrPaste hotkey was ⌥⌘S AND ≤5 min ago.
    private var lastAppendCopyTime: Date? = nil
    private enum LastDrPasteAction { case none, appendCopy, other }
    private var lastDrPasteAction: LastDrPasteAction = .none
    /// Session inactivity window for ⌥⌘S Append Copy. After this
    /// many seconds without an ⌥⌘S press, the NEXT press is
    /// treated as a fresh session — flush whatever's in the
    /// clipboard to history and ⌘C the user's current selection
    /// as the new seed. Applies uniformly regardless of session
    /// type (files-strict OR rich-text accumulator).
    private let appendSessionTimeout: TimeInterval = 120

    /// Status-item overlay: small red dot drawn in the corner of
    /// the menu-bar icon while an Append Copy session is alive.
    /// Lets the user see "I'm in a merge sequence" at a glance,
    /// so a stale session 90 seconds in doesn't surprise them.
    /// Hidden by default; toggled via `armAppendSessionIndicator`
    /// / `disarmAppendSessionIndicator`.
    private var sessionDotView: NSView?
    /// Auto-expiry timer that hides the dot after the same window
    /// the session timeout uses (`appendSessionTimeout`). Re-fires
    /// on every ⌥⌘S, so the dot stays lit while the user keeps
    /// appending and disappears `appendSessionTimeout` seconds
    /// after the LAST append.
    private var appendSessionTimer: Timer?

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("DrPaste: launch started")
        AppBrand.installApplicationIcon()
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
        registry.register(CSVTableActionsPack.all)   // #A15
        registry.register(RichTextActionsPack.all)
        registry.register(FileActionsPack.all(store: store))
        registry.register(ImageActionsPack.all)
        // Note: AI image styles (Pencil sketch / Watercolor / Cartoon) are NOT
        // registered statically here — they're seeded as user.* CustomAIDescriptor
        // entries via DefaultAISeed.defaults() and materialised by
        // ActionRegistry.rebuildCustomAI when `kind == .image`. That puts them on
        // the same Settings → Actions → AI editing surface as text AI actions
        // (Translate, Fix grammar, etc.) so the user can edit the prompt, switch
        // provider, rename, or clone them into their own styles.
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

        // GC orphan hotkeys — drop bindings whose action no longer exists (deleted
        // descriptor, removed action pack, factory ID migration). Must run after
        // all packs are registered and custom descriptors rebuilt.
        registry.pruneOrphanedActionHotkeys()
        NSLog("DrPaste: orphan hotkey GC complete")

        // Per-action hotkeys (Carbon side — system-wide hotkey registration).
        ActionHotkeyManager.shared.registry = registry
        ActionHotkeyManager.shared.delegate = self
        ActionHotkeyManager.shared.install()
        ActionHotkeyManager.shared.reload()
        NSLog("DrPaste: hotkey manager ready")

        settingsController = SettingsWindowController(registry: registry, store: store)
        bigHUDState = BigHUDState()
        NSLog("DrPaste: state objects ready")

        startEngine()
        NSLog("DrPaste: engine started")

        // Push the ⌥⌘<letter> hold-preview map to the EventTap engine.
        // CRITICAL: must run AFTER startEngine() — `reloadHoldPreviewMap`
        // guards on `engine as? EventTapEngine` and bails out silently
        // when engine is nil. If we call it earlier, the EventTap's
        // holdPreviewActionHotkeys map stays empty, and the armed-state
        // keyDown handler then swallows every per-action hotkey letter
        // because it can't recognise them. That bug made user hotkeys
        // appear to "not work" whenever the arm grace fired before the
        // letter (i.e. on any tap > 400 ms).
        reloadHoldPreviewMap()

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
            self.bigHUDState.mode = candidate.bigHUDMode
            self.bigHUDState.engineLabel = candidate.kind.rawValue
            self.lastAXTrusted = AXIsProcessTrusted()
            return
        }
        if candidate.kind == .eventTap {
            let fallback = CarbonHotKeyEngine(config: .default)
            fallback.delegate = self
            if fallback.start() {
                self.engine = fallback
                self.bigHUDState.mode = .summon
                self.bigHUDState.engineLabel = fallback.kind.rawValue
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
        if now && bigHUDState.mode == .summon {
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
        // Use the app icon instead of the default folder — this is a DrPaste
        // feature announcement, not a filesystem operation.
        alert.icon = AppBrand.nsIcon
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
            b.toolTip = "DrPaste — clipboard history"
        }
        rebuildStatusMenu()
    }

    /// Sync the status-bar tooltip with the current accumulator state.
    /// The colored dot on the icon signals "session active" visually;
    /// the tooltip spells out *which* session is active and *what* the
    /// next ⌥⌘S will do. Users hovering the menu-bar icon for a beat
    /// get an explicit explanation without having to dig into HELP.md.
    @MainActor
    private func updateStatusTooltip(appendActive: Bool, filesTrack: Bool) {
        guard let b = statusItem?.button else { return }
        if appendActive {
            if filesTrack {
                b.toolTip = "Append Copy: files accumulator active (cyan). "
                          + "Select more files and press ⌥⌘S to add."
            } else {
                b.toolTip = "Append Copy: rich-text accumulator active (red). "
                          + "Press ⌥⌘S to add more, ⌥⌘V to paste."
            }
        } else {
            b.toolTip = "DrPaste — clipboard history"
        }
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        let modeLabel = engine.bigHUDMode == .gesture ? "Full Gesture Mode" : "Limited Mode"
        let header = NSMenuItem(title: "DrPaste — \(modeLabel)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if engine.bigHUDMode == .summon {
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
        // Remember the frontmost app BEFORE the menu opens — needed for paste-to-frontmost.
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

        // "Clear history" first, styled like a visual separator.
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
        // Open the full Settings window (TabView + playground).
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

        // paste-to-frontmost: activate the saved app and simulate paste after a short delay.
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
                // Limited Mode: best-effort pasteboard write.
                SoundFeedback.play(.copySuccess)  // signal that the content reached the clipboard
            }
        }
    }

    // MARK: HotkeyEngineDelegate

    nonisolated func hotkeyEngineDidSummon(reason: SummonReason) {
        Task { @MainActor in
            self.markOtherDrPasteAction()
            self.currentSummonReason = reason
            if reason == .cutAndReplace {
                // Event-driven verification instead of a fixed asyncAfter:
                // poll the pasteboard for up to 250 ms waiting for a change,
                // then open the HUD. If nothing changed, fail silently rather
                // than getting stuck in the opening state.
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

    /// Polls the pasteboard to verify the cut, with a watchdog deadline. If
    /// the cut did not take effect, fail silently without opening the HUD.
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
            // Timeout — either no selection, or the app blocked the cut.
            SoundFeedback.play(.copyFailure)
            // Force-reset bigHUDIsActive in the engine since summon set it earlier.
            if let tap = self.engine as? EventTapEngine { tap.resetHudActive() }
        }
    }

    nonisolated func hotkeyEngineDidRelease() {
        Task { @MainActor in
            // Gesture Mode: ⌥⌘ release normally commits + closes. But
            // if the user just fired ⌥⌘⏎ (paste-and-keep), the paste
            // already happened — release should only close, not paste
            // again. Otherwise the row gets pasted twice (once from
            // ⌥⌘⏎, once from the release).
            if self.pasteAndKeepDidFire {
                self.pasteAndKeepDidFire = false
                self.savedFrontmostApp = nil
                self.closeBigHUD()
                return
            }
            self.commitBigHUD()
        }
    }
    nonisolated func hotkeyEngineDidCancel() { Task { @MainActor in self.closeBigHUD() } }
    nonisolated func hotkeyEngineDidNavigate(_ direction: NavDirection) {
        Task { @MainActor in
            // Re-arm release-paste: the paste-and-keep latch only
            // suppresses the IMMEDIATE next ⌥⌘ release after ⌥⌘⏎,
            // covering the "I already pasted via Enter" case. Once
            // the user navigates to a different item or action with
            // arrows, the intent flips back to "I want the new
            // focused row pasted on release" — so we clear the
            // latch and let the release path do its job.
            self.pasteAndKeepDidFire = false
            self.navigate(direction)
        }
    }
    nonisolated func hotkeyEngineDidRequestFontChange(_ change: FontChange) {
        Task { @MainActor in self.bigHUDState.adjustFontScale(change) }
    }

    /// ⌥⌘S inside the HUD — drive the "walking" clip accumulator.
    ///
    ///   • First press:   the focused clip becomes the carrier (anchor) and
    ///                    changes color. Nothing else moves.
    ///   • Press on the same green anchor again: TOGGLE OFF — drops the
    ///                    whole accumulator (consumed rows reappear in the
    ///                    list, preview returns to the focused clip's
    ///                    normal content). Symmetric on/off so a user who
    ///                    started the merge by mistake can cancel with the
    ///                    same key, no Esc needed.
    ///   • Subsequent press on a *different* clip: the previous carrier is
    ///                    folded into `consumed` (disappears from the list),
    ///                    and the newly focused clip becomes the new carrier
    ///                    showing the merged text right in its row.
    ///
    /// Navigation between presses (↑/↓) does NOT clear the accumulator —
    /// only HUD close / cancel / commit / toggle-off do.
    nonisolated func hotkeyEngineDidRequestHUDAccumulate() {
        Task { @MainActor in self.extendAccumulator() }
    }

    @MainActor
    private func extendAccumulator() {
        guard !bigHUDState.items.isEmpty else { return }
        let focused = bigHUDState.itemIndex
        guard focused >= 0, focused < bigHUDState.items.count else { return }

        // First press — start carrier on the focused item, no merge yet.
        // We pull the richest representation we can from the item
        // (RTFD → RTF → HTML → image attachment → plain text), not
        // its `previewText`, so subsequent appends preserve rich
        // formatting and inline images.
        guard var acc = bigHUDState.accumulator else {
            let seed = AppendAccumulator.attributedString(from: bigHUDState.items[focused])
            bigHUDState.accumulator = BigHUDClipAccumulator(
                consumed: [],
                anchorIndex: focused,
                attr: seed
            )
            bigHUDState.outcome = .preview(accumulatorItem(attr: seed))
            return
        }

        // Same anchor — toggle the accumulator off. Drops the entire merge
        // state so the HUD returns to normal mode: consumed rows become
        // visible again, green highlight disappears, preview reverts to the
        // focused clip's standard content.
        if acc.anchorIndex == focused {
            bigHUDState.accumulator = nil
            refreshPreview()
            updateContentMeta()
            return
        }
        // Defensive: focused row should never be consumed (it's hidden), but
        // guard anyway to keep the model consistent.
        if acc.consumed.contains(focused) { return }

        // Fold the previous carrier into consumed, absorb the focused
        // clip's full rich content into the merge, and adopt the
        // focused row as the new carrier. AppendAccumulator.append
        // handles the newline separator and attribute preservation.
        let appendedAttr = AppendAccumulator.attributedString(from: bigHUDState.items[focused])
        acc.consumed.insert(acc.anchorIndex)
        acc.attr = AppendAccumulator.append(appendedAttr, to: acc.attr)
        acc.anchorIndex = focused
        bigHUDState.accumulator = acc
        bigHUDState.outcome = .preview(accumulatorItem(attr: acc.attr))
    }

    /// ⌥⌘C inside the HUD — promote the current action preview into a
    /// new history clip at the TOP of history (where a real Copy would
    /// land) AND copy it back to the system pasteboard, then refocus
    /// the HUD onto the new clip. Semantically "take what I'm
    /// looking at back into the clipboard so I can keep working on
    /// it". Previously this chord was ⌥⌘Space and inserted above
    /// the focused row — that placement was technically correct but
    /// semantically wrong (a Copy belongs at top of history) and the
    /// ⌥⌘Space chord didn't read as "copy" to anyone.
    nonisolated func hotkeyEngineDidRequestPromotePreview() {
        Task { @MainActor in self.promotePreviewToHistory() }
    }

    /// EventTap/Monitor engines route ⌥⌘⏎ here when the HUD is
    /// active. We can't rely on the local NSEvent monitor for this
    /// chord because EventTapEngine sits in front of the runloop's
    /// event distribution and swallows every keyDown while the HUD
    /// is up — Return would never make it to the monitor without
    /// this explicit callback.
    nonisolated func hotkeyEngineDidRequestPasteAndKeep() {
        Task { @MainActor in self.commitBigHUDKeepingOpen() }
    }

    @MainActor
    private func promotePreviewToHistory() {
        guard !bigHUDState.items.isEmpty else { return }
        // Async (AI) actions in flight: their outcome is a stale placeholder
        // — skip rather than promote the unfinished content. Single failure
        // beep so the user knows the press was registered but the AI is
        // still working.
        if bigHUDState.isPreviewLoading {
            SoundFeedback.play(.copyFailure)
            return
        }
        // Only .preview is meaningful to promote. For .failed / .sideEffect
        // / .alternativeCommit / nil, silently no-op — these aren't usable
        // content to chain further actions on, and a failure beep would feel
        // noisy when the user is just exploring actions.
        guard let outcome = bigHUDState.outcome,
              case .preview(let previewItem) = outcome else {
            return
        }
        // Re-stamp with a fresh UUID and createdAt so duplicates in history
        // remain individually addressable and ordered. The promoted clip
        // ALWAYS lands at index 0 — top of history — to match the
        // semantics of "this is a fresh copy, just like ⌘C would
        // produce" rather than "an extra row threaded above where I
        // happened to be standing".
        let promoted = ClipboardItem(
            id: UUID(),
            semantic: previewItem.semantic,
            createdAt: Date(),
            representations: previewItem.representations,
            typesOrdered: previewItem.typesOrdered,
            previewText: previewItem.previewText,
            previewImageRel: previewItem.previewImageRel,
            originalImageWidth: previewItem.originalImageWidth,
            originalImageHeight: previewItem.originalImageHeight,
            originalImageFileSize: previewItem.originalImageFileSize,
            imageFormat: previewItem.imageFormat,
            sourceBundleID: previewItem.sourceBundleID,
            sourceAppName: "DrPaste · copied from preview",
            sourceWindowTitle: previewItem.sourceWindowTitle,
            tags: previewItem.tags
        )
        store.insertSnapshot(promoted, at: 0)
        // Also write the promoted item to the system pasteboard so
        // it behaves like a real Copy — the user can immediately
        // ⌘V it into any app outside DrPaste, not just paste it
        // back through the HUD. `ignoreNextChange` prevents the
        // pasteboard watcher from observing this synthetic write
        // and inserting ANOTHER copy of the same content right
        // after the one we just added.
        watcher.ignoreNextChange = true
        PasteboardWriter.write(promoted, store: store)
        bigHUDState.items = store.items
        // Refocus on the new top-of-history clip so the user
        // immediately sees what they just "copied" and can chain
        // further actions on it without arrow-key navigation.
        bigHUDState.itemIndex = 0
        bigHUDState.actionIndex = 0
        // Promote breaks the merge model — any in-flight accumulator must
        // be dropped because its indices are now off by one.
        bigHUDState.accumulator = nil
        recomputeActions()
        refreshPreview()
        updateContentMeta()
        SoundFeedback.play(.copySuccess)
    }

    /// Wraps an accumulated text blob in a temporary ClipboardItem so the
    /// existing preview-rendering machinery (which expects a ClipboardItem)
    /// can render it without special-casing. Item is never written to history
    /// or store — purely transient for the preview pane.
    /// Wrap the accumulator's NSAttributedString in a transient
    /// ClipboardItem so the existing preview / commit pipeline
    /// (which expects a `ClipboardItem`) can render and paste it
    /// without special-casing.
    ///
    /// Strategy: serialize the attributed string into
    /// `com.apple.flat-rtfd`, `public.rtf`, `public.html` and
    /// `public.utf8-plain-text` blobs in the store's blob
    /// directory, populate `representations` / `typesOrdered`
    /// accordingly, and tag the semantic kind as `.richText`
    /// (or `.text` if the content is plain). `PasteboardWriter`
    /// will then push every representation onto the pasteboard
    /// on commit, so apps that understand RTFD (Mail, Notes,
    /// Pages) get the inline images while plain-text-only targets
    /// (Terminal, Slack) fall back to text.
    @MainActor
    private func accumulatorItem(attr: NSAttributedString) -> ClipboardItem {
        var reps: [String: String] = [:]
        var ordered: [String] = []
        let range = NSRange(location: 0, length: attr.length)
        // RTFD — preserves attachments (inline images).
        if let rtfd = attr.rtfd(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]) {
            let rel = store.writeRawBlob(rtfd, type: "com.apple.flat-rtfd")
            reps["com.apple.flat-rtfd"] = rel
            ordered.append("com.apple.flat-rtfd")
        }
        // RTF — formatting only, no attachments.
        if let rtf = attr.rtf(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf
        ]) {
            let rel = store.writeRawBlob(rtf, type: "public.rtf")
            reps["public.rtf"] = rel
            ordered.append("public.rtf")
        }
        // HTML — best-effort for web-app targets.
        if let html = try? attr.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.html
        ]) {
            let rel = store.writeRawBlob(html, type: "public.html")
            reps["public.html"] = rel
            ordered.append("public.html")
        }
        // Plain text — last-resort fallback. Strip ￼ attachment
        // placeholders so plain-text targets don't see garbage chars.
        let plain = attr.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        if let data = plain.data(using: .utf8) {
            let rel = store.writeRawBlob(data, type: "public.utf8-plain-text")
            reps["public.utf8-plain-text"] = rel
            ordered.append("public.utf8-plain-text")
        }
        // Semantic: richText if anything beyond plain text made it
        // through (RTFD/RTF/HTML), otherwise text. Used by the HUD
        // preview's per-semantic renderer to pick the right view.
        let semantic: SemanticKind = (reps["com.apple.flat-rtfd"] != nil
                                       || reps["public.rtf"] != nil
                                       || reps["public.html"] != nil)
            ? .richText : .text
        return ClipboardItem(
            id: UUID(),
            semantic: semantic,
            createdAt: Date(),
            representations: reps,
            typesOrdered: ordered,
            previewText: plain.isEmpty ? nil : plain,
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: "DrPaste · accumulator",
            sourceWindowTitle: nil,
            tags: []
        )
    }

    /// Backspace in the HUD deletes the focused item. Has two extra
    /// responsibilities when an accumulator is active:
    ///   1. Shift `accumulator.consumed` and `accumulator.anchorIndex` to
    ///      match the new (shrunk) items array. Without this every
    ///      deletion at or below a consumed/anchor index silently corrupts
    ///      the merge — the indices stay numeric but point to the wrong
    ///      rows, so the wrong items hide/highlight on the next tick.
    ///   2. After picking the next focus position, skip past any consumed
    ///      rows so the cursor never lands on something invisible.
    nonisolated func hotkeyEngineDidDeleteFocused() {
        Task { @MainActor in
            // Delete moves focus to a different row — same reasoning
            // as navigate: clear the paste-and-keep latch so the
            // next ⌥⌘ release pastes the newly-focused item.
            self.pasteAndKeepDidFire = false
            guard let item = self.bigHUDState.currentItem else { return }
            let position = self.bigHUDState.itemIndex
            self.store.remove(item.id)
            self.adjustAccumulatorForDeletion(at: position)
            self.bigHUDState.items = self.store.items
            SoundFeedback.play(.delete)
            if self.bigHUDState.items.isEmpty {
                self.closeBigHUD()
                return
            }
            // Pick the next focus position. Prefer the row that visually
            // slides up to fill the deleted slot; fall back to the previous
            // row if forward is past end. Skip consumed rows in either
            // direction so the cursor never lands on something invisible.
            let consumed = self.bigHUDState.accumulator?.consumed ?? []
            var target = min(position, self.bigHUDState.items.count - 1)
            while target < self.bigHUDState.items.count && consumed.contains(target) {
                target += 1
            }
            if target >= self.bigHUDState.items.count {
                target = min(position, self.bigHUDState.items.count - 1)
                while target > 0 && consumed.contains(target) {
                    target -= 1
                }
            }
            self.bigHUDState.itemIndex = max(0, target)
            self.bigHUDState.actionIndex = 0
            self.recomputeActions()
            self.refreshPreview()
            self.updateContentMeta()
        }
    }

    /// Shifts `accumulator.consumed` and `accumulator.anchorIndex` to keep
    /// pointing at the same logical clips after one item has been removed
    /// from `store.items`. Dropping the accumulator entirely is the only
    /// safe option when the anchor itself was the deleted item — the
    /// carrier is gone, the merged text would no longer match a visible
    /// row, and there's no clean way to "re-anchor" it.
    @MainActor
    private func adjustAccumulatorForDeletion(at deletedIdx: Int) {
        guard var acc = self.bigHUDState.accumulator else { return }
        if acc.anchorIndex == deletedIdx {
            self.bigHUDState.accumulator = nil
            return
        }
        var newConsumed = Set<Int>()
        for ci in acc.consumed {
            if ci == deletedIdx { continue }
            newConsumed.insert(ci > deletedIdx ? ci - 1 : ci)
        }
        acc.consumed = newConsumed
        if acc.anchorIndex > deletedIdx {
            acc.anchorIndex -= 1
        }
        self.bigHUDState.accumulator = acc
    }

    /// Quick Copy via ⌥⌘C. Success/failure is detected by diffing pasteboard.changeCount.
    // MARK: - Per-action hotkey direct trigger

    /// Hotkey assigned to action was pressed. Without HUD: apply action to current
    /// clipboard content and paste result into frontmost app.
    /// Shows a transient progress mini-window for slow actions (AI calls, image transforms).
    func actionHotkeyDidFire(actionID: String) {
        markOtherDrPasteAction()
        guard let action = registry.actions.first(where: { $0.id == actionID }) else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        // If a previous direct-trigger action is still in flight (slow
        // AI, big image transform), cancel it before kicking off a new
        // one. Without this, two parallel actions both eventually call
        // performStandardPaste, the second overwriting the first in
        // the target app and possibly inside a context the user
        // wasn't expecting any more.
        actionHotkeyTask?.cancel()
        actionHotkeyTask = nil

        // Show progress HUD immediately — actions like AI calls or image
        // transforms may take a noticeable time. For AI actions also pass the
        // AIInflight descriptor so the mini-window can surface provider · model
        // · elapsed seconds, matching the main HUD preview pane treatment.
        let actionTitle = registry.displayTitle(forActionID: action.id, defaultTitle: action.title)
        let aiInflight = makeAIInflight(for: action)
        // Wire the MiniHUD's X button to cancel the in-flight task.
        // Without this the user has no escape hatch from a hung AI
        // call (provider takes forever, network stuck, etc.) — they
        // were stuck staring at a spinner with no way out short of
        // force-quitting DrPaste. Cancellation cascades into the
        // streaming task via Task.cancel(), which tears down the
        // URLSession bytes stream through onTermination.
        let hudToken = MiniHUDController.shared.show(
            label: actionTitle,
            inflight: aiInflight,
            onCancel: { [weak self] in
                self?.actionHotkeyTask?.cancel()
                self?.actionHotkeyTask = nil
            }
        )

        // Selection-first semantics — the whole point of a per-action
        // hotkey is "do X to what I'm looking at". Operating on stale
        // clipboard content is rarely what the user means. Issue ⌘C,
        // wait for the pasteboard to refresh, run the action on
        // whatever was selected. If nothing changes (no selection),
        // fail loudly — better than silently applying the
        // transformation to whatever old thing happened to be in pb.
        //
        // `hudToken` captured at show-time lets a cancelled branch take
        // its own MiniHUD down without accidentally hiding a later
        // show() (rapid-fire same-hotkey case where task N+1 replaced
        // task N's MiniHUD before task N's cancellation point ran).
        actionHotkeyTask = Task { @MainActor in
            // Watchdog — auto-cancel the whole task after 90 s.
            // Some providers/models leak the HTTP stream past
            // `message_stop` (server forgets to FIN; or sends
            // keep-alive pings forever) and our 15 s idle timeout
            // never trips because each ping ticks the byte clock.
            //
            // MUST be `Task.detached`, NOT `Task { @MainActor ... }`.
            // The parent task here is @MainActor-isolated; if the
            // watchdog inherits that isolation, its `Task.sleep`
            // also runs on the main actor, and if the main actor
            // is congested (parent task holding it through some
            // sync work inside applyStreaming, SwiftUI tick updates
            // from the MiniHUD elapsed counter, etc.) the watchdog
            // never gets its turn and the 90 s deadline silently
            // passes. Detached runs on a global executor — its
            // sleep wakes up regardless of main-actor pressure.
            // The cancel itself hops back to MainActor since
            // `actionHotkeyTask` is main-actor-bound state.
            let watchdog = Task.detached(priority: .background) { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                guard !Task.isCancelled else { return }
                // Inner `[weak self]` is required (not just inherited
                // from the outer detached task) because `MainActor.run`
                // takes a @Sendable closure, and Swift 6 forbids those
                // from referencing a `var` capture (weak captures are
                // semantically `var`). The inner re-capture creates a
                // fresh, Sendable-compatible binding.
                await MainActor.run { [weak self] in
                    self?.actionHotkeyTask?.cancel()
                }
            }
            defer { watchdog.cancel() }

            guard await PasteSimulator.simulateCopyAndAwaitChange() else {
                MiniHUDController.shared.hideIfOwner(hudToken)
                SoundFeedback.play(.pasteFailure)
                return
            }
            if Task.isCancelled {
                MiniHUDController.shared.hideIfOwner(hudToken)
                return
            }
            // Selection captured — audible "got it" cue. Same sound as
            // ⌥⌘C (Quick Copy) because conceptually this IS a copy step:
            // the user's selection just landed in the pasteboard. The
            // eventual paste of the transformed result fires
            // `.pasteSuccess` later through performStandardPaste, giving
            // the user a clean two-stage capture-then-paste audio rhythm.
            SoundFeedback.play(.copySuccess)
            // Promote the captured selection into history right away
            // (don't wait for the watcher's 0.5 s poll). Next BigHUD
            // session will see it at index 0.
            self.watcher.forceTick()
            // Build a transient ClipboardItem we run the action against —
            // distinct from the store entry forceTick produced (different
            // UUID, not persisted on its own).
            let pb = NSPasteboard.general
            let item = self.snapshotPasteboardAsItem(pb: pb, sourceApp: frontmost)
            let ctx = ContextDetector.detect(item)
            // AI actions go through the streaming path even in the
            // direct-trigger flow — same code BigHUD's preview uses.
            // Direct polymorphic dispatch via the ClipboardAction
            // protocol (NOT a `as? AIAction` cast) because the
            // protocol has a default `applyStreaming` extension that
            // forwards to `apply()` for non-AI actions, so this one
            // call covers every action type uniformly. The cast-based
            // version was rejecting subtle AIAction variants and
            // falling through to `apply()` — which uses
            // URLSession.shared (no idle timeout, no SSE-finish
            // sentinel) and would hang indefinitely when the provider
            // leaked the stream past message_stop. onPartial is no-op
            // here (MiniHUD has no preview pane) — we only need the
            // final outcome.
            let outcome = await action.applyStreaming(
                item: item,
                context: ctx
            ) { _ in }
            if Task.isCancelled {
                // Either the user clicked the MiniHUD's X button or
                // the 90 s watchdog fired. Either way, we drop the
                // (possibly partial) outcome rather than pasting
                // garbage into the user's app, and surface a failure
                // chime so the user understands their hotkey didn't
                // produce a result.
                MiniHUDController.shared.hideIfOwner(hudToken)
                SoundFeedback.play(.pasteFailure)
                return
            }
            // Flash the "Done · X.Xs" green pill in the MiniHUD
            // before tearing it down. Gives the user a beat to
            // notice "yes, that finished, that's how long it took"
            // instead of the spinner just vanishing — important
            // when AI calls take meaningful time and the user
            // wonders "did it actually run?". Applies to ALL
            // AI-flavoured actions: text-AI (AIAction), image-AI
            // (AIImageAction), and text-to-image (AITextToImageAction).
            // Earlier the gate was `action is AIAction` only, which
            // meant image-AI direct-triggers (e.g. ⌥⌘W for
            // Watercolor) lost the completion pill — the spinner
            // would just vanish after a 10–20 s call without the
            // user knowing it finished on the wire. Local actions
            // still skip the pill because they're fast enough that
            // a "Done" beat would feel pointless.
            let isAI = (action is AIAction) || (action is AIImageAction) || (action is AITextToImageAction)
            if isAI {
                MiniHUDController.shared.markCompleteIfOwner(hudToken)
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            MiniHUDController.shared.hideIfOwner(hudToken)
            switch outcome {
            case .preview(let result):
                self.performStandardPaste(result, savedApp: frontmost)
            case .alternativeCommit(let result, .standardPaste):
                self.performStandardPaste(result, savedApp: frontmost)
            case .alternativeCommit(let result, .typeSlowly(let delay, let jitter)):
                // Respect the action's chosen commit style. Earlier this
                // case fell through into `performStandardPaste`, which
                // meant a per-action hotkey bound to Type Slowly would
                // ⌘V-paste the whole text instead of typing it
                // character-by-character — defeating the action's
                // entire purpose. Direct-trigger and HUD commit paths
                // must agree on what "commit" means for each style.
                self.performTypeSlowly(result, savedApp: frontmost,
                                       delay: delay, jitter: jitter)
            case .alternativeCommit(let result, .typeFast):
                self.performTypeSlowly(result, savedApp: frontmost,
                                       delay: 0.05, jitter: 0)
            case .sideEffect(_, let perform):
                perform()
                SoundFeedback.play(.pasteSuccess)
            case .failed(_, let reason, _):
                SoundFeedback.play(.pasteFailure)
                NSLog("DrPaste hotkey action failed: \(reason)")
                // #A69 — replace the silent disappear with an explicit
                // failure surface so the user sees the reason instead of
                // having to re-run the action through BigHUD just to read
                // it. Auto-dismisses after 4 s (MiniHUDController handles
                // the timer), or sooner via the X button. Action title +
                // reason gives "what failed and why" in two lines.
                MiniHUDController.shared.showFailure(
                    label: action.title,
                    reason: reason
                )
            }
        }
    }

    /// Build a transient ClipboardItem from the current pasteboard
    /// contents — used by selection-first hotkey paths so the action
    /// runs against a snapshot of what the user just highlighted.
    /// Writes raw blob copies of each representation through the store
    /// so Paste-as-is can still restore them losslessly downstream.
    @MainActor
    private func snapshotPasteboardAsItem(pb: NSPasteboard,
                                          sourceApp: NSRunningApplication) -> ClipboardItem {
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
            sourceBundleID: sourceApp.bundleIdentifier,
            sourceAppName: sourceApp.localizedName,
            sourceWindowTitle: nil,
            tags: []
        )
        if let types = pb.types {
            for t in types {
                guard let data = pb.data(forType: t) else { continue }
                let rel = store.writeRawBlob(data, type: t.rawValue)
                item.representations[t.rawValue] = rel
                item.typesOrdered.append(t.rawValue)
            }
        }
        return item
    }

    /// ⌥⌘S — Sum/Append Copy. Session-scoped accumulator that
    /// merges back-to-back clips into a single composite payload
    /// on the system pasteboard:
    ///
    ///   • First press in a session (no prior ⌥⌘S, or >5 min gap):
    ///     flush whatever's currently in the clipboard to history,
    ///     then ⌘C the user's current selection — that becomes the
    ///     seed for the accumulator.
    ///
    ///   • Subsequent presses: snapshot the current pasteboard
    ///     (that's the accumulator state from the previous press),
    ///     ⌘C the new selection, then merge.
    ///
    /// Two merge tracks:
    ///
    ///   • **Files-strict**. If the previous snapshot was a URL
    ///     list, the session is locked to file-mode. New snapshot
    ///     must also be files; otherwise we play failure sound and
    ///     restore the original file list to the pasteboard. Mixing
    ///     files with text/images doesn't have a clean semantic so
    ///     we refuse rather than guess.
    ///
    ///   • **Rich text**. Everything else (plain text, rich text,
    ///     images, mixed) is read as `NSAttributedString` and
    ///     appended. Images become inline `NSTextAttachment`s
    ///     downscaled to 1920px on the longer side. The composite
    ///     is written back to the pasteboard in four
    ///     representations (RTFD → RTF → HTML → plain text) so the
    ///     receiving app picks whichever it understands.
    nonisolated func hotkeyEngineDidAppendCopy() {
        Task { @MainActor in
            let pb = NSPasteboard.general

            let isNewSession: Bool = {
                if self.lastDrPasteAction != .appendCopy { return true }
                if let last = self.lastAppendCopyTime,
                   Date().timeIntervalSince(last) > self.appendSessionTimeout { return true }
                return false
            }()

            if isNewSession {
                // Flush whatever's currently in the clipboard to
                // history before we overwrite it with the seed.
                self.watcher.forceTick()
                pb.clearContents()
            }

            // Snapshot what the pasteboard holds RIGHT NOW — that's
            // either the previous accumulator state (subsequent
            // press) or empty (new session).
            let prevFiles: [URL]? = isNewSession ? nil :
                (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])
            let prevAttr: NSAttributedString? = isNewSession ? nil :
                AppendAccumulator.readAttributed(from: pb)

            let captured = await PasteSimulator.simulateCopyAndAwaitChange()
            self.lastAppendCopyTime = Date()
            self.lastDrPasteAction = .appendCopy

            if !captured {
                SoundFeedback.play(.copyFailure)
                return
            }

            // New session — clipboard now holds the just-copied
            // selection unchanged. Nothing to merge yet. Determine
            // the session's track (files-strict vs rich-text) by
            // probing the freshly captured selection: if it's a
            // URL list, light the indicator cyan; otherwise red.
            if isNewSession {
                self.watcher.ignoreNextChange = false
                self.watcher.forceTick()
                let seedFiles = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
                let filesMode = (seedFiles?.isEmpty == false)
                SoundFeedback.play(.appendCopy)
                self.flashStatusItem()
                self.armAppendSessionIndicator(filesMode: filesMode)
                return
            }

            // --- Subsequent press: merge prev × new ---

            // Files-strict path: previous was a URL list, so the
            // session is locked to files. Reject anything else.
            if let prevFiles = prevFiles, !prevFiles.isEmpty {
                if let combined = AppendAccumulator.mergeFiles(previous: prevFiles, pasteboard: pb) {
                    pb.clearContents()
                    pb.writeObjects(combined as [NSPasteboardWriting])
                    self.watcher.ignoreNextChange = false
                    self.watcher.forceTick()
                    SoundFeedback.play(.appendCopy)
                    self.flashStatusItem()
                    self.armAppendSessionIndicator(filesMode: true)
                    return
                }
                // New clip isn't files. Before giving up, check if
                // the previous files are ALL images — if so, this
                // is a legitimate cross-track bridge: convert the
                // image files to inline attachments, append the
                // new rich/text/image clip on top, and switch the
                // session into rich-text mode (cyan dot → red dot).
                // Same image-file means same content regardless of
                // whether the user copied it from Finder or from
                // Preview/Photos.
                let allImages = prevFiles.allSatisfy { AppendAccumulator.isImageURL($0) }
                if allImages,
                   let prevAsRich = AppendAccumulator.attributedString(forImageFiles: prevFiles),
                   let newAttr = AppendAccumulator.readAttributed(from: pb) {
                    let combined = AppendAccumulator.append(newAttr, to: prevAsRich)
                    AppendAccumulator.write(combined, to: pb)
                    self.watcher.ignoreNextChange = false
                    self.watcher.forceTick()
                    SoundFeedback.play(.appendCopy)
                    self.flashStatusItem()
                    self.armAppendSessionIndicator(filesMode: false)
                    return
                }
                // Genuinely incompatible — restore the original
                // URL list (⌘C clobbered it) and fail loudly.
                pb.clearContents()
                pb.writeObjects(prevFiles as [NSPasteboardWriting])
                self.watcher.ignoreNextChange = false
                SoundFeedback.play(.copyFailure)
                self.flashStatusItem()
                return
            }

            // Rich-text path: previous was text / rich text / image
            // / mixed. Append everything as NSAttributedString.
            // Reject the reverse-direction mismatch — files cannot
            // be appended to a rich-text accumulator either.
            // Without this guard the file URL leaks through
            // `readAttributed` as plain text (the URL string), so
            // the user would silently get "file:///path/to/foo.pdf"
            // pasted into their accumulating note instead of a
            // proper file attachment.
            let newAsFiles = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
            if let nf = newAsFiles, !nf.isEmpty {
                // Try the same bridge as the files-side path: if
                // every URL is an image, convert them to inline
                // attachments and append to the rich-text
                // accumulator. Mode stays red.
                let allImages = nf.allSatisfy { AppendAccumulator.isImageURL($0) }
                if allImages,
                   let asAttr = AppendAccumulator.attributedString(forImageFiles: nf) {
                    let prev = prevAttr ?? NSAttributedString()
                    let combined = AppendAccumulator.append(asAttr, to: prev)
                    AppendAccumulator.write(combined, to: pb)
                    self.watcher.ignoreNextChange = false
                    self.watcher.forceTick()
                    SoundFeedback.play(.appendCopy)
                    self.flashStatusItem()
                    self.armAppendSessionIndicator(filesMode: false)
                    return
                }
                // Not images — genuinely incompatible. Restore the
                // rich accumulator (⌘C clobbered it) and fail.
                pb.clearContents()
                if let prev = prevAttr {
                    AppendAccumulator.write(prev, to: pb)
                }
                self.watcher.ignoreNextChange = false
                SoundFeedback.play(.copyFailure)
                self.flashStatusItem()
                return
            }
            guard let prevAttr = prevAttr,
                  let newAttr = AppendAccumulator.readAttributed(from: pb) else {
                // Either side unreadable as attributed string —
                // shouldn't happen since readAttributed has plain-
                // text and image fallbacks, but if it does we
                // surface failure rather than corrupt the clipboard.
                self.watcher.ignoreNextChange = false
                SoundFeedback.play(.copyFailure)
                self.flashStatusItem()
                return
            }
            let combined = AppendAccumulator.append(newAttr, to: prevAttr)
            AppendAccumulator.write(combined, to: pb)
            self.watcher.ignoreNextChange = false
            self.watcher.forceTick()
            SoundFeedback.play(.appendCopy)
            self.flashStatusItem()
            self.armAppendSessionIndicator(filesMode: false)
        }
    }

    /// Mark that some DrPaste hotkey other than ⌥⌘S was used.
    /// Causes next ⌥⌘S to be treated as a new session (#2).
    /// Also tears down the menu-bar session indicator immediately,
    /// even before its timer would have expired — the explicit
    /// non-⌥⌘S action is the user's signal that they've moved on.
    @MainActor
    private func markOtherDrPasteAction() {
        lastDrPasteAction = .other
        lastAppendCopyTime = Date()
        disarmAppendSessionIndicator()
    }

    // MARK: - #A10 hold-preview wiring

    /// Push the current ⌥⌘<letter> action-hotkey map into the EventTap engine
    /// so it can intercept those chords and route them through the grace-
    /// timer flow. Called from initial setup and whenever ActionConfig's
    /// `actionHotkeys` map changes (Settings save / hotkey rebind).
    ///
    /// Only ⌥⌘<letter> hotkeys are forwarded — the hold-preview UX only
    /// makes sense when the user could plausibly keep ⌥⌘ held after the
    /// chord. Other modifier combos (⌃⇧X, etc.) stay on the Carbon
    /// direct-trigger path with no hold-preview support.
    @MainActor
    func reloadHoldPreviewMap() {
        guard let eventTap = engine as? EventTapEngine else { return }
        var map: [UInt16: String] = [:]
        let optCmd = UInt32(optionKey) | UInt32(cmdKey)
        for (actionID, hk) in registry.config.actionHotkeys where hk.modifiers == optCmd {
            guard registry.isEnabled(actionID) else { continue }
            map[hk.keyCode] = actionID
        }
        eventTap.setHoldPreviewActionHotkeys(map)
    }

    /// Pause every hotkey interception path (EventTap session-level tap,
    /// Carbon system hotkeys ⌥⌘V/C/X/S, Carbon per-action hotkeys) so the
    /// Settings hotkey recorder can capture ⌥⌘<letter> chords without
    /// them being consumed before the NSEvent local monitor sees them.
    /// Must be called in pairs with `endHotkeyRecording()`.
    @MainActor
    func beginHotkeyRecording() {
        engine?.setRecordingMode(true)
        ActionHotkeyManager.shared.pauseForRecording()
    }

    /// Restore hotkey interception after `beginHotkeyRecording()`. Reloads
    /// the per-action map from current config (so a hotkey the user just
    /// recorded and saved is picked up), then re-pushes the ⌥⌘<letter>
    /// hold-preview map to the EventTap.
    @MainActor
    func endHotkeyRecording() {
        engine?.setRecordingMode(false)
        ActionHotkeyManager.shared.resumeFromRecording()
        reloadHoldPreviewMap()
    }

    /// Build the list of ⌥⌘<letter> user hotkeys that the region-capture
    /// cheat sheet should display. Same filter as `reloadHoldPreviewMap`
    /// — only ⌥⌘ combos qualify; everything else can't fire while ⌥⌘ is
    /// held anyway. Sorted by display title so the legend reads
    /// predictably. Letter is uppercased so the keyboard's
    /// `highlightedLetters` set match works case-insensitively.
    @MainActor
    func collectRegionCaptureCheatSheetHotkeys() -> [RegionCaptureUserHotkey] {
        let optCmd = UInt32(optionKey) | UInt32(cmdKey)
        var out: [RegionCaptureUserHotkey] = []
        for (actionID, hk) in registry.config.actionHotkeys where hk.modifiers == optCmd {
            guard registry.isEnabled(actionID) else { continue }
            guard let action = registry.actions.first(where: { $0.id == actionID }) else { continue }
            let title = registry.displayTitle(forActionID: actionID, defaultTitle: action.title)
            let letter = KeyName.from(keyCode: hk.keyCode).uppercased()
            out.append(RegionCaptureUserHotkey(letter: letter, title: title))
        }
        out.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return out
    }

    /// EventTap-routed per-action hotkey fire.
    ///
    /// • `holdPreview: false` — user did the standard tap-and-release of
    ///   ⌥⌘<letter>. Run the action directly against the current
    ///   clipboard and paste the result into the frontmost app. This is
    ///   the same flow as the Carbon path (`actionHotkeyDidFire`) and
    ///   delegates to it for code reuse.
    /// • `holdPreview: true` — user held ⌥⌘ past the 250 ms grace
    ///   period. Open the HUD focused on the action so the user can
    ///   preview the result before committing. The standard release-⌥⌘
    ///   commit gesture (existing Gesture Mode logic) pastes whatever
    ///   the user navigated to.
    nonisolated func hotkeyEngineDidFireActionHotkey(actionID: String,
                                                      holdPreview: Bool) {
        Task { @MainActor in
            if holdPreview {
                self.openBigHUDFocusedOnAction(actionID: actionID)
            } else {
                self.actionHotkeyDidFire(actionID: actionID)
            }
        }
    }

    // MARK: - #A11 region capture delegate

    /// Grace expired with bare ⌥⌘ still held alone. Raise the C2 cursor
    /// overlay so the user sees crosshair feedback that capture mode is
    /// armed. Wire onCapture / onCancel here too because the controller
    /// is short-lived (rebuilt every gesture).
    nonisolated func hotkeyEngineDidArmRegionCapture() {
        Task { @MainActor in self.armRegionCapture() }
    }

    /// User clicked while armed. C1 selection overlay takes over from
    /// C2 cursor overlay; rectangle anchors at the mouse-down point.
    nonisolated func hotkeyEngineDidBeginRegionDrag(at globalPoint: NSPoint) {
        Task { @MainActor in self.regionCapture?.beginSelection(at: globalPoint) }
    }

    nonisolated func hotkeyEngineDidUpdateRegionDrag(to globalPoint: NSPoint) {
        Task { @MainActor in self.regionCapture?.updateSelection(to: globalPoint) }
    }

    /// Mouse released with a valid selection. Controller captures the
    /// region synchronously and fires `onCapture` (wired in
    /// `armRegionCapture`). The engine has already set its internal
    /// HUD-active flag so the next ⌥⌘ release will commit the standard
    /// paste path against whatever the user navigates to in the HUD.
    nonisolated func hotkeyEngineDidEndRegionDrag(at globalPoint: NSPoint) {
        Task { @MainActor in self.regionCapture?.endSelection(at: globalPoint) }
    }

    /// ⌥⌘ released without committing the capture (no mouse-down, or
    /// mid-drag bail). Tear down overlays without affecting clipboard.
    nonisolated func hotkeyEngineDidCancelRegionCapture() {
        Task { @MainActor in self.regionCapture?.cancel() }
    }

    /// Build and wire a fresh ScreenRegionCaptureController, then arm it.
    /// Controller is instance-per-gesture — easier than keeping one alive
    /// across all the state transitions since each gesture cleanly
    /// terminates with onCapture or onCancel.
    @MainActor
    private func armRegionCapture() {
        // Block region capture when ANY DrPaste UI is up. The EventTap
        // engine already guards against its own bigHUDIsActive flag for
        // Gesture-mode HUDs, but we layer a belt-and-braces check here
        // to cover all cases — visible BigHUDPanel (any reason), MiniHUD
        // showing an in-flight action, or a deferred-paste handoff
        // waiting for an AI stream. In all of these the user has
        // existing DrPaste state on screen that the region-capture
        // gesture would conflict with, so we silently ignore the arm.
        // The engine's region-capture state self-recovers on the next
        // ⌥⌘ release (flagsChanged path fires cancel which finds no
        // overlay to tear down — no-op).
        if bigHUDPanel?.isVisible == true { return }
        if pendingDeferredPasteApp != nil { return }
        if aiStreamingTask != nil { return }
        // Direct-trigger in flight (MiniHUD on screen with a streaming AI /
        // image transform). Without this guard the user could fire a fast
        // ⌥⌘<letter> tap, then keep ⌥⌘ held alone, and 400 ms later the
        // region-capture cursor overlay + cheat sheet would pop up while
        // the MiniHUD is still spinning. Two unrelated DrPaste surfaces
        // on screen at the same time, AI request continuing in the
        // background — this is the "2 HUDs at once, spinner forever"
        // scenario the user reported. Same guard family as the three
        // above: any in-flight DrPaste state blocks region-capture arm.
        if actionHotkeyTask != nil { return }
        // Likewise a still-pending hold-preview open (simulateCopy is
        // mid-poll, BigHUD hasn't materialized yet). Without this an
        // arm fired while the open task races to completion could leave
        // both surfaces visible simultaneously.
        if bigHUDOpenTask != nil { return }
        // MiniHUD is the user-visible signal that DrPaste is busy. If it
        // somehow survived an external cancellation path (defensive — we
        // already cancel the underlying tasks above), don't let region-
        // capture stack on top of it.
        if MiniHUDController.shared.isVisible { return }

        // Remember which app was frontmost at arm time so the eventual
        // paste lands in the right window. NSWorkspace.frontmostApplication
        // at gesture start is more reliable than at capture time because
        // by then the user may have clicked into a different window.
        regionCaptureSourceApp = NSWorkspace.shared.frontmostApplication

        let controller = ScreenRegionCaptureController()
        regionCapture = controller

        // Hand the cheat sheet a closure that pulls fresh user
        // hotkeys from the registry every time it shows. Filter to
        // ⌥⌘<letter> only — other modifier combos can't fire while
        // ⌥⌘ is held anyway (see the modifier-matching invariant
        // recorded for the per-action hotkey path).
        controller.cheatSheet.hotkeysProvider = { [weak self] in
            guard let self = self else { return [] }
            return self.collectRegionCaptureCheatSheetHotkeys()
        }

        controller.onCapture = { [weak self] data, rect in
            guard let self = self else { return }
            self.regionCapture = nil
            guard let pngData = data else {
                // Capture failed — most likely Screen Recording permission
                // hasn't been granted yet. macOS will have shown its own
                // prompt; play the failure sound so the user has audio
                // confirmation something went wrong.
                SoundFeedback.play(.pasteFailure)
                self.regionCaptureSourceApp = nil
                return
            }
            // Width/height in pixels = points × backing scale of the screen
            // the rect was on. Fall back to main screen if we can't locate it.
            let scale = NSScreen.screens.first(where: { $0.frame.intersects(rect) })?
                .backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let pxW = Int(rect.width * scale)
            let pxH = Int(rect.height * scale)
            let sourceApp = self.regionCaptureSourceApp
            self.regionCaptureSourceApp = nil
            if let item = self.store.addCapturedImage(pngData: pngData,
                                                     width: pxW,
                                                     height: pxH,
                                                     sourceApp: sourceApp) {
                // Confirmation toast (#A66) — explicit dimensions so the
                // user knows the capture went through. Anchored near
                // the menu bar so it doesn't compete with the freshly-
                // opening BigHUD.
                ToastController.shared.show(
                    message: "Captured \(pxW)×\(pxH)",
                    systemImage: "camera.viewfinder",
                    duration: 1.2,
                    category: .essential
                )
                self.openBigHUDFocusedOnCapturedImage(item: item, sourceApp: sourceApp)
            }
        }

        controller.onCancel = { [weak self] in
            self?.regionCapture = nil
            self?.regionCaptureSourceApp = nil
        }

        controller.arm()
    }

    /// Open the BigHUD with the freshly-captured image as the focused
    /// row. Mirrors `openBigHUDFocusedOnAction` but for an item (Paste-as-
    /// is by default — the user can arrow over to Extract text / ASCII
    /// art / AI Describe etc. while still holding ⌥⌘).
    @MainActor
    private func openBigHUDFocusedOnCapturedImage(item: ClipboardItem,
                                                  sourceApp: NSRunningApplication?) {
        markOtherDrPasteAction()
        currentSummonReason = .paste
        // Match openBigHUDFocusedOnAction / openHUD — cancel any prior
        // direct-trigger, stranded hold-preview, or deferred-paste
        // stream and take down the MiniHUD before this BigHUD comes
        // up. Without these, a region capture finishing while an
        // older MiniHUD was on screen would leave both surfaces
        // visible simultaneously and the old action's eventual paste
        // would land into the wrong app.
        actionHotkeyTask?.cancel()
        actionHotkeyTask = nil
        bigHUDOpenTask?.cancel()
        bigHUDOpenTask = nil
        aiStreamingTask?.cancel()
        aiStreamingTask = nil
        pendingDeferredPasteApp = nil
        MiniHUDController.shared.hide()
        savedFrontmostApp = sourceApp
        bigHUDState.items = store.items
        // The freshly-captured image was inserted at index 0 by
        // ClipboardStore.addCapturedImage.
        bigHUDState.itemIndex = 0
        bigHUDState.actionIndex = 0
        bigHUDState.contentMeta = nil
        bigHUDState.mode = engine.bigHUDMode
        recomputeActions()
        refreshPreview()
        updateContentMeta()
        showBigHUD()
    }

    /// Open the HUD pre-focused on a specific action (current clipboard as
    /// the focused item). Used by the #A10 hold-preview path so a user
    /// holding ⌥⌘ after a per-action hotkey chord lands directly on the
    /// action's preview without first browsing to it.
    ///
    /// The EventTap engine has already set its internal `bigHUDIsActive` flag
    /// before invoking us, so the subsequent ⌥⌘ release flows through the
    /// existing `flagsChanged → hotkeyEngineDidRelease` commit path — same
    /// gesture-mode commit semantics as releasing after ⌥⌘V.
    @MainActor
    private func openBigHUDFocusedOnAction(actionID: String) {
        markOtherDrPasteAction()
        currentSummonReason = .paste

        // Cancel any in-flight direct-trigger action — the MiniHUD it
        // spawned is about to be replaced by the BigHUD, and we don't
        // want the old action's eventual paste landing in whatever the
        // user is looking at when the BigHUD-driven paste also fires.
        actionHotkeyTask?.cancel()
        actionHotkeyTask = nil
        // Same for a prior in-flight hold-preview open. Without this,
        // rapid ⌥⌘+letter holds (release-then-rehold faster than the
        // 250 ms simulateCopy poll) could stack two BigHUD open
        // sequences, each calling refreshPreview and racing to set
        // bigHUDState.actionIndex.
        bigHUDOpenTask?.cancel()
        bigHUDOpenTask = nil
        // And a deferred-paste AI stream — opening a fresh BigHUD
        // session means whatever the deferred paste was about to do is
        // stale (user clearly moved on). Cancel the stream and clear
        // the target so its completion handler doesn't fire a paste
        // into the user's app behind the new BigHUD.
        aiStreamingTask?.cancel()
        aiStreamingTask = nil
        pendingDeferredPasteApp = nil
        // Visual de-overlap — if a prior direct-trigger left a MiniHUD
        // on screen, take it down before the BigHUD comes up.
        MiniHUDController.shared.hide()

        // Selection-first, same as the direct-trigger path. The BigHUD
        // preview is only useful if it reflects the action applied to
        // what the user actually highlighted — stale clipboard content
        // would render a misleading preview and lead to a wrong paste.
        // Issue ⌘C, wait for pb to refresh, then open the HUD with the
        // freshly-captured item at the top.
        bigHUDOpenTask = Task { @MainActor in
            guard await PasteSimulator.simulateCopyAndAwaitChange() else {
                // No selection. Failure feedback + reset EventTap's
                // bigHUDIsActive flag (the engine had set it true in
                // anticipation of this open) so the inevitable ⌥⌘
                // release doesn't try to commit a HUD that never
                // opened.
                SoundFeedback.play(.pasteFailure)
                (self.engine as? EventTapEngine)?.resetHudActive()
                self.bigHUDOpenTask = nil
                return
            }
            // Cancellation can land at every await point — a competing
            // hold-preview fire or a release-during-poll could have
            // already replaced this task. Check before doing visible
            // state mutations.
            if Task.isCancelled { self.bigHUDOpenTask = nil; return }
            // Stranded-BigHUD guard. The ⌘C poll can take up to 250 ms;
            // if the user released ⌥⌘ in that window, hotkeyEngineDidRelease
            // already ran, found nothing to commit (state still empty),
            // and reset bigHUDIsActive. Continuing past this point would
            // open BigHUD "after the train left" — visible on screen with
            // no user gesture holding it. Bail out instead.
            guard let tap = self.engine as? EventTapEngine, tap.isHudActive else {
                self.bigHUDOpenTask = nil
                return
            }
            // Selection captured — same audible "got it" cue as the
            // direct-trigger path. The eventual paste on ⌥⌘ release
            // fires `.pasteSuccess` via the standard commit path, so
            // the user still hears the two-stage capture-then-paste
            // rhythm even when using the hold-preview flow.
            SoundFeedback.play(.copySuccess)
            // Promote selection into history so the BigHUD sees it at
            // index 0.
            self.watcher.forceTick()

            self.bigHUDState.items = self.store.items
            self.bigHUDState.itemIndex = 0
            self.bigHUDState.contentMeta = nil
            self.bigHUDState.mode = self.engine.bigHUDMode
            self.recomputeActions()
            if let idx = self.bigHUDState.actions.firstIndex(where: { $0.id == actionID }) {
                self.bigHUDState.actionIndex = idx
            } else {
                self.bigHUDState.actionIndex = 0
            }
            self.refreshPreview()
            self.updateContentMeta()
            self.showBigHUD()
            self.bigHUDOpenTask = nil
        }
    }

    nonisolated func hotkeyEngineDidQuickCopy() {
        Task { @MainActor in
            self.markOtherDrPasteAction()
            if await PasteSimulator.simulateCopyAndAwaitChange() {
                SoundFeedback.play(.copySuccess)
                self.flashStatusItem()
            } else {
                SoundFeedback.play(.copyFailure)
            }
        }
    }

    private func flashStatusItem() {
        guard let btn = statusItem.button else { return }
        let original = btn.image
        // Brief accent flash as a simple visual confirmation.
        btn.appearsDisabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            btn.appearsDisabled = false
            btn.image = original
        }
    }

    /// Lazy-create the 6-pt red dot overlay used as the Append
    /// Copy session indicator. Added as a subview of the status
    /// item's button so the template tinting on the underlying
    /// icon stays untouched (the dot itself is intentionally
    /// not a template — it must read as red in both light and
    /// dark menu bars).
    @MainActor
    private func ensureSessionDotView() {
        guard let btn = statusItem?.button, sessionDotView == nil else { return }
        let dot = NSView()
        dot.wantsLayer = true
        // Initial colour doesn't matter — `armAppendSessionIndicator`
        // sets red/cyan based on the session track before unhiding.
        dot.layer?.cornerRadius = 3   // half of 6pt = a circle
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.isHidden = true
        btn.addSubview(dot)
        // Pin to the upper-right corner with a 1-pt inset so the
        // dot sits comfortably inside the clipboard glyph without
        // touching the icon's outline.
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.topAnchor.constraint(equalTo: btn.topAnchor, constant: 1),
            dot.trailingAnchor.constraint(equalTo: btn.trailingAnchor, constant: -1)
        ])
        sessionDotView = dot
    }

    /// Show the session-indicator dot and (re)arm the auto-hide
    /// timer. `filesMode = true` paints the dot bright cyan to
    /// signal a files-strict session; `false` paints red for the
    /// rich-text accumulator. The two tracks never mix at runtime,
    /// so the colour is a quick at-a-glance reminder which kind
    /// the next ⌥⌘S will demand (file URLs vs anything else). The
    /// timer's interval matches `appendSessionTimeout` so the dot
    /// vanishes the moment the session would no longer extend the
    /// existing accumulator.
    @MainActor
    private func armAppendSessionIndicator(filesMode: Bool) {
        // Per-session toast feedback (#A65). On the FIRST ⌥⌘S of a
        // fresh session (no active dot yet) show "Append started";
        // on subsequent presses within the same session show
        // "Appended (N clips)" where N = current accumulator size.
        // Suppressed when the user has disabled append toasts via
        // Settings (`PreferenceKeys.appendToastsEnabled`).
        let wasActive = sessionDotView?.isHidden == false
        ensureSessionDotView()
        let color: NSColor = filesMode ? .systemCyan : .systemRed
        sessionDotView?.layer?.backgroundColor = color.cgColor
        sessionDotView?.isHidden = false
        updateStatusTooltip(appendActive: true, filesTrack: filesMode)
        appendSessionTimer?.invalidate()
        appendSessionTimer = Timer.scheduledTimer(withTimeInterval: appendSessionTimeout,
                                                  repeats: false) { [weak self] _ in
            Task { @MainActor in self?.disarmAppendSessionIndicator() }
        }
        // Toast after the dot is armed so the message reflects the
        // new state, not the prior one.
        if !wasActive {
            ToastController.shared.show(
                message: filesMode ? "Append started — files" : "Append started",
                systemImage: filesMode ? "doc.on.doc" : "rectangle.stack.badge.plus",
                category: .appendCopy
            )
        } else {
            ToastController.shared.show(
                message: filesMode ? "Files appended" : "Clip appended",
                systemImage: filesMode ? "doc.on.doc.fill" : "rectangle.stack.fill.badge.plus",
                category: .appendCopy
            )
        }
    }

    /// Hide the dot and cancel the auto-hide timer. Called when
    /// the user explicitly ends the session by invoking another
    /// DrPaste hotkey, or implicitly via timeout.
    @MainActor
    private func disarmAppendSessionIndicator() {
        let wasActive = sessionDotView?.isHidden == false
        appendSessionTimer?.invalidate()
        appendSessionTimer = nil
        sessionDotView?.isHidden = true
        updateStatusTooltip(appendActive: false, filesTrack: false)
        // Surface "session ended" only if a session was actually
        // active — the disarm path also runs during construction.
        if wasActive {
            ToastController.shared.show(
                message: "Append ended",
                systemImage: "checkmark.circle",
                category: .appendCopy
            )
        }
    }

    // MARK: HUD lifecycle

    private func openHUD() {
        // Per-session pin reset (#A30): every fresh HUD open starts
        // unpinned. The user opts into multi-commit mode by clicking
        // the pin icon after opening, not as a persistent preference.
        bigHUDState.isPinned = false
        // De-overlap any prior direct-trigger MiniHUD before we put the
        // BigHUD up. The action behind that MiniHUD might still be
        // running an AI stream; cancel it so its eventual paste doesn't
        // land in the user's app after they've already moved on to
        // browsing history.
        actionHotkeyTask?.cancel()
        actionHotkeyTask = nil
        // Same for a stranded hold-preview open in flight.
        bigHUDOpenTask?.cancel()
        bigHUDOpenTask = nil
        // A deferred-paste AI stream is also stale once the user
        // explicitly opens a fresh BigHUD session — they've moved on
        // from whatever the pending paste was about to do. Clearing
        // pendingDeferredPasteApp prevents the streaming task's
        // completion handler from firing a paste into the user's
        // original app behind the newly-opened BigHUD.
        aiStreamingTask?.cancel()
        aiStreamingTask = nil
        pendingDeferredPasteApp = nil
        MiniHUDController.shared.hide()

        bigHUDState.items = store.items
        // Cut & Replace UX: when cursorOnSecondOnCut is enabled and there are
        // more than one item, the cursor starts on the second (skipping the
        // just-cut item). Default off matches native cut+paste behavior.
        let skipCutItem = currentSummonReason == .cutAndReplace
            && UserDefaults.standard.bool(forKey: "drpaste.hud.cursorOnSecondOnCut")
            && bigHUDState.items.count > 1
        bigHUDState.itemIndex = skipCutItem ? 1 : 0
        bigHUDState.actionIndex = 0
        bigHUDState.contentMeta = nil
        recomputeActions()
        refreshPreview()
        updateContentMeta()
        showBigHUD()
        if engine.bigHUDMode == .summon { installLocalKeyMonitor() }
    }

    /// Compute content meta for the focused item — async, lazy, cached.
    private func updateContentMeta() {
        guard let item = bigHUDState.currentItem else {
            bigHUDState.contentMeta = nil
            return
        }
        bigHUDState.contentMeta = nil   // placeholder "…"
        let itemID = item.id
        Task { [weak self] in
            // Background compute via a detached child task, then await back on
            // the MainActor. Avoids the Swift 6 warning about concurrent var
            // capture of self in MainActor.run.
            let meta = await Task.detached(priority: .userInitiated) {
                ContentMetaCache.shared.computeSync(for: item)
            }.value
            guard let self = self else { return }
            if self.bigHUDState.currentItem?.id == itemID {
                self.bigHUDState.contentMeta = meta
            }
        }
    }

    private func commitBigHUD() {
        let savedApp = savedFrontmostApp

        // Deferred-paste path: if an AI action is still streaming, the
        // outcome currently held in bigHUDState is the placeholder (original
        // un-transformed clipboard), NOT the eventual AI result. Don't
        // paste the placeholder — keep the streaming task running, take
        // down HUD chrome, promote ProgressHUD as the in-flight indicator,
        // and paste the real outcome when the stream completes. Makes the
        // hotkey timing model uniform: press hotkey → result pastes when
        // ready, regardless of how long ⌥⌘ was held.
        if bigHUDState.isPreviewLoading, bigHUDState.aiInflight != nil {
            deferPasteAfterAILoad(savedApp: savedApp)
            return
        }

        let outcome = bigHUDState.outcome
        // Pin behaviour (#A30): if the user pinned the HUD, treat
        // this commit as paste-and-keep so the HUD stays open for
        // subsequent commits. savedFrontmostApp is preserved so the
        // next commit targets the same app.
        let pinned = bigHUDState.isPinned
        if !pinned {
            savedFrontmostApp = nil
            closeBigHUD()
        }

        guard let outcome = outcome else { return }
        commitOutcome(outcome, savedApp: savedApp)
    }

    /// Variant of `commitBigHUD` triggered by ⌥⌘⏎: paste the focused
    /// outcome into the saved target app but DO NOT close the HUD.
    /// Lets the user paste several clipboard items back-to-back
    /// without the open-HUD friction every time. Differences from
    /// the regular commit:
    ///
    ///   • `savedFrontmostApp` is preserved (the next paste targets
    ///     the same app — closing it would orphan the workflow).
    ///   • `closeBigHUD()` is NOT called — local key monitor stays
    ///     installed, panel stays on screen at panel level.
    ///   • After the paste lands in the target app, the HUD is
    ///     re-keyed and re-activated so arrow/⏎ keys keep going
    ///     to it instead of leaking into the target app. The
    ///     120 ms delay is empirical: long enough for the ⌘V we
    ///     synthesize in `performStandardPaste` to be processed
    ///     by the target app's runloop, short enough that the
    ///     user doesn't notice the gap.
    ///   • Streaming-AI placeholder protection still applies —
    ///     if the focused row is the placeholder for an in-flight
    ///     AI call, fall through to the regular `commitBigHUD`
    ///     path (which routes to `deferPasteAfterAILoad`). Pasting
    ///     a placeholder repeatedly would surface stale text.
    @MainActor
    private func commitBigHUDKeepingOpen() {
        let savedApp = savedFrontmostApp
        if bigHUDState.isPreviewLoading, bigHUDState.aiInflight != nil {
            commitBigHUD()
            return
        }
        guard let outcome = bigHUDState.outcome else { return }
        // Only `.preview` and `.alternativeCommit(_, .standardPaste)`
        // make sense to paste-and-keep. Side-effects (Reveal in
        // Finder), Type Slowly, Type Fast, and failure recovery
        // all have non-paste commit semantics that would be
        // confusing to fire silently while the HUD is up — for
        // those, fall through to the normal commit path which
        // closes the HUD and plays the usual outcome chrome.
        let item: ClipboardItem
        switch outcome {
        case .preview(let i):                            item = i
        case .alternativeCommit(let i, .standardPaste):  item = i
        default:
            commitBigHUD()
            return
        }
        // Mark so the Gesture-Mode release handler doesn't double-
        // paste when the user lets go of ⌥⌘ after this chord.
        // Limited Mode never calls didRelease, so this flag is a
        // no-op there.
        pasteAndKeepDidFire = true
        // Write the item to the pasteboard, then synthesize ⌘V
        // through the SESSION event tap — NOT the HID tap that
        // PasteSimulator.simulatePaste() uses. The user is still
        // physically holding ⌥⌘ for this chord; if we posted ⌘V
        // through cghidEventTap, HID would merge the held Option
        // into our event and the target app would receive ⌥⌘V —
        // which is DrPaste's own summon-HUD hotkey, so focus
        // would bounce back to DrPaste with nothing pasted.
        PasteboardWriter.write(item, store: store)
        watcher.ignoreNextChange = true
        // Make sure target app is frontmost so it receives ⌘V.
        // Safe to call even in Gesture Mode where the HUD is a
        // nonactivating overlay and target is already frontmost —
        // activate becomes a no-op there. Critical in Limited Mode
        // where the HUD's key window made DrPaste frontmost.
        savedApp?.activate(options: [])
        // ~30 ms for the activation to settle before posting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            if AXIsProcessTrusted() {
                PasteSimulator.simulatePasteKeepingHeldModifiers()
            }
            SoundFeedback.play(.pasteSuccess)
        }
        // Deliberately DO NOT re-front DrPaste / the HUD panel
        // after the paste. The HUD is a nonactivating overlay
        // panel (`hidesOnDeactivate = false`) so it stays visible
        // on top of the target app without holding focus, and the
        // EventTap engine listens for ⌥⌘<key> chords globally —
        // so the next ⌥⌘⏎ works regardless of which app owns the
        // keyboard focus. Calling NSApp.activate here would steal
        // focus from the target app, blur its text caret, and
        // (most visibly) make the user's window switcher show
        // DrPaste — exactly the "переключает окно" behaviour the
        // user reported.
    }

    /// Single-place ApplyOutcome → side-effect mapping. Called by both the
    /// synchronous HUD commit path and the deferred AI-completion path so
    /// they produce identical user-visible behaviour for the same outcome.
    @MainActor
    private func commitOutcome(_ outcome: ApplyOutcome,
                                savedApp: NSRunningApplication?) {
        switch outcome {
        case .preview(let item), .alternativeCommit(let item, .standardPaste):
            performStandardPaste(item, savedApp: savedApp)
        case .alternativeCommit(let item, .typeSlowly(let delay, let jitter)):
            performTypeSlowly(item, savedApp: savedApp, delay: delay, jitter: jitter)
        case .alternativeCommit(let item, .typeFast):
            performTypeSlowly(item, savedApp: savedApp, delay: 0.05, jitter: 0)
        case .failed(let original, _, _):
            // On commit of a failed outcome, paste the original and play the failure sound.
            performStandardPaste(original, savedApp: savedApp)
            SoundFeedback.play(.pasteFailure)
        case .sideEffect(_, let perform):
            perform()
            SoundFeedback.play(.pasteSuccess)
        }
    }

    /// Convert a HUD commit that landed during AI streaming into a deferred
    /// paste. HUD chrome goes away (the user signalled "I'm done watching")
    /// but the streaming task and its eventual result stay alive. ProgressHUD
    /// surfaces the wait so the user has SOME visible indicator that the
    /// AI is still working — same chrome they'd have seen on a quick-tap
    /// direct-trigger path. Paste fires from the streaming task's completion
    /// block when the AI finishes (or the partial when it fails mid-stream).
    @MainActor
    private func deferPasteAfterAILoad(savedApp: NSRunningApplication?) {
        let inflight = bigHUDState.aiInflight
        // Record the target app for the streaming task's completion handler
        // to fire against. Cleared in the completion handler itself.
        pendingDeferredPasteApp = savedApp
        savedFrontmostApp = nil

        // Hide HUD chrome but DO NOT call closeBigHUD — closeBigHUD cancels
        // aiStreamingTask, which would defeat the entire purpose. We do
        // need to tear down the gesture monitor and tick timer manually.
        removeLocalKeyMonitor()
        stopAITickTimer()
        bigHUDState.accumulator = nil
        bigHUDPanel?.orderOut(nil)
        // Bump the showBigHUD retry session so any in-flight 80 ms
        // retry from the initial show doesn't resurrect the panel on
        // top of the MiniHUD we're about to show. Without this, the
        // retry can re-orderFront the panel ~80 ms after deferred-
        // paste handoff, producing the "2 HUDs at once" the user
        // sees after a fast ⌥⌘+letter tap on an AI action.
        cancelBigHUDShowRetry()

        // Surface the in-flight state in ProgressHUD so the user sees the
        // wait. Identical chrome to what a quick-tap direct-trigger would
        // have shown for the same action — keeps the visual language
        // consistent across the two entry points.
        //
        // onCancel: the X button is the user's escape hatch out of a slow
        // AI call. Clicking it must cancel the streaming task AND clear
        // pendingDeferredPasteApp so the completion handler (if it fires
        // after cancellation) doesn't paste something into the user's
        // original app behind their back.
        let cancelHandler: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.aiStreamingTask?.cancel()
            self.aiStreamingTask = nil
            self.pendingDeferredPasteApp = nil
            SoundFeedback.play(.pasteFailure)
        }
        if let inflight = inflight {
            MiniHUDController.shared.show(label: inflight.actionTitle,
                                              inflight: inflight,
                                              onCancel: cancelHandler)
        } else {
            MiniHUDController.shared.show(label: "Working…",
                                              onCancel: cancelHandler)
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
        // Small delay so the HUD disappears and focus returns to the target app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            TypeSimulator.typeSlowly(text, baseDelay: delay, jitter: jitter)
        }
    }

    private func closeBigHUD() {
        // Reset paste-and-keep latch — next HUD open starts fresh.
        // Guards against the case where the latch was set by ⌥⌘⏎
        // but the HUD closes via some other path (Esc, AI cancel,
        // another summon stomping this one) before the deferred
        // release fires.
        pasteAndKeepDidFire = false
        removeLocalKeyMonitor()
        stopAITickTimer()
        // Cancel any in-flight AI streaming. Cancellation cascades through
        // the AsyncThrowingStream continuation's onTermination hook into
        // the underlying URLSession data task, dropping the connection and
        // stopping further token billing.
        aiStreamingTask?.cancel()
        aiStreamingTask = nil
        // Same for any in-flight local preview (CIFilter / VN work).
        localPreviewTask?.cancel()
        localPreviewTask = nil
        // And any direct-trigger action still running from before the
        // BigHUD opened.
        actionHotkeyTask?.cancel()
        actionHotkeyTask = nil
        // Any in-flight hold-preview open — defensive, in practice
        // this is nil by the time the user can close, but covers the
        // edge case where a fresh open task is still mid-poll when
        // commit/cancel arrives.
        bigHUDOpenTask?.cancel()
        bigHUDOpenTask = nil
        // The deferred-paste indicator (MiniHUD with the streaming AI
        // task) is a DIFFERENT mode of BigHUD teardown — handled by
        // deferPasteAfterAILoad, NOT this path. By the time we hit
        // closeBigHUD, any deferred-paste state is stale; clear it
        // so a late-arriving completion handler doesn't paste behind
        // the user's back.
        pendingDeferredPasteApp = nil
        // Belt-and-braces — if a MiniHUD somehow survived (deferred-
        // paste indicator that should have been hidden by the
        // completion handler, or a direct-trigger orphan), take it
        // down here. Mutually exclusive surfaces: when BigHUD closes,
        // no MiniHUD should be left on screen.
        MiniHUDController.shared.hide()
        bigHUDState.aiInflight = nil
        bigHUDState.accumulator = nil
        bigHUDPanel?.orderOut(nil)
        // Same anti-resurrection guard as deferPasteAfterAILoad — kill
        // any pending 80 ms visibility retry that might still re-show
        // the panel after we've explicitly torn down.
        cancelBigHUDShowRetry()
        // CRITICAL: clear the EventTap's bigHUDIsActive flag. Without
        // this the engine keeps thinking the HUD is up and swallows
        // every keyDown system-wide via the navigation switch's
        // `default: return nil` arm — including plain ⌘V into other
        // apps (Settings text fields, Edit Action sample input,
        // anywhere). User-reported: "can't paste into Sample Input,
        // only type." Normal gesture-mode close already clears the
        // flag via the ⌥⌘-release flagsChanged path, but X-button /
        // Esc / Limited Mode commit / programmatic close all bypass
        // it. Belt-and-braces: always reset on teardown.
        (engine as? EventTapEngine)?.resetHudActive()
    }

    private func navigate(_ direction: NavDirection) {
        // Navigation does NOT drop the accumulator — the user is scouting
        // candidate clips to fold in. Consumed indices are skipped so the
        // visible list and the cursor stay in sync.
        let consumed = bigHUDState.accumulator?.consumed ?? []
        switch direction {
        case .up:
            var t = bigHUDState.itemIndex - 1
            while t >= 0 && consumed.contains(t) { t -= 1 }
            if t >= 0 {
                bigHUDState.itemIndex = t; bigHUDState.actionIndex = 0
                recomputeActions(); refreshPreview(); updateContentMeta()
            }
        case .down:
            var t = bigHUDState.itemIndex + 1
            while t < bigHUDState.items.count && consumed.contains(t) { t += 1 }
            if t < bigHUDState.items.count {
                bigHUDState.itemIndex = t; bigHUDState.actionIndex = 0
                recomputeActions(); refreshPreview(); updateContentMeta()
            }
        case .left:
            if bigHUDState.actionIndex > 0 { bigHUDState.actionIndex -= 1; refreshPreview() }
        case .right:
            if bigHUDState.actionIndex + 1 < bigHUDState.actions.count {
                bigHUDState.actionIndex += 1; refreshPreview()
            }
        }
    }

    private func recomputeActions() {
        guard let item = bigHUDState.currentItem else { bigHUDState.actions = []; return }
        let ctx = ContextDetector.detect(item)
        bigHUDState.actions = registry.applicable(for: item, context: ctx)
    }

    private func refreshPreview() {
        guard let item = bigHUDState.currentItem,
              let action = bigHUDState.currentAction else {
            bigHUDState.outcome = nil
            return
        }
        previewToken &+= 1
        let myToken = previewToken
        let ctx = ContextDetector.detect(item)

        // Clear any prior AI-inflight state from a previous focused action
        // (the timer would otherwise keep ticking against a now-irrelevant
        // start time). The AI branch below sets it again for actual AI calls.
        stopAITickTimer()
        bigHUDState.aiInflight = nil
        bigHUDState.aiElapsed = 0

        // When a clip accumulator is active the preview always shows the
        // accumulated text — the focused action's transformation is bypassed
        // because the user is in "merge clips" mode, not "transform clip" mode.
        if let acc = bigHUDState.accumulator {
            bigHUDState.isPreviewLoading = false
            bigHUDState.outcome = .preview(accumulatorItem(attr: acc.attr))
            return
        }

        // Cancel any prior AI streaming task whose preview is now stale —
        // the user moved on, no reason to keep burning provider tokens.
        aiStreamingTask?.cancel()
        aiStreamingTask = nil
        // Same for any prior local preview task — image actions doing
        // CIFilter / VN work otherwise pile up on the background queue
        // when the user navigates quickly.
        localPreviewTask?.cancel()
        localPreviewTask = nil

        if action.isLocal {
            // Show the spinner immediately so the user gets visual
            // feedback that "this action is computing", instead of
            // staring at the previous action's stale preview for the
            // 100–500 ms an image transformation takes on a typical
            // full-resolution clip. Spinner clears the moment the
            // result lands.
            bigHUDState.isPreviewLoading = true
            localPreviewTask = Task { @MainActor in
                let outcome = await action.apply(item: item, context: ctx)
                if myToken == self.previewToken {
                    self.bigHUDState.outcome = outcome
                    self.bigHUDState.isPreviewLoading = false
                }
            }
        } else {
            bigHUDState.isPreviewLoading = true
            bigHUDState.outcome = .preview(item)
            // Surface provider / model / action title so the HUD preview pane
            // can show "Anthropic claude-sonnet-4-6 · 4.2s" instead of an
            // opaque spinner. Tick timer drives `aiElapsed` until the call
            // returns.
            bigHUDState.aiInflight = makeAIInflight(for: action)
            bigHUDState.aiElapsed = 0
            startAITickTimer()
            // Stream the response. The `onPartial` closure runs on the
            // main actor for each accumulated chunk; the first chunk
            // flips `isPreviewLoading` off so the user sees content
            // appear in place of the spinner. `previewToken` guards
            // against stale chunks landing after the user navigated to
            // a different action.
            aiStreamingTask = Task {
                // 90 s watchdog — same defense as the direct-trigger
                // path. Provider keep-alive pings can defeat the
                // 15 s byte-idle timeout indefinitely; without this,
                // a leaked stream past message_stop would keep the
                // BigHUD's "thinking…" spinner ticking forever even
                // after the response was complete and the user was
                // just staring at a stale loading state. Cancellation
                // cascades into applyStreaming's catch block which
                // returns the accumulated partial as .preview, so the
                // user still gets whatever arrived.
                //
                // Detached (background priority) so the watchdog's
                // sleep can wake regardless of main-actor pressure
                // — same reasoning as actionHotkeyDidFire above.
                let watchdog = Task.detached(priority: .background) { [weak self] in
                    try? await Task.sleep(nanoseconds: 90_000_000_000)
                    guard !Task.isCancelled else { return }
                    // Inner `[weak self]` for Swift 6 Sendable
                    // capture rules — see actionHotkeyDidFire above.
                    await MainActor.run { [weak self] in
                        self?.aiStreamingTask?.cancel()
                    }
                }
                defer { watchdog.cancel() }

                let outcome = await action.applyStreaming(
                    item: item,
                    context: ctx,
                    onPartial: { [weak self] partial in
                        guard let self = self else { return }
                        if myToken == self.previewToken {
                            self.bigHUDState.outcome = .preview(partial)
                            self.bigHUDState.isPreviewLoading = false
                        }
                    }
                )
                await MainActor.run {
                    if myToken == self.previewToken {
                        self.bigHUDState.outcome = outcome
                        self.bigHUDState.isPreviewLoading = false
                        self.stopAITickTimer()
                        self.bigHUDState.aiInflight = nil
                    }
                    // Deferred-paste path. If the user released ⌥⌘ while
                    // this stream was still loading, `commitBigHUD` left
                    // `pendingDeferredPasteApp` set, took down HUD chrome,
                    // and promoted ProgressHUD as the in-flight indicator.
                    // Now that the AI is done, fire the paste against that
                    // app. This runs INDEPENDENTLY of previewToken — the
                    // user pressed a hotkey and the result owes them a
                    // paste, even if they navigated away mid-stream.
                    if let target = self.pendingDeferredPasteApp {
                        self.pendingDeferredPasteApp = nil
                        MiniHUDController.shared.hide()
                        self.commitOutcome(outcome, savedApp: target)
                    }
                }
            }
        }
    }

    /// Resolves the AI provider / model labels for the in-progress action so
    /// the HUD preview pane can render a transparent "thinking…" panel.
    /// Returns nil for non-AI actions (which take the generic "processing…"
    /// path), or for AI actions whose configured provider is missing.
    @MainActor
    private func makeAIInflight(for action: ClipboardAction) -> AIInflight? {
        // Both AIAction (text) and AIImageAction (image) drive the
        // "Provider · Model · 4.2s" HUD chrome. Extract the per-action
        // provider override (if any) — both store it as `providerID:
        // String?` with the same "nil/empty means follow default"
        // semantics. Without the AIImageAction arm, image actions
        // hit the generic "processing…" loading panel because
        // bigHUDState.aiInflight stays nil — matches the bug the user
        // reported ("вижу processing и спинер" instead of provider
        // chrome).
        let explicitID: String?
        let isImageish: Bool
        if let ai = action as? AIAction {
            explicitID = ai.providerID
            isImageish = false
        } else if let ai = action as? AIImageAction {
            explicitID = ai.providerID
            isImageish = true
        } else if let ai = action as? AITextToImageAction {
            explicitID = ai.providerID
            isImageish = true
        } else {
            return nil
        }
        let cfg = AIProviderRegistry.shared.config
        // Mirror the runtime resolveProvider chain so the chrome
        // doesn't lie about which provider actually runs the
        // request. For image actions specifically, the chat default
        // may be non-image-capable (Anthropic etc.) — runtime then
        // soft-falls back to OpenAI / Gemini / OpenRouter — and the
        // inflight label has to reflect THAT, not the chat default.
        let cp: ConfiguredProvider? = {
            if let id = explicitID, !id.isEmpty,
               let p = cfg.providers.first(where: { $0.id == id }),
               p.enabled,
               (!isImageish || p.kind.supportsImageEdit) {
                return p
            }
            if let defaultID = cfg.defaultProviderID,
               let p = cfg.providers.first(where: { $0.id == defaultID }),
               p.enabled,
               (!isImageish || p.kind.supportsImageEdit) {
                return p
            }
            if isImageish {
                // Cheapest-first (Gemini → OpenRouter → OpenAI →
                // Custom). Same ranking the runtime uses, so the
                // HUD chrome surfaces the worker that's actually
                // about to fire instead of a stale registry-order
                // pick.
                return AIProviderRegistry.shared.cheapestEnabledImageProvider()
            }
            return cfg.providers.first { $0.enabled }
        }()
        guard let cp = cp else {
            return AIInflight(providerLabel: "AI",
                              modelName: "unknown",
                              actionTitle: action.title,
                              startedAt: Date())
        }
        // For image actions the actual on-the-wire model is the
        // image endpoint (gpt-image-1 for OpenAI, gemini-2.5-flash-
        // image-preview for Gemini, etc.) — not the configured chat
        // model. Surface the actual model so the chrome doesn't lie.
        let modelLabel: String = isImageish
            ? (cp.kind == .gemini ? "gemini-2.5-flash-image-preview" : "gpt-image-1")
            : cp.model
        return AIInflight(providerLabel: cp.displayName,
                          modelName: modelLabel,
                          actionTitle: action.title,
                          startedAt: Date())
    }

    /// Starts a 10 Hz timer that refreshes `bigHUDState.aiElapsed` while an AI
    /// request is in flight. Stopped via `stopAITickTimer()` when the response
    /// arrives, the user navigates away, or the HUD closes.
    @MainActor
    private func startAITickTimer() {
        stopAITickTimer()
        let started = bigHUDState.aiInflight?.startedAt ?? Date()
        aiTickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.bigHUDState.aiElapsed = Date().timeIntervalSince(started)
            }
        }
    }

    @MainActor
    private func stopAITickTimer() {
        aiTickTimer?.invalidate()
        aiTickTimer = nil
    }

    private func showBigHUD() {
        if bigHUDPanel == nil {
            // Provider closure for custom titles.
            bigHUDState.actionTitleProvider = { [weak self] (id, defaultTitle) in
                self?.registry.displayTitle(forActionID: id, defaultTitle: defaultTitle) ?? defaultTitle
            }
            let view = BigHUDView(
                state: bigHUDState,
                onPick: { [weak self] itemIdx, actionIdx in
                    guard let self = self else { return }
                    let itemChanged = itemIdx != self.bigHUDState.itemIndex
                    self.bigHUDState.itemIndex = itemIdx
                    self.bigHUDState.actionIndex = actionIdx
                    self.refreshPreview()
                    if itemChanged { self.updateContentMeta() }
                },
                onCommit: { [weak self] in self?.commitBigHUD() },
                onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
                onRecoveryAction: { [weak self] rec in self?.performRecovery(rec) },
                onClose: { [weak self] in self?.closeBigHUD() }   // HUD close button
            )
            let allowsKey = engine.bigHUDMode == .summon
            let host = BigHUDHostingView(rootView: view)
            let frame = NSRect(x: 0, y: 0, width: 720, height: allowsKey ? 440 : 400)
            let panel = BigHUDPanel(contentRect: frame, allowsKey: allowsKey)
            panel.contentView = host
            bigHUDPanel = panel
        }
        guard let panel = bigHUDPanel else { return }
        centerOnActiveScreen(panel)
        bigHUDShowSession &+= 1
        let session = bigHUDShowSession
        if engine.bigHUDMode == .summon {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFrontRegardless()
        }
        // Verify visibility after a short delay and retry the show if
        // window-server raced our orderFront. Critical: only re-assert
        // visibility when the show is STILL the active one. Without
        // the session check, a fast-tap sequence could fire the retry
        // after commitBigHUD / deferPasteAfterAILoad already
        // orderOut'd the panel — the retry would resurrect the BigHUD
        // on top of the deferred-paste MiniHUD, producing the
        // "2 HUDs at once" the user reports. Session counter bumps on
        // every show; closeBigHUD / deferPasteAfterAILoad bump it
        // too via `cancelBigHUDShowRetry()` so any pending retry
        // sees a stale session and bails.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            guard session == self.bigHUDShowSession else { return }
            if let p = self.bigHUDPanel, !p.isVisible {
                NSLog("DrPaste: HUD did not become visible, retry")
                if self.engine.bigHUDMode == .summon {
                    p.makeKeyAndOrderFront(nil)
                } else {
                    p.orderFrontRegardless()
                }
            }
        }
    }

    /// Bump the session counter so any pending `showBigHUD` retry
    /// captured before this call sees a stale session and skips its
    /// re-assert. Called from teardown paths (`closeBigHUD`,
    /// `deferPasteAfterAILoad`) so a freshly-orderOut'd panel doesn't
    /// get resurrected by a late retry.
    private func cancelBigHUDShowRetry() {
        bigHUDShowSession &+= 1
    }

    private func centerOnActiveScreen(_ panel: NSPanel) {
        // Multi-monitor: pick the screen containing the mouse cursor, not
        // NSScreen.main. NSScreen.main returns "screen with the focused
        // key window" — fine in Gesture Mode (DrPaste never grabs focus),
        // but in Limited Mode we call NSApp.activate(ignoringOtherApps:),
        // which can shift NSScreen.main onto whichever screen our prior
        // window was on. The cursor's screen is a stable proxy for "where
        // the user is actually working right now" across both modes.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
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
            // Close the HUD and open Settings → AI tab.
            closeBigHUD()
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
                // Limited Mode: ⏎ pastes the focused outcome and
                // closes the HUD. Paste-and-keep is intentionally a
                // Gesture-Mode-only chord — in Limited Mode the
                // user is already in HUD-key-window-with-no-held-
                // modifiers, so chaining pastes works fine via the
                // normal re-summon flow (and exposes a simpler
                // mental model for the legend).
                self.commitBigHUD()
                return nil
            case kVK_Escape:
                self.closeBigHUD(); return nil
            case kVK_Delete:                       // Backspace deletes the focused item in Limited Mode
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
                    self.bigHUDState.adjustFontScale(.bigger); return nil
                case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
                    self.bigHUDState.adjustFontScale(.smaller); return nil
                case kVK_ANSI_0, kVK_ANSI_Keypad0:
                    self.bigHUDState.adjustFontScale(.reset); return nil
                default: break
                }
            }
            // S / ⌥⌘S in HUD — drive the walking clip accumulator.
            // In Limited Mode the user isn't holding any modifiers (the HUD
            // is a regular key window), so bare S works in addition to the
            // chord version — keeps the footer legend in sync with Gesture
            // Mode and removes one mental step for "merge this row".
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isBare = mods.intersection([.command, .option, .control, .shift]).isEmpty
            let isOptCmd = mods.contains(.command) && mods.contains(.option)
            if kc == kVK_ANSI_S, (isBare || isOptCmd) {
                self.hotkeyEngineDidRequestHUDAccumulate()
                return nil
            }
            // C / ⌥⌘C in HUD — promote the current preview to a new
            // top-of-history clip + copy to system pasteboard. Bare C
            // works in Limited Mode (no held modifiers, HUD is key
            // window) so the legend can read just "C copy"; ⌥⌘C
            // works too for muscle-memory continuity with the
            // Gesture-Mode flow and for keyboards where the bare
            // letter would type into a text field overlay.
            if kc == kVK_ANSI_C, (isBare || isOptCmd) {
                self.hotkeyEngineDidRequestPromotePreview()
                return nil
            }
            // (No bare / ⌥⌘ Space handler — was the original
            // promote-preview chord during the v0.32 series, replaced
            // by C in v0.35. Alpha hasn't shipped, no need to keep
            // the legacy binding.)
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
