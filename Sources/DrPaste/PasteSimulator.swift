//
//  PasteSimulator.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Имитация ⌘V / ⌘C / ⌘X в активном приложении (Backlog #9)
//  + writers в NSPasteboard с восстановлением всех representations (Backlog #1).
//

import AppKit
import Carbon.HIToolbox

enum PasteSimulator {
    static func simulatePaste() { postShortcut(keyCode: kVK_ANSI_V) }
    static func simulateCopy()  { postShortcut(keyCode: kVK_ANSI_C) }
    static func simulateCut()   { postShortcut(keyCode: kVK_ANSI_X) }

    private static func postShortcut(keyCode: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        cmdDown?.flags = .maskCommand
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)
        keyUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        let loc = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: loc)
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
        cmdUp?.post(tap: loc)
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
