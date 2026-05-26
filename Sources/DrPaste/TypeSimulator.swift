//
//  TypeSimulator.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Type Slowly (Backlog #7). Печатает текст символ за символом через
//  CGEvent.keyboardSetUnicodeString с задержкой. Обходит paste-block
//  в банковских формах и других input fields с onpaste=false.
//

import AppKit
import Carbon.HIToolbox

enum TypeSimulator {
    /// Печатает строку символ за символом. Каждый символ — отдельный keyDown/keyUp event.
    /// Cancellation closure проверяется перед каждым символом.
    /// onProgress(current, total) вызывается после каждого символа.
    static func typeSlowly(_ text: String,
                           baseDelay: TimeInterval = 0.2,
                           jitter: Double = 0.2,
                           cancellation: @escaping () -> Bool = { false },
                           onProgress: @escaping (Int, Int) -> Void = { _, _ in },
                           completion: @escaping () -> Void = {}) {
        let chars = Array(text)
        let total = chars.count
        let source = CGEventSource(stateID: .combinedSessionState)

        Task.detached {
            for (idx, ch) in chars.enumerated() {
                if cancellation() {
                    await MainActor.run { completion() }
                    return
                }

                switch ch {
                case "\n":
                    postKey(source: source, keyCode: CGKeyCode(kVK_Return))
                case "\t":
                    postKey(source: source, keyCode: CGKeyCode(kVK_Tab))
                default:
                    postUnicode(source: source, character: ch)
                }

                await MainActor.run {
                    onProgress(idx + 1, total)
                    SoundFeedback.play(.typeTick)
                }

                let factor = 1.0 + Double.random(in: -jitter...jitter)
                let delay = baseDelay * factor
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await MainActor.run { completion() }
        }
    }

    private static func postUnicode(source: CGEventSource?, character: Character) {
        let utf16 = Array(String(character).utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        utf16.withUnsafeBufferPointer { ptr in
            down?.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
            up?.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postKey(source: CGEventSource?, keyCode: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: - Type Slowly action (Backlog #7)

struct TypeSlowlyAction: ClipboardAction {
    let id = "builtin.type_slowly"
    let title = "Type Slowly (bypass paste-block)"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard context.contains(.plain) else { return false }
        guard let text = item.previewText else { return false }
        return text.count > 0 && text.count <= 500
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard AXIsProcessTrusted() else {
            return .failed(original: item,
                          reason: "Type Slowly requires Accessibility permission",
                          recovery: .openAccessibilitySettings)
        }
        let plain = makePlainText(item)
        return .alternativeCommit(plain, style: .typeSlowly(delay: 0.2, jitter: 0.2))
    }
}
