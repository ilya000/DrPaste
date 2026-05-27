//
//  PasteSimulator.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Имитация ⌘V / ⌘C / ⌘X в активном приложении (Backlog #9 + Правка #16):
//  - физический ⌥ "приподнимается" чтобы synthetic был чистым ⌘X не ⌥⌘X
//  - все наши events помечаются DrPasteSyntheticMarker → EventTap игнорирует recursion
//  Plus writers в NSPasteboard с восстановлением всех representations (Backlog #1).
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

        // Правка #16 слой 1: проверяем физическое состояние ⌥ — если зажат,
        // programmatically up'аем его перед synthetic ⌘X, чтобы app видел
        // чистый ⌘X не ⌥⌘X (важно для cut/copy через ⌥⌘X / ⌥⌘C).
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

        // Слой 2: пометить все наши synthetic чтобы EventTap не recursively обработал.
        for ev in [cmdDown, keyDown, keyUp, cmdUp] {
            ev?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
        }

        cmdDown?.post(tap: loc)
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
        cmdUp?.post(tap: loc)

        // Восстановить ⌥ если был up'нут.
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
}

// MARK: - PasteboardWriter (Backlog #1 — lossless restoration)

enum PasteboardWriter {
    /// Восстанавливает ВСЕ representations clipboard item.
    /// Это Paste-as-is: если item был скопирован из Excel — все его representations
    /// (TSV, HTML, RTF, proprietary metadata) попадают обратно в pasteboard
    /// в исходном порядке приоритета.
    static func write(_ item: ClipboardItem, store: ClipboardStore) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // Если у нас есть полный raw snapshot — восстанавливаем lossless
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

        // Fallback: writeback из previewText / previewImageRel
        // (используется для transformed items — например после JSON pretty
        // мы создали item.previewText без representations).
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
