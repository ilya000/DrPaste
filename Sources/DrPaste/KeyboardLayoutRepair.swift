//
//  KeyboardLayoutRepair.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Local repair for text typed in the wrong keyboard layout (Punto-Switcher
//  style). Two directions per layout:
//    1. local-script text touch-typed on a US/QWERTY layout → Latin gibberish
//       ("Rcnfnb" → "Кстати");
//    2. English text touch-typed on a local layout → local-script gibberish
//       ("руддщ" → "hello").
//  A per-key character map per layout swaps the text; `NSSpellChecker` scores
//  whether the swap is a real improvement in the appropriate language. Multiple
//  layouts (Russian, Ukrainian) are tried and the best-scoring swap wins.
//
//  Latin↔Latin layouts (French AZERTY, German QWERTZ) are tracked in BACKLOG
//  #A86 — they need accent/AltGr handling and a stricter detector to avoid
//  false positives, so they're deliberately not included here yet.
//

import Foundation
import AppKit

enum KeyboardLayoutRepair {

    // MARK: - Layout model

    struct Layout {
        let id: String
        /// Spell-check language of the LOCAL (non-Latin) side.
        let language: String
        /// english-QWERTY character → local-layout character at the same key.
        let enToLocal: [Character: Character]
        /// Inverse map, built once.
        let localToEn: [Character: Character]

        init(id: String, language: String, enToLocal: [Character: Character]) {
            self.id = id
            self.language = language
            self.enToLocal = enToLocal
            var inverse: [Character: Character] = [:]
            for (k, v) in enToLocal { inverse[v] = k }
            self.localToEn = inverse
        }
    }

    // Russian ЙЦУКЕН.
    private static let russianMap: [Character: Character] = [
        "q":"й","w":"ц","e":"у","r":"к","t":"е","y":"н","u":"г","i":"ш","o":"щ","p":"з","[":"х","]":"ъ",
        "a":"ф","s":"ы","d":"в","f":"а","g":"п","h":"р","j":"о","k":"л","l":"д",";":"ж","'":"э",
        "z":"я","x":"ч","c":"с","v":"м","b":"и","n":"т","m":"ь",",":"б",".":"ю","/":".",
        "Q":"Й","W":"Ц","E":"У","R":"К","T":"Е","Y":"Н","U":"Г","I":"Ш","O":"Щ","P":"З","{":"Х","}":"Ъ",
        "A":"Ф","S":"Ы","D":"В","F":"А","G":"П","H":"Р","J":"О","K":"Л","L":"Д",":":"Ж","\"":"Э",
        "Z":"Я","X":"Ч","C":"С","V":"М","B":"И","N":"Т","M":"Ь","<":"Б",">":"Ю","?":","
    ]

    // Ukrainian ЙЦУКЕН — Russian base, with the Ukrainian-specific letters
    // replacing ы/э/ъ (which Ukrainian doesn't have): s→і, '→є, ]→ї.
    private static let ukrainianMap: [Character: Character] = {
        var m = russianMap
        m["s"] = "і"; m["S"] = "І"
        m["'"] = "є"; m["\""] = "Є"
        m["]"] = "ї"; m["}"] = "Ї"
        return m
    }()

    // Bulgarian — "Phonetic Traditional" (KBDBGPH1), the variant ~70–80% of
    // everyday Bulgarian users type with (БДС is the professional-typist
    // minority). Cyrillic letters sit on phonetically-similar Latin keys.
    private static let bulgarianMap = addingUppercase([
        "q":"я","w":"в","e":"е","r":"р","t":"т","y":"ъ","u":"у","i":"и","o":"о","p":"п",
        "[":"ш","]":"щ",
        "a":"а","s":"с","d":"д","f":"ф","g":"г","h":"х","j":"й","k":"к","l":"л",
        "z":"з","x":"ь","c":"ц","v":"ж","b":"б","n":"н","m":"м",
        "`":"ч","\\":"ю"
    ])

    // Serbian Cyrillic (KBDYCC, QWERTZ-based — note y→з). Cross-verified against
    // Microsoft's KBDYCC codepoint table.
    private static let serbianMap = addingUppercase([
        "q":"љ","w":"њ","e":"е","r":"р","t":"т","y":"з","u":"у","i":"и","o":"о","p":"п",
        "[":"ш","]":"ђ","\\":"ж",
        "a":"а","s":"с","d":"д","f":"ф","g":"г","h":"х","j":"ј","k":"к","l":"л",
        ";":"ч","'":"ћ",
        "z":"ѕ","x":"џ","c":"ц","v":"в","b":"б","n":"н","m":"м"
    ])

    /// Add uppercase entries (e.g. "a"→"а" ⇒ "A"→"А") to a lowercase key map.
    private static func addingUppercase(_ m: [Character: Character]) -> [Character: Character] {
        var r = m
        for (k, v) in m {
            guard let ku = k.uppercased().first, ku != k,
                  let vu = v.uppercased().first else { continue }
            r[ku] = vu
        }
        return r
    }

    private static let russian = Layout(id: "ru", language: "ru", enToLocal: russianMap)
    private static let ukrainian = Layout(id: "uk", language: "uk", enToLocal: ukrainianMap)
    private static let bulgarian = Layout(id: "bg", language: "bg", enToLocal: bulgarianMap)
    private static let serbian = Layout(id: "sr", language: "sr", enToLocal: serbianMap)

    /// All supported layouts, tried in turn.
    static let layouts: [Layout] = [russian, ukrainian, bulgarian, serbian]

    /// Bundled Serbian Cyrillic wordlist (top ~40k by frequency) — Serbian has
    /// no installed `NSSpellChecker` dictionary, so `scoreInLanguage("sr")`
    /// scores against this set instead. Loaded once, cached.
    private static let serbianWords: Set<String> = {
        guard let url = Bundle.module.url(forResource: "serbian-words", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }()

    // MARK: - Swapping

    /// Swap `text` through one layout, in whichever direction applies per
    /// character (english→local or local→english).
    static func swap(_ text: String, with layout: Layout) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if let local = layout.enToLocal[ch] { out.append(local) }
            else if let en = layout.localToEn[ch] { out.append(en) }
            else { out.append(ch) }
        }
        return out
    }

    /// Back-compat convenience: swap through the Russian layout.
    static func swap(_ text: String) -> String { swap(text, with: russian) }

    // MARK: - Detection & repair

    static func looksWrongLayout(_ text: String) -> Bool {
        decideLayout(sample(of: text)) != nil
    }

    static func repair(_ text: String) -> String {
        // Decide on a bounded sample (cheap), then apply the chosen swap to the
        // FULL string — avoids several full-length NSSpellChecker passes on a
        // long clip.
        guard let layout = decideLayout(sample(of: text)) else { return text }
        return swap(text, with: layout)
    }

    /// Bounded, trimmed sample used for the decision.
    private static func sample(of text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
    }

    /// Pick the layout whose swap is a clear, confident improvement over the
    /// sample as-is, or nil if none qualifies.
    private static func decideLayout(_ trimmed: String) -> Layout? {
        guard trimmed.count >= 3 else { return nil }
        let original = originalScore(trimmed)
        var best: (Layout, Double)?
        for layout in layouts {
            let swapped = swap(trimmed, with: layout)
            guard swapped != trimmed else { continue }
            // Confidence guard against short collisions: a single short word that
            // happens to swap to a valid word is NOT enough — require ≥2 scored
            // words, or one word of ≥4 letters ("руддщ" → "hello").
            let scoredWords = words(in: swapped)
            if scoredWords.isEmpty { continue }
            if scoredWords.count == 1 && (scoredWords.first?.count ?? 0) < 4 { continue }
            let score = scoreInLanguage(swapped, language: swapLanguage(of: trimmed, layout: layout))
            if score >= 0.5 && score > original + 0.3, best == nil || score > best!.1 {
                best = (layout, score)
            }
        }
        return best?.0
    }

    // MARK: - Scoring

    /// The language to spell-check a SWAP result in: Latin input swaps to the
    /// local script (score in the layout's language); local-script input swaps
    /// back to Latin (score in English).
    private static func swapLanguage(of input: String, layout: Layout) -> String {
        isLatinDominant(input) ? layout.language : "en"
    }

    /// How valid the text is AS-IS, in its most plausible language (so genuine
    /// text is never "repaired"). Latin input → English; any non-Latin script →
    /// the best of every supported layout's language. Script-agnostic, so adding
    /// a new (non-Latin) layout needs no change here.
    private static func originalScore(_ text: String) -> Double {
        if isLatinDominant(text) { return scoreInLanguage(text, language: "en") }
        return layouts.map { scoreInLanguage(text, language: $0.language) }.max() ?? 0
    }

    /// Scorable words (≥2 letters) in `text`.
    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    /// Fraction of words (0…1) recognised in the given language. Uses the
    /// bundled wordlist for Serbian (no system dictionary), else NSSpellChecker.
    private static func scoreInLanguage(_ text: String, language: String) -> Double {
        let ws = words(in: text)
        guard !ws.isEmpty else { return 0 }
        if language == "sr" {
            let good = ws.filter { serbianWords.contains($0.lowercased()) }.count
            return Double(good) / Double(ws.count)
        }
        let checker = NSSpellChecker.shared
        var good = 0
        for w in ws {
            let r = checker.checkSpelling(of: w, startingAt: 0, language: language,
                                          wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            if r.location == NSNotFound { good += 1 }
        }
        return Double(good) / Double(ws.count)
    }

    // MARK: - Script helpers

    /// True when the text is mostly Latin (A–Z / a–z) rather than any other
    /// script — used to decide swap direction. Works for Cyrillic, Greek,
    /// Hangul, Hebrew, … alike (anything non-Latin counts as "other").
    private static func isLatinDominant(_ text: String) -> Bool {
        var latin = 0, other = 0
        for s in text.unicodeScalars {
            let v = s.value
            if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) { latin += 1 }
            else if CharacterSet.letters.contains(s) { other += 1 }
        }
        return latin >= other
    }
}
