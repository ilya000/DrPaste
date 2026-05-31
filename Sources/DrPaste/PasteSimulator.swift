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

    private static func postShortcut(keyCode: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let loc = CGEventTapLocation.cghidEventTap

        // Check the physical Option modifier — if it is held, lift it
        // programmatically before posting the synthetic shortcut so the target
        // app sees a clean ⌘X / ⌘C rather than ⌥⌘X / ⌥⌘C.
        let optionHeld = NSEvent.modifierFlags.contains(.option)
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
    @MainActor
    static func simulateCopyAndAwaitChange(timeout: TimeInterval = 0.25) async -> Bool {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        simulateCopy()
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount > before { return true }
        }
        return false
    }
}

// MARK: - PasteboardWriter (lossless restoration)

enum PasteboardWriter {
    /// Restores every representation of a clipboard item. This is Paste-as-is:
    /// if the item was copied from Excel, all of its representations (TSV,
    /// HTML, RTF, proprietary metadata) are written back to the pasteboard in
    /// the original priority order.
    static func write(_ item: ClipboardItem, store: ClipboardStore) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // If a full raw snapshot is available, restore losslessly.
        if !item.representations.isEmpty && !item.typesOrdered.isEmpty {
            let types = item.typesOrdered.map { NSPasteboard.PasteboardType($0) }
            pb.declareTypes(types, owner: nil)
            for typeStr in item.typesOrdered {
                guard let rel = item.representations[typeStr] else { continue }
                let url = store.blobURL(rel)
                guard let data = try? Data(contentsOf: url) else { continue }
                pb.setData(data, forType: NSPasteboard.PasteboardType(typeStr))
            }
            return
        }

        // Fallback path: write back from previewText / previewImageRel. Used
        // for transformed items where we created item.previewText without
        // preserving the original representations (for example after JSON pretty).
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
