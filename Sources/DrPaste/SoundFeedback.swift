//
//  SoundFeedback.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Звуковой фидбек (Backlog #10). Короткие звуки для copy/paste/type операций.
//  По умолчанию все включены, отключаются индивидуально через UserDefaults.
//  Source: bundled aiff в Resources/Sounds/ либо fallback на system NSSounds.
//

import AppKit

enum SoundCue: String {
    case copySuccess  = "copy-success"
    case copyFailure  = "copy-failure"
    case pasteSuccess = "paste-success"
    case pasteFailure = "paste-failure"
    case typeTick     = "type-tick"

    var defaultsKey: String { "drpaste.sound.\(rawValue).enabled" }
    var defaultEnabled: Bool { true }

    /// System NSSound name для fallback если bundled assets нет.
    var systemFallback: NSSound.Name {
        switch self {
        case .copySuccess, .pasteSuccess: return NSSound.Name("Tink")
        case .copyFailure, .pasteFailure: return NSSound.Name("Funk")
        case .typeTick:                   return NSSound.Name("Morse")
        }
    }
}

enum SoundFeedback {
    private static let volumeKey = "drpaste.sound.volume"
    private static let defaultVolume: Float = 0.6
    private static var lastPlay: [SoundCue: Date] = [:]
    private static let throttleSeconds: TimeInterval = 0.2

    static func play(_ cue: SoundCue) {
        guard isEnabled(cue) else { return }

        // Throttle: не играть тот же sound чаще чем раз в 200 мс (type-tick exempt).
        if cue != .typeTick {
            if let prev = lastPlay[cue], Date().timeIntervalSince(prev) < throttleSeconds {
                return
            }
        }
        lastPlay[cue] = Date()

        let volume = max(0, min(1, currentVolume()))
        let effectiveVolume = cue == .typeTick ? volume * 0.3 : volume

        let sound: NSSound? = makeSound(cue: cue)
        sound?.volume = effectiveVolume
        sound?.play()
    }

    private static func makeSound(cue: SoundCue) -> NSSound? {
        // Try bundled aiff
        if let url = Bundle.module.url(forResource: cue.rawValue, withExtension: "aiff"),
           let s = NSSound(contentsOf: url, byReference: false) {
            return s.copy() as? NSSound
        }
        // Try bundled m4a as alternative
        if let url = Bundle.module.url(forResource: cue.rawValue, withExtension: "m4a"),
           let s = NSSound(contentsOf: url, byReference: false) {
            return s.copy() as? NSSound
        }
        // Fallback на system sound
        return NSSound(named: cue.systemFallback)?.copy() as? NSSound
    }

    static func isEnabled(_ cue: SoundCue) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: cue.defaultsKey) == nil { return cue.defaultEnabled }
        return defaults.bool(forKey: cue.defaultsKey)
    }

    static func setEnabled(_ enabled: Bool, for cue: SoundCue) {
        UserDefaults.standard.set(enabled, forKey: cue.defaultsKey)
    }

    static func currentVolume() -> Float {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: volumeKey) == nil { return defaultVolume }
        return defaults.float(forKey: volumeKey)
    }

    static func setVolume(_ v: Float) {
        UserDefaults.standard.set(v, forKey: volumeKey)
    }
}
