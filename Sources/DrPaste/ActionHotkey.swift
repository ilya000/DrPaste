//
//  ActionHotkey.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Per-action hotkeys (0.6.0): пользователь назначает горячую клавишу
//  любому action — при нажатии action применяется к текущему clipboard
//  content без открытия HUD, результат вставляется в frontmost app.
//

import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey descriptor

struct ActionHotkey: Codable, Equatable, Hashable {
    var keyCode: UInt16          // CGKeyCode (как UInt16 для Codable)
    var modifiers: UInt32        // битовая маска: cmd / opt / ctrl / shift (Carbon constants)

    /// Human-readable строка (например "⌃⌘P")
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += KeyName.from(keyCode: keyCode)
        return s
    }

    /// Конфликтует с зарезервированными hotkey'ями DrPaste (⌥⌘V/C/X)?
    var conflictsWithMainHotkeys: Bool {
        let isOptCmd = modifiers == (UInt32(optionKey) | UInt32(cmdKey))
        guard isOptCmd else { return false }
        switch Int(keyCode) {
        case kVK_ANSI_V, kVK_ANSI_C, kVK_ANSI_X: return true
        default: return false
        }
    }
}

/// Преобразование keyCode → название клавиши для UI.
enum KeyName {
    static func from(keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Grave: return "`"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "?"
        }
    }
}

// MARK: - Manager — регистрирует Carbon hotkeys и роутит на ActionRegistry

@MainActor
final class ActionHotkeyManager: ObservableObject {
    static let shared = ActionHotkeyManager()

    private var refs: [String: EventHotKeyRef] = [:]    // actionID → ref
    private var idMap: [UInt32: String] = [:]            // carbon hkID → actionID
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x44524841             // 'DRHA' = DrPaste Hotkey Action
    private var nextID: UInt32 = 100

    weak var registry: ActionRegistry?
    weak var delegate: ActionHotkeyManagerDelegate?

    private init() {}

    func install() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let mgr = Unmanaged<ActionHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard hkID.signature == mgr.signature else { return noErr }
            DispatchQueue.main.async {
                if let actionID = mgr.idMap[hkID.id] {
                    mgr.delegate?.actionHotkeyDidFire(actionID: actionID)
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// Перерегистрировать все hotkeys из ActionConfig.
    func reload() {
        unregisterAll()
        guard let cfg = registry?.config else { return }
        for (actionID, hotkey) in cfg.actionHotkeys {
            guard !hotkey.conflictsWithMainHotkeys else { continue }
            register(actionID: actionID, hotkey: hotkey)
        }
    }

    private func register(actionID: String, hotkey: ActionHotkey) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.modifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref = ref {
            refs[actionID] = ref
            idMap[id] = actionID
        }
    }

    private func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        idMap.removeAll()
    }
}

protocol ActionHotkeyManagerDelegate: AnyObject {
    @MainActor func actionHotkeyDidFire(actionID: String)
}
