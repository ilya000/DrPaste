//
//  ActionHotkey.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Per-action hotkeys. The user assigns a global shortcut to any action; when
//  pressed, the action runs against the current clipboard content without
//  opening the HUD and the result is pasted into the frontmost app.
//

import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey descriptor

struct ActionHotkey: Codable, Equatable, Hashable {
    var keyCode: UInt16          // CGKeyCode (typed as UInt16 for Codable)
    var modifiers: UInt32        // Bitmask of Carbon constants: cmd / opt / ctrl / shift

    /// Human-readable string, e.g. "⌃⌘P".
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += KeyName.from(keyCode: keyCode)
        return s
    }

    /// True if this combination collides with one of DrPaste's reserved
    /// main hotkeys (⌥⌘V/C/X/S) or in-HUD chords (⌥⌘⏎). User actions
    /// must not steal these because they're hard-wired in the engine
    /// and would never fire if the action were trying to claim them.
    var conflictsWithMainHotkeys: Bool {
        drPasteReservedName != nil
    }

    /// Human-readable name of the DrPaste feature that owns this
    /// combination, or nil if the combo is free of internal
    /// conflict. Used by the recorder so the rejection message
    /// can say WHICH feature owns the chord instead of just
    /// listing every reserved letter.
    var drPasteReservedName: String? {
        guard isOptCmdOnly else { return nil }
        switch Int(keyCode) {
        case kVK_ANSI_V:                       return "Open BigHUD"
        case kVK_ANSI_C:                       return "Quick Copy"
        case kVK_ANSI_X:                       return "Cut & Replace"
        case kVK_ANSI_S:                       return "Append Copy"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "Paste & Keep HUD"
        default:                               return nil
        }
    }

    /// Human-readable name of the macOS system shortcut that owns
    /// this combination, or nil if the combo is free. Used by the
    /// hotkey recorder to refuse a binding that would silently
    /// fight the OS for the same chord (e.g. ⌥⌘Q = Log Out User,
    /// ⌥⌘D = Show/Hide Dock — even though DrPaste's EventTap sits
    /// in front of Carbon and "wins" the keystroke, the system
    /// menu / Dock target still flickers because lower layers
    /// process the event before our nil-return propagates).
    ///
    /// Scope is deliberately narrow: only chords that macOS itself
    /// hard-wires at the OS level. App-specific defaults (⌘S Save,
    /// ⌘Q Quit, ⌘N New) are NOT here — those are owned by the
    /// frontmost app and DrPaste can legitimately intercept them
    /// before the app sees them, so blocking would be too
    /// paternalistic.
    var systemHotkeyName: String? {
        // ⌥⌘ chord — the most common collision space for user
        // hotkeys (every macOS install ships with several here).
        // Labels match the Apple menu / Finder menu wording the
        // user sees natively, so they recognise the conflict
        // immediately. Verified against Apple's published
        // keyboard-shortcuts list, not guessed.
        if isOptCmdOnly {
            switch Int(keyCode) {
            case kVK_ANSI_Q:     return "Force Quit"
            case kVK_ANSI_D:     return "Show or Hide the Dock"
            case kVK_ANSI_M:     return "Minimize All Windows"
            case kVK_ANSI_H:     return "Hide Others"
            case kVK_ANSI_L:     return "Go to Downloads (Finder)"
            case kVK_ANSI_N:     return "New Smart Folder (Finder)"
            // ⌥⌘O in Finder: Open the selected item and close the
            // current Finder window. Was mislabeled "Open With…"
            // — that's plain ⌘O / right-click → Open With.
            case kVK_ANSI_O:     return "Open & Close Finder Window"
            case kVK_ANSI_P:     return "Show or Hide the Path Bar (Finder)"
            case kVK_ANSI_T:     return "Show or Hide the Toolbar (Finder)"
            // ⌥⌘Space opens the Finder search window. The plain
            // Spotlight shortcut is ⌘Space — different chord.
            case kVK_Space:      return "Show Finder Search Window"
            default:             break
            }
        }
        return nil
    }

    /// True if this combo uses EXACTLY ⌥⌘ with no other modifiers — the
    /// only combo eligible for the BigHUD hold-preview synergy (#A10).
    /// Hotkeys with any other modifier set (⌃⇧X, fn+letter, ⌘ alone, …)
    /// run as pure direct-trigger because the gesture "keep ⌥⌘ held to
    /// preview" only composes when ⌥⌘ is what's already pressed.
    var isOptCmdOnly: Bool {
        modifiers == (UInt32(optionKey) | UInt32(cmdKey))
    }

    /// Display name of the key portion only (no modifier glyphs). Used
    /// in HUD-support hint messages that need to refer to just the
    /// letter the user picked, e.g. "hold ⌥⌘ after pressing T".
    var keyDisplayName: String {
        KeyName.from(keyCode: keyCode)
    }
}

/// Maps a keyCode to a display name used in the UI.
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

// MARK: - Manager — registers Carbon hotkeys and routes them to ActionRegistry

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

    /// Reregister all hotkeys from ActionConfig.
    /// Skips actions whose descriptor is disabled — disabled actions remain
    /// visible in Settings (greyed) but do not respond to their direct-trigger
    /// hotkey. Mirrors how `ActionRegistry.applicable(for:context:)` filters
    /// disabled actions out of the HUD list.
    func reload() {
        unregisterAll()
        guard let registry = registry else { return }
        let cfg = registry.config
        for (actionID, hotkey) in cfg.actionHotkeys {
            guard !hotkey.conflictsWithMainHotkeys else { continue }
            guard registry.isEnabled(actionID) else { continue }
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

    /// Unregister every per-action hotkey so the Settings hotkey
    /// recorder can capture ⌥⌘<letter> chords without Carbon firing
    /// the bound action first. Re-registered by `resumeFromRecording()`.
    func pauseForRecording() {
        unregisterAll()
    }

    /// Re-register every per-action hotkey from current config. Pairs
    /// with `pauseForRecording()`. Safe to call multiple times — relies
    /// on `unregisterAll()` inside `reload()` for idempotency.
    func resumeFromRecording() {
        reload()
    }
}

protocol ActionHotkeyManagerDelegate: AnyObject {
    @MainActor func actionHotkeyDidFire(actionID: String)
}
