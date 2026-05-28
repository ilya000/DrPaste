//
//  KeyboardLayoutRepair.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Local repair for text typed in the wrong keyboard layout.
//  Minimal Punto-Switcher-style heuristic: character-level RU/EN mapping plus
//  scoring via NSSpellChecker to decide whether the swap is an improvement.
//

import Foundation
import AppKit

enum KeyboardLayoutRepair {

    private static let enToRu: [Character: Character] = [
        "q":"й","w":"ц","e":"у","r":"к","t":"е","y":"н","u":"г","i":"ш","o":"щ","p":"з","[":"х","]":"ъ",
        "a":"ф","s":"ы","d":"в","f":"а","g":"п","h":"р","j":"о","k":"л","l":"д",";":"ж","'":"э",
        "z":"я","x":"ч","c":"с","v":"м","b":"и","n":"т","m":"ь",",":"б",".":"ю","/":".",
        "Q":"Й","W":"Ц","E":"У","R":"К","T":"Е","Y":"Н","U":"Г","I":"Ш","O":"Щ","P":"З","{":"Х","}":"Ъ",
        "A":"Ф","S":"Ы","D":"В","F":"А","G":"П","H":"Р","J":"О","K":"Л","L":"Д",":":"Ж","\"":"Э",
        "Z":"Я","X":"Ч","C":"С","V":"М","B":"И","N":"Т","M":"Ь","<":"Б",">":"Ю","?":","
    ]

    private static let ruToEn: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (k, v) in enToRu { m[v] = k }
        return m
    }()

    static func looksWrongLayout(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        let original = scoreLikelihood(trimmed)
        let swapped = scoreLikelihood(swap(trimmed))
        return swapped > original + 2
    }

    static func repair(_ text: String) -> String {
        let swapped = swap(text)
        return scoreLikelihood(swapped) > scoreLikelihood(text) ? swapped : text
    }

    static func swap(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if let r = enToRu[ch] { out.append(r); continue }
            if let e = ruToEn[ch] { out.append(e); continue }
            out.append(ch)
        }
        return out
    }

    private static func scoreLikelihood(_ text: String) -> Double {
        let dominantLang = guessDominantLanguage(text)
        let words = text.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" })
            .map(String.init)
            .filter { $0.count >= 2 }
        guard !words.isEmpty else { return 0 }

        let checker = NSSpellChecker.shared
        var goodWords = 0
        for w in words {
            let r = checker.checkSpelling(of: w, startingAt: 0, language: dominantLang, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            if r.location == NSNotFound { goodWords += 1 }
        }
        return Double(goodWords) * 10.0 / Double(max(text.count, 1))
    }

    private static func guessDominantLanguage(_ text: String) -> String {
        var cyr = 0, lat = 0
        for ch in text.unicodeScalars {
            if (0x0400...0x04FF).contains(ch.value) { cyr += 1 }
            else if (0x0041...0x007A).contains(ch.value) { lat += 1 }
        }
        return cyr > lat ? "ru" : "en"
    }
}
