//
//  PasteSimulator.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Simulates ⌘V / ⌘C / ⌘X in the foreground app.
//  - Physically held Option is briefly released so the synthetic shortcut is a
//    clean ⌘X / ⌘C and not ⌥⌘X / ⌥⌘C.
//  - Every synthetic event is tagged with DrPasteSyntheticMarker so the
//    EventTap ignores them and avoids recursion.
//  Includes NSPasteboard writers that restore every representation losslessly.
//

import AppKit
import Carbon.HIToolbox

enum PasteSimulator {
    static func simulatePaste() { postShortcut(keyCode: kVK_ANSI_V) }
    static func simulateCopy()  { postShortcut(keyCode: kVK_ANSI_C) }
    static func simulateCut()   { postShortcut(keyCode: kVK_ANSI_X) }

    /// Paste-and-keep variant for ⌥⌘⏎ in BigHUD. The user is still
    /// physically holding ⌥⌘ during this chord — we need the target
    /// app to see a clean ⌘V, not ⌥⌘V (which is DrPaste's summon
    /// hotkey and would bounce focus right back to DrPaste).
    ///
    /// Three differences from the normal `simulatePaste()` recipe:
    ///
    ///   1. Source stateID is `.privateState`, NOT
    ///      `.combinedSessionState`. CombinedSessionState makes the
    ///      OS bake the current HID modifier flags into every event
    ///      the source produces — so even after we set
    ///      `event.flags = .maskCommand`, the source's snapshot of
    ///      "Option is held right now" leaks back in and the target
    ///      sees ⌥⌘V. PrivateState produces events with no implicit
    ///      modifier state; our explicit `.maskCommand` is then the
    ///      only flag set.
    ///
    ///   2. Post location is `.cgAnnotatedSessionEventTap`, NOT
    ///      `.cghidEventTap`. HID re-applies real-keyboard modifier
    ///      state to every event passing through it, defeating step
    ///      1. The annotated session tap is far enough up the stack
    ///      that HID has nothing more to add.
    ///
    ///   3. No Option lift/restore. It's unreliable against
    ///      hardware-held modifiers (the OS reads modifier state
    ///      from HID hardware, not from our synthetic flagsChanged
    ///      events), and the synthetic Option keyUp would otherwise
    ///      look like a real release to the gesture engine and tear
    ///      down the HUD — defeating the whole point of "keep open".
    static func simulatePasteKeepingHeldModifiers() {
        guard let src = CGEventSource(stateID: .privateState) else {
            // Source allocation should never fail, but fall back to
            // the regular path so the user at least gets something.
            postShortcut(keyCode: kVK_ANSI_V)
            return
        }
        let loc = CGEventTapLocation.cgAnnotatedSessionEventTap
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        // Mark both events so our own EventTap engine doesn't
        // re-interpret them as a user-initiated ⌥⌘V summon — even
        // though we sanitized flags, the marker is belt-and-braces.
        for ev in [keyDown, keyUp] {
            ev?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
        }
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }

    private static func postShortcut(keyCode: Int,
                                     via loc: CGEventTapLocation = .cghidEventTap,
                                     liftOption: Bool = true) {
        let src = CGEventSource(stateID: .combinedSessionState)

        // Check the physical Option modifier — if it is held, lift it
        // programmatically before posting the synthetic shortcut so the target
        // app sees a clean ⌘X / ⌘C rather than ⌥⌘X / ⌥⌘C.
        let optionHeld = liftOption && NSEvent.modifierFlags.contains(.option)
        if optionHeld {
            let optUp = CGEvent(keyboardEventSource: src,
                                virtualKey: CGKeyCode(kVK_Option),
                                keyDown: false)
            optUp?.flags = []
            optUp?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
            optUp?.post(tap: loc)
            // 5 ms settling
            Thread.sleep(forTimeInterval: 0.005)
        }

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        cmdDown?.flags = .maskCommand
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)
        keyUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)

        // Tag every synthetic event so the EventTap does not re-process them.
        for ev in [cmdDown, keyDown, keyUp, cmdUp] {
            ev?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
        }

        cmdDown?.post(tap: loc)
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
        cmdUp?.post(tap: loc)

        // Restore Option if it was held before.
        if optionHeld {
            Thread.sleep(forTimeInterval: 0.005)
            let optDown = CGEvent(keyboardEventSource: src,
                                  virtualKey: CGKeyCode(kVK_Option),
                                  keyDown: true)
            optDown?.flags = .maskAlternate
            optDown?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
            optDown?.post(tap: loc)
        }
    }

    /// Simulate ⌘C against the frontmost app and poll the system
    /// pasteboard for a change. Returns `true` if a new selection
    /// landed within `timeout`, `false` on timeout (nothing was
    /// selected or the frontmost app ignored the ⌘C). 250 ms covers
    /// every well-behaved app the team has tested; longer values
    /// trade UI latency for compatibility with slow hosts (Java apps,
    /// remote terminals, Electron with heavy DOM).
    ///
    /// Used by every selection-first hotkey path — Quick Copy
    /// (⌥⌘C), Append Copy (⌥⌘S), per-action direct trigger, and
    /// per-action hold-preview. Previously each of those sites
    /// inlined the simulate-and-poll dance; the helper eliminates
    /// the duplication and gives all four paths a single timing
    /// model to maintain.
    ///
    /// **Timeout chosen at 0.40 s** (raised from 0.25 s in 0.42.2).
    /// On Electron / Java / Office / Remote Desktop apps the ⌘C
    /// round-trip occasionally takes 250–350 ms — large rich-text
    /// or image selections cross that threshold reliably. The
    /// earlier 0.25 s budget produced false "selection capture
    /// failed" outcomes on per-action hotkeys and Append Copy in
    /// those apps; the loop still exits the moment `changeCount`
    /// ticks, so fast-path latency on native apps stays at one
    /// poll interval (~20 ms). Logging on timeout includes the
    /// frontmost app's bundleID so problem apps are diagnosable.
    @MainActor
    static func simulateCopyAndAwaitChange(timeout: TimeInterval = 0.40) async -> Bool {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        simulateCopy()
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount > before { return true }
        }
        // Selection capture timed out — log the frontmost app so
        // repeated failures with one specific app can be diagnosed.
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        NSLog("DrPaste: simulateCopyAndAwaitChange timed out after %.2fs (frontmost: %@)",
              timeout, frontBundleID)
        return false
    }
}

// MARK: - PasteboardWriter (lossless restoration)

enum PasteboardWriter {
    static func readableRepresentations(
        for item: ClipboardItem,
        store: ClipboardStore
    ) -> (entries: [(type: String, data: Data)], missingCount: Int) {
        var readableData: [(type: String, data: Data)] = []
        var missingCount = 0
        for typeStr in item.typesOrdered {
            guard let rel = item.representations[typeStr] else { continue }
            let url = store.blobURL(rel)
            if let data = try? Data(contentsOf: url) {
                readableData.append((type: typeStr, data: data))
            } else {
                missingCount += 1
            }
        }
        return (readableData, missingCount)
    }

    /// Restores every representation of a clipboard item. This is Paste-as-is:
    /// if the item was copied from Excel, all of its representations (TSV,
    /// HTML, RTF, proprietary metadata) are written back to the pasteboard in
    /// the original priority order.
    static func write(_ item: ClipboardItem, store: ClipboardStore) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // If a full raw snapshot is available, restore losslessly.
        // CRITICAL: declare only the types we can actually read back
        // from disk. The earlier code declared every type in
        // `typesOrdered` and then silently skipped the `setData` call
        // for any missing / unreadable blob. Result: the pasteboard
        // claimed e.g. "I have public.tiff" but had no bytes for it,
        // so receiving apps that preferred .tiff over .string got an
        // empty image and the user's text-only paste flow produced
        // a broken paste. Two-pass: read all blobs into memory first,
        // declare only types whose blob loaded, then write the data.
        if !item.representations.isEmpty && !item.typesOrdered.isEmpty {
            let result = readableRepresentations(for: item, store: store)
            let readableData = result.entries
            let missingCount = result.missingCount
            if !readableData.isEmpty {
                let types = readableData.map { NSPasteboard.PasteboardType($0.type) }
                pb.declareTypes(types, owner: nil)
                for entry in readableData {
                    pb.setData(entry.data,
                               forType: NSPasteboard.PasteboardType(entry.type))
                }
                if missingCount > 0 {
                    NSLog("DrPaste: PasteboardWriter skipped %d missing blob(s) for clip id=%@",
                          missingCount, item.id.uuidString)
                }
                return
            }
            // Every representation failed to load. Fall through to the
            // preview-only path so the user at least gets the rendered
            // text / image, not an empty pasteboard.
            NSLog("DrPaste: PasteboardWriter — all %d representations missing for clip id=%@; falling back to preview",
                  item.typesOrdered.count, item.id.uuidString)
        }

        // Fallback path: write back from previewText / previewImageRel. Used
        // for transformed items where we created item.previewText without
        // preserving the original representations (for example after JSON pretty),
        // OR as a recovery when all blobs were missing above.
        if let text = item.previewText, !text.isEmpty {
            pb.setString(text, forType: .string)
        }
        if let rel = item.previewImageRel {
            let url = AppStorage.imagesDir.appendingPathComponent(rel)
            if let img = NSImage(contentsOf: url),
               let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
    }
}
