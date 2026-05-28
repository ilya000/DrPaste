//
//  HotkeyEngine.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Three main hotkeys: ⌥⌘V paste (with press-and-hold), ⌥⌘C Quick Copy,
//  ⌥⌘X Cut & Replace. Three engine implementations:
//  EventTap (Full Gesture mode), Carbon (Limited mode), GlobalMonitor (debug).
//

import AppKit
import CoreGraphics
import Carbon.HIToolbox

// MARK: - Config, enums

struct HotkeyConfig {
    let pasteKeyCode: CGKeyCode      // V
    let copyKeyCode: CGKeyCode       // C
    let cutKeyCode: CGKeyCode        // X
    let appendKeyCode: CGKeyCode     // S — Sum/Append Copy (#12)
    let modifiers: CGEventFlags      // ⌥⌘

    static let `default` = HotkeyConfig(
        pasteKeyCode: CGKeyCode(kVK_ANSI_V),
        copyKeyCode: CGKeyCode(kVK_ANSI_C),
        cutKeyCode: CGKeyCode(kVK_ANSI_X),
        appendKeyCode: CGKeyCode(kVK_ANSI_S),
        modifiers: [.maskCommand, .maskAlternate]
    )
}

enum NavDirection { case up, down, left, right }

enum FontChange { case bigger, smaller, reset }

enum SummonReason {
    case paste              // ⌥⌘V — standard HUD flow.
    case cutAndReplace      // ⌥⌘X — simulated ⌘X first, then HUD, replace on commit.
}

enum HotkeyEngineKind: String {
    case eventTap = "tap"
    case carbon   = "carbon"
    case monitor  = "monitor"
}

enum HudMode {
    case gesture   // Full: non-activating, release-to-commit
    case summon    // Limited: key window, Enter/click-to-commit
}

protocol HotkeyEngineDelegate: AnyObject {
    func hotkeyEngineDidSummon(reason: SummonReason)
    func hotkeyEngineDidRelease()
    func hotkeyEngineDidNavigate(_ direction: NavDirection)
    func hotkeyEngineDidCancel()
    func hotkeyEngineDidRequestFontChange(_ change: FontChange)
    func hotkeyEngineDidQuickCopy()
    func hotkeyEngineDidDeleteFocused()
    func hotkeyEngineDidAppendCopy()
}

/// Marker for our own synthetic CGEvents — filters recursion when the engine
/// re-observes events it just posted. Written into .eventSourceUserData when
/// posting ⌘V/⌘X/⌘C.
let DrPasteSyntheticMarker: Int64 = 0x44525041535445  // "DRPASTE" ASCII

protocol HotkeyEngine: AnyObject {
    var delegate: HotkeyEngineDelegate? { get set }
    var config: HotkeyConfig { get }
    var kind: HotkeyEngineKind { get }
    var hudMode: HudMode { get }
    func start() -> Bool
    func stop()
}

// MARK: - EventTap engine

final class EventTapEngine: HotkeyEngine {
    weak var delegate: HotkeyEngineDelegate?
    let config: HotkeyConfig
    let kind: HotkeyEngineKind = .eventTap
    let hudMode: HudMode = .gesture

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hudIsActive: Bool = false

    init(config: HotkeyConfig) { self.config = config }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<EventTapEngine>.fromOpaque(refcon).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else { return false }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        self.runLoopSource = src
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        tap = nil; runLoopSource = nil; hudIsActive = false
    }

    /// Force-clears hudIsActive. Used as a watchdog in AppDelegate when the HUD
    /// failed to open in time.
    func resetHudActive() { hudIsActive = false }

    /// Current state — used for AppDelegate state-machine synchronization.
    var isHudActive: Bool { hudIsActive }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Skip our own synthetic events so the tap does not re-process them
        // (e.g. our synthetic ⌘X must not be interpreted as a user-initiated ⌥⌘X).
        if event.getIntegerValueField(.eventSourceUserData) == DrPasteSyntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let modsPresent = flags.contains(config.modifiers)

        if type == .keyDown {
            let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

            if hudIsActive {
                switch Int(kc) {
                case kVK_UpArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.up) }
                    return nil
                case kVK_DownArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.down) }
                    return nil
                case kVK_LeftArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.left) }
                    return nil
                case kVK_RightArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.right) }
                    return nil
                case kVK_Escape:
                    hudIsActive = false
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidCancel() }
                    return nil
                case kVK_Delete:           // Backspace deletes the focused history item.
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidDeleteFocused() }
                    return nil
                case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.bigger) }
                    return nil
                case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.smaller) }
                    return nil
                case kVK_ANSI_0, kVK_ANSI_Keypad0:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.reset) }
                    return nil
                default:
                    return nil
                }
            }

            // not active
            if modsPresent {
                if kc == config.pasteKeyCode {
                    hudIsActive = true
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .paste) }
                    return nil
                }
                if kc == config.cutKeyCode {
                    hudIsActive = true
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .cutAndReplace) }
                    return nil
                }
                if kc == config.copyKeyCode {
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidQuickCopy() }
                    return nil
                }
                if kc == config.appendKeyCode {
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidAppendCopy() }
                    return nil
                }
            }
        }

        if type == .flagsChanged && hudIsActive {
            if !modsPresent {
                hudIsActive = false
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRelease() }
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

// MARK: - Carbon engine (Limited Mode, no AX needed)

final class CarbonHotKeyEngine: HotkeyEngine {
    weak var delegate: HotkeyEngineDelegate?
    let config: HotkeyConfig
    let kind: HotkeyEngineKind = .carbon
    let hudMode: HudMode = .summon

    private var pasteRef: EventHotKeyRef?
    private var copyRef: EventHotKeyRef?
    private var cutRef: EventHotKeyRef?
    private var appendRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x44525053 // 'DRPS'

    init(config: HotkeyConfig) { self.config = config }

    func start() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let engine = Unmanaged<CarbonHotKeyEngine>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard hkID.signature == engine.signature else { return noErr }
            DispatchQueue.main.async {
                switch hkID.id {
                case 1: engine.delegate?.hotkeyEngineDidSummon(reason: .paste)
                case 2: engine.delegate?.hotkeyEngineDidQuickCopy()
                case 3: engine.delegate?.hotkeyEngineDidSummon(reason: .cutAndReplace)
                case 4: engine.delegate?.hotkeyEngineDidAppendCopy()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        guard status == noErr else { return false }

        let mods = carbonModifiers(from: config.modifiers)
        let pasteOK = RegisterEventHotKey(UInt32(config.pasteKeyCode), mods,
                                           EventHotKeyID(signature: signature, id: 1),
                                           GetApplicationEventTarget(), 0, &pasteRef) == noErr
        let copyOK = RegisterEventHotKey(UInt32(config.copyKeyCode), mods,
                                         EventHotKeyID(signature: signature, id: 2),
                                         GetApplicationEventTarget(), 0, &copyRef) == noErr
        let cutOK = RegisterEventHotKey(UInt32(config.cutKeyCode), mods,
                                        EventHotKeyID(signature: signature, id: 3),
                                        GetApplicationEventTarget(), 0, &cutRef) == noErr
        _ = RegisterEventHotKey(UInt32(config.appendKeyCode), mods,
                                EventHotKeyID(signature: signature, id: 4),
                                GetApplicationEventTarget(), 0, &appendRef)
        return pasteOK || copyOK || cutOK
    }

    func stop() {
        for ref in [pasteRef, copyRef, cutRef, appendRef] {
            if let r = ref { UnregisterEventHotKey(r) }
        }
        pasteRef = nil; copyRef = nil; cutRef = nil; appendRef = nil
        if let e = eventHandler { RemoveEventHandler(e); eventHandler = nil }
    }

    private func carbonModifiers(from cgFlags: CGEventFlags) -> UInt32 {
        var m: UInt32 = 0
        if cgFlags.contains(.maskCommand)   { m |= UInt32(cmdKey) }
        if cgFlags.contains(.maskAlternate) { m |= UInt32(optionKey) }
        if cgFlags.contains(.maskControl)   { m |= UInt32(controlKey) }
        if cgFlags.contains(.maskShift)     { m |= UInt32(shiftKey) }
        return m
    }
}

// MARK: - GlobalMonitor engine (debug only)

final class GlobalMonitorEngine: HotkeyEngine {
    weak var delegate: HotkeyEngineDelegate?
    let config: HotkeyConfig
    let kind: HotkeyEngineKind = .monitor
    let hudMode: HudMode = .gesture

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var hudIsActive: Bool = false

    init(config: HotkeyConfig) { self.config = config }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event)
        }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event)
        }
        return keyMonitor != nil && flagsMonitor != nil
    }

    func stop() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil; flagsMonitor = nil; hudIsActive = false
    }

    private func cgFlags(from ns: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if ns.contains(.command) { f.insert(.maskCommand) }
        if ns.contains(.option)  { f.insert(.maskAlternate) }
        if ns.contains(.control) { f.insert(.maskControl) }
        if ns.contains(.shift)   { f.insert(.maskShift) }
        return f
    }
    private func modsPresent(_ event: NSEvent) -> Bool {
        cgFlags(from: event.modifierFlags).contains(config.modifiers)
    }

    private func handleKey(_ event: NSEvent) {
        let kc = CGKeyCode(event.keyCode)
        if hudIsActive {
            switch Int(kc) {
            case kVK_UpArrow:    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.up) }
            case kVK_DownArrow:  DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.down) }
            case kVK_LeftArrow:  DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.left) }
            case kVK_RightArrow: DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.right) }
            case kVK_Escape:
                hudIsActive = false
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidCancel() }
            case kVK_Delete:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidDeleteFocused() }
            case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.bigger) }
            case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.smaller) }
            case kVK_ANSI_0, kVK_ANSI_Keypad0:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.reset) }
            default: break
            }
            return
        }
        if modsPresent(event) {
            if kc == config.pasteKeyCode {
                hudIsActive = true
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .paste) }
            } else if kc == config.cutKeyCode {
                hudIsActive = true
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .cutAndReplace) }
            } else if kc == config.copyKeyCode {
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidQuickCopy() }
            } else if kc == config.appendKeyCode {
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidAppendCopy() }
            }
        }
    }

    private func handleFlags(_ event: NSEvent) {
        guard hudIsActive else { return }
        if !modsPresent(event) {
            hudIsActive = false
            DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRelease() }
        }
    }
}

// MARK: - Factory

enum HotkeyEngineFactory {
    static func make(config: HotkeyConfig) -> HotkeyEngine {
        let env = ProcessInfo.processInfo.environment["CLIPMAC_ENGINE"]?.lowercased()
            ?? ProcessInfo.processInfo.environment["DRPASTE_ENGINE"]?.lowercased()
        if let forced = env.flatMap(HotkeyEngineKind.init(rawValue:)) {
            switch forced {
            case .eventTap: return EventTapEngine(config: config)
            case .carbon:   return CarbonHotKeyEngine(config: config)
            case .monitor:  return GlobalMonitorEngine(config: config)
            }
        }
        return AXIsProcessTrusted()
            ? EventTapEngine(config: config)
            : CarbonHotKeyEngine(config: config)
    }
}
