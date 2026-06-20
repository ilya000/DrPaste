import Foundation

// The 14-language Cyrillic model: each language's full alphabet (for detection by "fit"),
// its national Cyrillic→Latin and Latin→Cyrillic romanization overrides over the Russian
// base maps, and a prevalence used to break detection ties. Ported verbatim from DrPaste.

struct CyrillicLang {
    let id: String
    let name: String
    let prevalence: Int
    /// The language's full lowercase Cyrillic alphabet. Detection rules out any language
    /// whose alphabet is missing a letter present in the text — so a word can never be
    /// assigned to a language that physically can't spell it.
    let letters: Set<Character>
    let cyr2lat: [Character: String]
    let lat2cyr: [String: String]
    let lat2cyrDrop: [String]
    init(_ id: String, _ name: String, _ prevalence: Int,
         letters: String,
         cyr2lat: [Character: String] = [:],
         lat2cyr: [String: String] = [:],
         lat2cyrDrop: [String] = []) {
        self.id = id; self.name = name; self.prevalence = prevalence
        self.letters = Set(letters)
        self.cyr2lat = cyr2lat
        self.lat2cyr = lat2cyr; self.lat2cyrDrop = lat2cyrDrop
    }
}

enum CyrillicModel {
    /// Russian 33-letter alphabet — the base most other languages extend.
    static let ruCore = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"

    /// Slavic-script Gaj/Vuk digraphs shared by Serbian and Macedonian: the Russian-style
    /// ASCII digraphs (sh/ch/zh/…) are dropped in favour of single diacritic letters.
    static let southSlavicDrop = ["sh", "ch", "zh", "kh", "ts", "yo", "yu", "ya", "shch", "ye"]

    /// All 14 supported Cyrillic languages (>1M speakers), ordered by prevalence (the
    /// tie-breaker during detection). `letters` is each language's complete alphabet;
    /// romanization follows each language's national / common scheme rather than a single
    /// uniform standard. Latin→Cyrillic overrides assume input written in that national
    /// Latin (incl. diacritics like ä/ö/ü/ñ where the scheme uses them).
    static let langs: [CyrillicLang] = [
        CyrillicLang("russian", "Russian", 150,
            letters: ruCore,
            // Russian-specific Latin→Cyrillic so the explicit Russian target produces its
            // characteristic letters (the neutral `interslavic` fallback omits these):
            // y→ы, j→й, apostrophes→ь/ъ. ё comes from the base yo→ё. (э is intentionally
            // NOT mapped — no unambiguous Latin source; "eh" would false-trigger in
            // ordinary words like "tehnika".)
            lat2cyr: ["y": "ы", "j": "й", "'": "ь", "''": "ъ"]),
        CyrillicLang("ukrainian", "Ukrainian", 33,
            letters: "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя",
            cyr2lat: ["г": "h", "и": "y"],
            lat2cyr: ["y": "и", "yi": "ї", "ye": "є", "g": "г", "i": "і", "'": "ь"]),
        CyrillicLang("kazakh", "Kazakh", 13,
            letters: ruCore + "әғіңөұүһқ",
            cyr2lat: ["ә": "ä", "ғ": "ğ", "қ": "q", "ң": "ñ", "ө": "ö",
                      "ұ": "ū", "ү": "ü", "һ": "h", "і": "i", "ж": "j",
                      "ш": "ş", "и": "i", "й": "i", "ю": "iu", "я": "ia"],
            lat2cyr: ["ä": "ә", "ğ": "ғ", "q": "қ", "ñ": "ң", "ö": "ө",
                      "ū": "ұ", "ü": "ү", "j": "ж", "ş": "ш", "h": "һ"]),
        CyrillicLang("serbian", "Serbian", 9,
            letters: "абвгдђежзијклљмнњопрстћуфхцчџш",
            cyr2lat: ["ж": "ž", "ч": "č", "ш": "š", "х": "h", "ц": "c",
                      "ћ": "ć", "ђ": "đ", "ј": "j", "љ": "lj", "њ": "nj",
                      "џ": "dž"],
            lat2cyr: ["ž": "ж", "č": "ч", "š": "ш", "ć": "ћ", "đ": "ђ",
                      "lj": "љ", "nj": "њ", "dž": "џ", "j": "ј", "h": "х",
                      "c": "ц"],
            lat2cyrDrop: southSlavicDrop),
        CyrillicLang("bulgarian", "Bulgarian", 8,
            letters: "абвгдежзийклмнопрстуфхцчшщъьюя",
            cyr2lat: ["щ": "sht", "ъ": "a", "ь": "y"],
            lat2cyr: ["sht": "щ", "a": "а", "yo": "йо", "yu": "ю", "ya": "я", "'": "ь"]),
        CyrillicLang("tajik", "Tajik", 8,
            letters: "абвгғдеёжзиӣйкқлмнопрстуӯфхҳцчҷшъэюя",
            cyr2lat: ["ғ": "gh", "ӣ": "ī", "қ": "q", "ӯ": "ū", "ҳ": "h",
                      "ҷ": "j", "ъ": "'"],
            lat2cyr: ["gh": "ғ", "ī": "ӣ", "q": "қ", "ū": "ӯ", "h": "ҳ",
                      "j": "ҷ"]),
        CyrillicLang("mongolian", "Mongolian", 6,
            letters: ruCore + "өү",
            cyr2lat: ["ж": "j", "ө": "ö", "ү": "ü", "щ": "sh", "й": "i",
                      "ъ": "i", "ь": "i"],
            lat2cyr: ["ö": "ө", "ü": "ү", "j": "ж"]),
        CyrillicLang("belarusian", "Belarusian", 5,
            letters: "абвгдеёжзійклмнопрстуўфхцчшыьэюя",
            cyr2lat: ["г": "h"],
            lat2cyr: ["w": "ў", "h": "г", "i": "і", "'": "ь"]),
        CyrillicLang("kyrgyz", "Kyrgyz", 5,
            letters: ruCore + "ңөү",
            cyr2lat: ["ң": "ñ", "ө": "ö", "ү": "ü", "ж": "j"],
            lat2cyr: ["ñ": "ң", "ö": "ө", "ü": "ү", "j": "ж"]),
        CyrillicLang("tatar", "Tatar", 5,
            letters: ruCore + "әөүҗңһ",
            cyr2lat: ["ә": "ä", "ө": "ö", "ү": "ü", "җ": "c", "ң": "ñ",
                      "һ": "h", "ж": "j", "х": "x", "ч": "ç", "ш": "ş",
                      "ы": "ı"],
            lat2cyr: ["ä": "ә", "ö": "ө", "ü": "ү", "ñ": "ң", "c": "җ",
                      "ç": "ч", "ş": "ш", "j": "ж", "x": "х", "ı": "ы"]),
        CyrillicLang("chechen", "Chechen", 2,
            letters: ruCore + "ӏӀ",
            cyr2lat: ["ӏ": "'", "Ӏ": "'", "ъ": "'"],
            lat2cyr: ["'": "ӏ"]),
        CyrillicLang("macedonian", "Macedonian", 2,
            letters: "абвгдѓежзѕијклљмнњопрстќуфхцчџш",
            cyr2lat: ["ж": "ž", "ч": "č", "ш": "š", "х": "h", "ц": "c",
                      "ѓ": "gj", "ќ": "kj", "ѕ": "dz", "џ": "dž",
                      "љ": "lj", "њ": "nj", "ј": "j"],
            lat2cyr: ["ž": "ж", "č": "ч", "š": "ш", "gj": "ѓ", "ǵ": "ѓ",
                      "kj": "ќ", "ḱ": "ќ", "dz": "ѕ", "lj": "љ", "nj": "њ",
                      "dž": "џ", "j": "ј", "h": "х", "c": "ц"],
            lat2cyrDrop: southSlavicDrop),
        CyrillicLang("bashkir", "Bashkir", 1,
            letters: ruCore + "әөүғҙҡңҫһ",
            cyr2lat: ["ә": "ä", "ө": "ö", "ү": "ü", "ғ": "ğ", "ҙ": "ź",
                      "ҫ": "ś", "ҡ": "q", "ң": "ñ", "һ": "h", "ж": "j",
                      "х": "x", "ч": "ç", "ш": "ş", "ы": "ı"],
            lat2cyr: ["ä": "ә", "ö": "ө", "ü": "ү", "ğ": "ғ", "ź": "ҙ",
                      "ś": "ҫ", "q": "ҡ", "ñ": "ң", "ç": "ч", "ş": "ш",
                      "j": "ж", "x": "х", "ı": "ы"]),
        CyrillicLang("chuvash", "Chuvash", 1,
            letters: ruCore + "ӑӗҫӳ",
            cyr2lat: ["ӑ": "ă", "ӗ": "ĕ", "ҫ": "ś", "ӳ": "ÿ"],
            lat2cyr: ["ă": "ӑ", "ĕ": "ӗ", "ś": "ҫ", "ÿ": "ӳ"])
    ]

    static func lang(id: String) -> CyrillicLang { langs.first { $0.id == id } ?? langs[0] }

    /// Union of every supported alphabet — used to isolate the Cyrillic letters in a string
    /// while ignoring Latin / punctuation.
    static let allLetters: Set<Character> = {
        var u = Set<Character>()
        for l in langs { u.formUnion(l.letters) }
        return u
    }()

    // MARK: detection

    /// Auto-detect the Cyrillic language by alphabet fit: a language is penalised once for
    /// every Cyrillic letter in the text its alphabet does not contain; fewest "foreign"
    /// letters wins. Ties break toward `prefer` (a caller hint, e.g. the active layout),
    /// then locale, then prevalence — so «Џек», impossible in Russian but valid in Serbian
    /// and Macedonian, resolves to Serbian. Bulgarian (a subset of Russian's alphabet) is
    /// recovered from its signature ъ-as-vowel with no Russian-only ы/э/ё.
    static func detect(_ s: String, prefer: String? = nil) -> CyrillicLang {
        var present = Set(s.lowercased())
        present.formUnion(s)
        let textCyr = present.intersection(allLetters)
        guard !textCyr.isEmpty else { return lang(id: prefer ?? "russian") }

        let scored = langs.map { ($0, textCyr.subtracting($0.letters).count) }
        let minForeign = scored.map(\.1).min() ?? 0
        let tied = scored.filter { $0.1 == minForeign }.map(\.0)

        // Bulgarian signature is locale-independent: ъ used as a vowel with no Russian-only
        // ы/э/ё, when Bulgarian is among the best fits.
        if textCyr.contains("ъ"), textCyr.isDisjoint(with: ["ы", "э", "ё"]),
           tied.contains(where: { $0.id == "bulgarian" }) {
            return lang(id: "bulgarian")
        }
        // Caller hint wins ties when it fits, then locale, then prevalence.
        if let prefer, let m = tied.first(where: { $0.id == prefer }) { return m }
        if let localeID = localePreferredID, let m = tied.first(where: { $0.id == localeID }) { return m }
        return tied.max(by: { $0.prevalence < $1.prevalence }) ?? langs[0]
    }

    // MARK: Cyrillic → Latin

    /// Lowercase Cyrillic → Latin base map (Russian + Ukrainian / Belarusian / Old Church
    /// Slavonic letters). Per-language overrides are layered on top in `cyr2latMap`.
    static let cyrBaseMap: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d",
        "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i",
        "й": "y", "к": "k", "л": "l", "м": "m", "н": "n",
        "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
        "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch",
        "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "",
        "э": "e", "ю": "yu", "я": "ya",
        "є": "ye", "і": "i", "ї": "yi", "ґ": "g",
        "ў": "w",
        "ѣ": "ye", "ѵ": "i", "ѳ": "f", "ѕ": "dz"
    ]

    static func cyr2latMap(_ l: CyrillicLang) -> [Character: String] {
        var m = cyrBaseMap
        for (k, v) in l.cyr2lat { m[k] = v }
        return m
    }

    /// Cyrillic → Latin with the given (resolved) language and per-letter case preservation:
    /// "ПРИВЕТ" → "PRIVET" (all-caps) but "Привет" → "Privet" (title-case), not "PRIvet".
    static func cyrToLat(_ input: String, lang l: CyrillicLang) -> String {
        let map = cyr2latMap(l)
        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count * 2)
        for i in chars.indices {
            let ch = chars[i]
            let lowerStr = String(ch).lowercased()
            guard let lowerCh = lowerStr.first, let translit = map[lowerCh] else {
                out.append(ch); continue
            }
            if !ch.isUppercase || translit.isEmpty { out.append(translit); continue }
            if nearestNeighborIsUppercase(chars, at: i, map: map) {
                out.append(translit.uppercased())
            } else if let first = translit.first {
                out.append(String(first).uppercased())
                out.append(String(translit.dropFirst()))
            }
        }
        return out
    }

    /// True if the closest Cyrillic letter on either side of `idx` is uppercase — decides
    /// whether a multi-letter translit like "shch" renders as "Shch" (title) or "SHCH".
    private static func nearestNeighborIsUppercase(_ chars: [Character], at idx: Int,
                                                   map: [Character: String]) -> Bool {
        func isCyr(_ c: Character) -> Bool { map[String(c).lowercased().first ?? c] != nil }
        var j = idx - 1
        while j >= 0 {
            let n = chars[j]
            if isCyr(n) { return n.isUppercase }
            if !n.isLetter { break }
            j -= 1
        }
        j = idx + 1
        while j < chars.count {
            let n = chars[j]
            if isCyr(n) { return n.isUppercase }
            if !n.isLetter { break }
            j += 1
        }
        return false
    }

    // MARK: Latin → Cyrillic

    /// Characteristic national-Latin letters per target. Markers unique to one language
    /// (Serbian ć/đ, Macedonian gj/kj, Bashkir ź/ś, Chuvash ă/ĕ, Tajik ī) weigh 10×; shared
    /// ones (ä/ö/ü/ñ/q/ş) weigh 1×, with the hint / locale / prevalence breaking ties.
    static let latinTargetSignatures: [(id: String, markers: [String])] = [
        ("serbian",    ["ć", "đ", "ž", "č", "š"]),
        ("macedonian", ["gj", "kj", "ǵ", "ḱ", "dz"]),
        ("kazakh",     ["q", "ğ", "ñ", "ä", "ö", "ü", "ū", "ş"]),
        ("tatar",      ["ç", "ı", "ä", "ö", "ü", "ş", "ñ"]),
        ("bashkir",    ["ź", "ś", "ğ", "ä", "ö", "ü", "q", "ç", "ş", "ı"]),
        ("chuvash",    ["ă", "ĕ", "ÿ"]),
        ("tajik",      ["ī", "ū", "gh"])
    ]

    private static let latinMarkerCount: [String: Int] = {
        var c: [String: Int] = [:]
        for (_, ms) in latinTargetSignatures { for m in Set(ms) { c[m, default: 0] += 1 } }
        return c
    }()

    /// Resolve the Latin→Cyrillic target for "auto": (1) characteristic letters, (2) caller
    /// hint, (3) locale, (4) Interslavic — the neutral pan-Slavic orthography (deliberately
    /// NOT Russian, so the default isn't a politically-loaded choice). Plain ASCII carries
    /// no language evidence, so it falls through to hint / locale / Interslavic.
    static func autoDetectLatinTarget(_ input: String, prefer: String? = nil) -> String {
        let lower = input.lowercased()
        var best: String?
        var bestScore = 0
        for (id, markers) in latinTargetSignatures {
            var score = 0
            for m in Set(markers) where lower.contains(m) {
                score += (latinMarkerCount[m] == 1) ? 10 : 1
            }
            guard score > 0 else { continue }
            if score > bestScore {
                bestScore = score; best = id
            } else if score == bestScore, let b = best, b != id {
                if id == prefer || id == localePreferredID {
                    best = id
                } else if b != prefer, b != localePreferredID,
                          lang(id: id).prevalence > lang(id: b).prevalence {
                    best = id
                }
            }
        }
        return best ?? prefer ?? localePreferredID ?? "interslavic"
    }

    /// Latin → Cyrillic map for the given target. Digraphs first (matched greedily by the
    /// caller), single letters second. Russian base, then the target's `lat2cyrDrop`
    /// removals and `lat2cyr` overrides; `interslavic` swaps in the neutral pan-Slavic forms.
    static func lat2cyrMap(for target: String) -> [String: String] {
        var m: [String: String] = [
            "shch": "щ",
            "sh": "ш", "ch": "ч", "zh": "ж", "kh": "х", "ts": "ц",
            "yo": "ё", "yu": "ю", "ya": "я", "ye": "е",
            "a": "а", "b": "б", "v": "в", "g": "г", "d": "д",
            "e": "е", "z": "з", "i": "и", "y": "й",
            "k": "к", "l": "л", "m": "м", "n": "н", "o": "о",
            "p": "п", "r": "р", "s": "с", "t": "т", "u": "у",
            "f": "ф", "h": "х", "c": "ц",
            "j": "й", "w": "в", "x": "кс", "q": "к"
        ]
        if target == "interslavic" {
            m["yo"] = "јо"; m["yu"] = "ју"; m["ya"] = "ја"
            m["ye"] = "је"; m["yi"] = "ји"
            m["y"] = "и"; m["j"] = "ј"; m["shch"] = "шч"
            return m
        }
        let l = lang(id: target)
        for key in l.lat2cyrDrop { m.removeValue(forKey: key) }
        for (k, v) in l.lat2cyr { m[k] = v }
        return m
    }

    /// Greedy longest-match (4→1) Latin→Cyrillic over `chars` with `map`, preserving case per run
    /// ("Privet"→"Привет", "PRIVET"→"ПРИВЕТ"). Non-mapped characters pass through.
    private static func greedyLat2Cyr(_ chars: [Character], _ map: [String: String]) -> String {
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            var matched = false
            for length in stride(from: min(4, chars.count - i), through: 1, by: -1) {
                let slice = String(chars[i..<(i + length)]).lowercased()
                guard let cyrillic = map[slice] else { continue }
                let firstSourceChar = chars[i]
                let allCapsRun = firstSourceChar.isUppercase && (length == 1 || chars[i + 1].isUppercase)
                if allCapsRun {
                    out.append(cyrillic.uppercased())
                } else if firstSourceChar.isUppercase {
                    if let f = cyrillic.first {
                        out.append(String(f).uppercased())
                        out.append(String(cyrillic.dropFirst()))
                    }
                } else {
                    out.append(cyrillic)
                }
                i += length
                matched = true
                break
            }
            if !matched { out.append(chars[i]); i += 1 }
        }
        return out
    }

    /// Serbian Latin word stems where `lj`/`nj`/`dž` straddle a morpheme boundary, so they are TWO
    /// letters, not a digraph: `nadживeti` = над+живети → "надживети" (NOT "наџивети"); `injekcija`
    /// = ин+јекција → "инјекција". Prefix-matched (covers inflections). Curated; rare misses are a
    /// one-backspace fix. NB: `nadžak` (наџак) and `nadljudski` (надљудски) ARE real digraphs and
    /// are deliberately ABSENT — the default digraph rule spells them correctly.
    static let serbianBoundaryStems: [String] = [
        "injekc", "injekt", "konjug", "konjunk", "konjunkt", "tanjug", "vanjezič", "vanjezic", "anjon",
        "nadživ", "odžive", "podžanr", "predživot", "izdžik",
    ]

    /// Latin → Cyrillic with the given (resolved) target. Greedy longest-match against the
    /// digraph/trigraph table (shch, sh/ch/zh, yo/yu/ya) before single letters. Serbian is handled
    /// word-wise so morpheme-boundary `lj`/`nj`/`dž` split (see `serbianBoundaryStems`); every other
    /// target keeps the plain greedy pass, so their output is unchanged.
    static func latToCyr(_ input: String, target: String) -> String {
        let map = lat2cyrMap(for: target)
        let normalized = input
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .replacingOccurrences(of: "\u{2032}", with: "'")
        guard target == "serbian" else { return greedyLat2Cyr(Array(normalized), map) }
        var noDigraph = map
        for k in ["lj", "nj", "dž"] { noDigraph.removeValue(forKey: k) }
        var out = ""
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            let lower = word.lowercased()
            let isException = serbianBoundaryStems.contains { lower.hasPrefix($0) }
            out += greedyLat2Cyr(Array(word), isException ? noDigraph : map)
            word = ""
        }
        for ch in normalized {
            if ch.isLetter { word.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }

    // MARK: locale

    /// Public ISO-ish code → internal language id. Accepts `ua` as an alias for Ukrainian.
    static let codeToID: [String: String] = [
        "ru": "russian", "uk": "ukrainian", "ua": "ukrainian", "be": "belarusian",
        "bg": "bulgarian", "sr": "serbian", "mk": "macedonian", "kk": "kazakh",
        "ky": "kyrgyz", "tg": "tajik", "mn": "mongolian", "tt": "tatar",
        "ba": "bashkir", "cv": "chuvash", "ce": "chechen",
        "is": "interslavic", "isv": "interslavic"
    ]

    /// The language id matching the user's locale, if any. `var` (not `let`) so callers/tests
    /// can pin it; production reads it once from the system's preferred languages.
    static var localePreferredID: String? = {
        for lang in Locale.preferredLanguages {
            let code = String(lang.prefix(2)).lowercased()
            if let id = codeToID[code] { return id }
        }
        return nil
    }()

    // MARK: Multi-scheme candidates (anti-translit "zoo")

    /// Alternative Latin→Cyrillic mappings beyond the base, per target — the keys where translit
    /// conventions diverge (often layout-imprinted: a phonetic-layout key collapses a digraph into
    /// one letter, e.g. `w` = Ш instead of `sh`). Base value is excluded by the candidate builder.
    static func lat2cyrAlternatives(for target: String) -> [String: [String]] {
        switch target {
        // Variants are consolidated from a survey of the real phonetic keyboard layouts that "train"
        // diaspora habits (XKB phonetic/winkeys/YAZHERTY, macOS KDWin, cyrex, Somelauw, AATSEEL
        // Student/ЯШЕРТ, winrus YaWert family). Base values are the standard translit; these are the
        // layout-imprinted alternatives. Divergent keys: w∈{в,ш,ж,я}, v∈{в,ж}, x∈{ь,х,ж}.
        case "russian":
            return ["w": ["ш", "ж", "я"], "x": ["х", "ь", "ж"], "v": ["ж"], "q": ["я", "ч"],
                    "j": ["ж", "дж"], "c": ["к", "с"], "y": ["й", "и"], "u": ["ю"], "e": ["э"],
                    "i": ["й"], "'": ["ъ"]]
                    // base ' → ь; alt → ъ (ob'yavlenie → объявление; dict picks the real word).
                    // e→ё dropped (rare; "yo" already yields ё) to keep the candidate count bounded.
        case "ukrainian":
            return ["w": ["в", "ш", "ж"], "x": ["х", "ж"], "v": ["ж"], "q": ["я", "ч"],
                    "j": ["й", "ж"], "c": ["к"], "g": ["ґ"], "i": ["и"], "u": ["ю"]]
        default:
            return [:]
        }
    }

    /// Multi-char "iotation" alternatives that introduce a NEW segment boundary not present in `base`.
    /// The base map reads `jo` as й+о ("йо"); but diaspora typists routinely write `jo/ja/ju/je` for
    /// ё/я/ю/е (the j-iotation habit, e.g. `jolka`→ёлка, `jabloko`→яблоко). These can't be single-key
    /// alternatives (they span two source chars), so the generator matches them as digraph keys and
    /// branches: base reading ("йо") first, then the iotated reading ("ё"). Closes `jo→ё`.
    static func lat2cyrDigraphs(for target: String) -> [String: [String]] {
        switch target {
        case "russian":
            return ["jo": ["ё"], "ja": ["я"], "ju": ["ю"], "je": ["е", "ё"]]
        case "ukrainian":
            return ["ja": ["я"], "ju": ["ю"], "je": ["є", "е"], "ji": ["ї"]]
        default:
            return [:]
        }
    }

    struct Candidate { let text: String; let variants: [String: String] }   // non-base choices: srcToken→cyr

    /// Apply the source slice's case to a lowercase Cyrillic option (mirrors `greedyLat2Cyr`).
    private static func applyCaseOpt(_ src: [Character], _ lower: String) -> String {
        let f = src[0]
        let allCaps = f.isUppercase && (src.count == 1 || src[1].isUppercase)
        if allCaps { return lower.uppercased() }
        if f.isUppercase, let c = lower.first { return String(c).uppercased() + lower.dropFirst() }
        return lower
    }

    /// All plausible Latin→Cyrillic readings of `input` under the base map + its alternatives — the
    /// base reading first, then variants. Greedy longest-match segments the source; each segment
    /// branches over [base] + alternatives; the cartesian product is capped at `max`. Each candidate
    /// records the non-base choices it made (for per-user habit learning by the host).
    static func candidates(_ input: String, base: [String: String],
                           alts: [String: [String]], digraphs: [String: [String]] = [:],
                           max: Int) -> [Candidate] {
        let normalized = input
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .replacingOccurrences(of: "\u{2032}", with: "'")
        let chars = Array(normalized)
        var segOpts: [[String]] = []      // lowercase cyr options, base at index 0
        var segSrc: [[Character]] = []
        var i = 0
        while i < chars.count {
            var len = 0, key = ""
            for l in stride(from: min(4, chars.count - i), through: 1, by: -1) {
                let slice = String(chars[i..<(i + l)]).lowercased()
                if base[slice] != nil || digraphs[slice] != nil { len = l; key = slice; break }
            }
            if len == 0 { segOpts.append([String(chars[i])]); segSrc.append([chars[i]]); i += 1; continue }
            // Base reading: the direct map entry, or (for a digraph-only key like "jo") the greedy
            // base segmentation of the slice ("йо"). Then layer single-key alts and digraph variants.
            let baseReading = base[key] ?? greedyLat2Cyr(Array(key), base)
            var opts = [baseReading]
            if let a = alts[key] { for x in a where !opts.contains(x) { opts.append(x) } }
            if let d = digraphs[key] { for x in d where !opts.contains(x) { opts.append(x) } }
            segOpts.append(opts); segSrc.append(Array(chars[i..<(i + len)])); i += len
        }
        var cands: [Candidate] = [Candidate(text: "", variants: [:])]
        for s in segOpts.indices {
            let src = segSrc[s], opts = segOpts[s], srcKey = String(segSrc[s]).lowercased()
            var next: [Candidate] = []
            outer: for c in cands {
                for (oi, opt) in opts.enumerated() {
                    var v = c.variants
                    if oi != 0 { v[srcKey] = opt }
                    next.append(Candidate(text: c.text + applyCaseOpt(src, opt), variants: v))
                    if next.count >= max { break outer }
                }
            }
            cands = next
        }
        var seen = Set<String>(); var out: [Candidate] = []
        for c in cands where seen.insert(c.text).inserted { out.append(c) }   // base reading stays first
        return out
    }
}
