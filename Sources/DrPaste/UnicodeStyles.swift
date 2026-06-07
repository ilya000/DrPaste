//
//  UnicodeStyles.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Unicode pseudo-font conversion engine. Maps plain ASCII letters and digits
//  to stylized Unicode code points (Math Alphanumerics block, Halfwidth and
//  Fullwidth Forms, Enclosed Alphanumerics, etc.) so users can paste "bold" /
//  "italic" / "script" / "fraktur" text into platforms where font-family
//  control is unavailable (Twitter, Telegram bios, LinkedIn headlines,
//  Discord profiles, plain-text editors, etc.).
//
//  Each style is a single mapping table; the runtime walks the input char by
//  char and replaces ASCII A-Z / a-z / 0-9 with the styled code point when
//  available, leaving other characters untouched. The reverse pass (Plain)
//  uses Unicode NFKC compatibility decomposition to undo most styled forms,
//  plus a small custom reverse map for upside-down and other styles whose
//  decomposition isn't a simple ASCII fallback.
//
//  Accessibility note: stylized Unicode is NOT a real font — screen readers
//  read the glyph names ("MATHEMATICAL BOLD CAPITAL H") character by
//  character. Use only for decorative purposes in plain-text contexts.
//

import Foundation

// MARK: - Style catalogue

/// All pseudo-font styles bundled with DrPaste. Each case maps to a unique
/// transformation. The display name is the user-facing label in the editor
/// picker; the action title in CuratedDefaults uses the "Font: <name>"
/// convention so all stylize actions cluster together in the action list.
enum UnicodeFontStyle: String, CaseIterable, Codable, Identifiable {
    case bold              = "bold"
    case italic            = "italic"
    case boldItalic        = "bold_italic"
    case script            = "script"
    case boldScript        = "bold_script"
    case fraktur           = "fraktur"
    case boldFraktur       = "bold_fraktur"
    case doubleStruck      = "double_struck"
    case sans              = "sans"
    case sansBold          = "sans_bold"
    case sansItalic        = "sans_italic"
    case sansBoldItalic    = "sans_bold_italic"
    case monospace         = "monospace"
    case fullwidth         = "fullwidth"
    case smallCaps         = "small_caps"
    case circled           = "circled"
    case filledCircled     = "filled_circled"
    case squared           = "squared"
    case filledSquared     = "filled_squared"
    case upsideDown        = "upside_down"
    case markdownAware     = "markdown_aware"    // parses **bold** / *italic* / `code` etc.
    case plain             = "plain"             // reverse pass — strip styling

    var id: String { rawValue }

    /// Human label used in the engine parameter picker.
    var displayName: String {
        switch self {
        case .bold:              return "Bold"
        case .italic:            return "Italic"
        case .boldItalic:        return "Bold Italic"
        case .script:            return "Script"
        case .boldScript:        return "Bold Script"
        case .fraktur:           return "Fraktur"
        case .boldFraktur:       return "Bold Fraktur"
        case .doubleStruck:      return "Double-struck"
        case .sans:              return "Sans-serif"
        case .sansBold:          return "Sans-serif Bold"
        case .sansItalic:        return "Sans-serif Italic"
        case .sansBoldItalic:    return "Sans-serif Bold Italic"
        case .monospace:         return "Monospace"
        case .fullwidth:         return "Fullwidth"
        case .smallCaps:         return "Small Caps"
        case .circled:           return "Circled"
        case .filledCircled:     return "Filled Circled"
        case .squared:           return "Squared"
        case .filledSquared:     return "Filled Squared"
        case .upsideDown:        return "Upside Down"
        case .markdownAware:     return "Markdown styles → Unicode"
        case .plain:             return "Plain (strip styling)"
        }
    }

    /// One-line preview ("Aa Bb 12") rendered in the styled form. Used as the
    /// secondary line in editor pickers so users see what the style looks
    /// like before committing.
    var sample: String { UnicodeStylizer.apply(to: "Aa Bb 12", style: self) }
}

// MARK: - Engine entry point

enum UnicodeStylizer {

    /// Apply a style transformation to the input. Pure function; thread-safe.
    ///
    /// #A33 (0.57.0) — Every non-`.plain` style now denormalizes the input
    /// to ASCII before applying its own table. Previous behaviour stacked
    /// styles silently: applying Italic to already-Bold text returned the
    /// Bold text unchanged because the Italic table is keyed on a-z / A-Z
    /// and the Bold glyphs aren't in those ranges, so the per-character
    /// lookup fell through to "pass it as-is". Now the input is rewound to
    /// plain ASCII first, so user expectation "this button changes the
    /// style" matches what happens.
    ///
    /// Performance: `normalize` is cheap on plain-ASCII inputs (NFKC is
    /// near-no-op for un-styled text; `customReverse` lookup is a single
    /// dictionary probe per character). Worth paying unconditionally to
    /// keep the contract simple.
    static func apply(to input: String, style: UnicodeFontStyle) -> String {
        switch style {
        case .plain:          return normalize(input)
        case .markdownAware:  return applyMarkdown(to: input)
        case .upsideDown:     return upsideDown(normalize(input))
        default:              return mapped(normalize(input), table: table(for: style))
        }
    }

    /// Markdown-aware stylization. Parses inline markdown markup
    /// (`**bold**`, `*italic*`, `***bold-italic***`, `__bold__`,
    /// `_italic_`, `` `code` ``, `~~strike~~`) and applies the matching
    /// Unicode pseudo-font style to each span. Markup characters are
    /// dropped — the output is plain Unicode-styled text suitable for
    /// platforms that don't render Markdown (Twitter / X, Telegram bios,
    /// Discord profiles, LinkedIn headlines).
    ///
    /// Plain text outside any markup span stays unstyled. Spans are
    /// matched greedily, longest-token-first, so `***x***` correctly
    /// resolves as bold-italic rather than italic-wrapping-bold.
    static func applyMarkdown(to input: String) -> String {
        // Tokens sorted longest-first so `***` is matched before `**` /
        // `*`, `___` before `__` / `_`, etc.
        struct MarkdownToken {
            let delimiter: String
            let style: UnicodeFontStyle
        }
        let tokens: [MarkdownToken] = [
            MarkdownToken(delimiter: "***", style: .boldItalic),
            MarkdownToken(delimiter: "___", style: .boldItalic),
            MarkdownToken(delimiter: "**",  style: .bold),
            MarkdownToken(delimiter: "__",  style: .bold),
            MarkdownToken(delimiter: "*",   style: .italic),
            MarkdownToken(delimiter: "_",   style: .italic),
            MarkdownToken(delimiter: "`",   style: .monospace),
            MarkdownToken(delimiter: "~~",  style: .plain)
            // ~~strike~~ uses .plain as a sentinel — the output adds
            // combining longstroke per character below.
        ]

        var out = ""
        out.reserveCapacity(input.count)
        var idx = input.startIndex

        while idx < input.endIndex {
            // Find the next opening delimiter at the current position.
            // We test in longest-first order to avoid greedy-tokenization
            // bugs (** before *, *** before **).
            var matched: MarkdownToken? = nil
            for token in tokens {
                if input[idx...].hasPrefix(token.delimiter) {
                    matched = token
                    break
                }
            }
            guard let token = matched else {
                out.append(input[idx])
                idx = input.index(after: idx)
                continue
            }

            // Scan forward for the matching closing delimiter on the
            // same line. If we can't find one, treat the opening
            // delimiter as literal text and move on (matches Markdown
            // tolerance for unclosed emphasis).
            let contentStart = input.index(idx, offsetBy: token.delimiter.count)
            var closeRange: Range<String.Index>? = nil
            var scan = contentStart
            while scan < input.endIndex {
                if input[scan] == "\n" { break }
                if input[scan...].hasPrefix(token.delimiter) {
                    closeRange = scan..<input.index(scan, offsetBy: token.delimiter.count)
                    break
                }
                scan = input.index(after: scan)
            }
            guard let close = closeRange else {
                out.append(input[idx])
                idx = input.index(after: idx)
                continue
            }

            let span = String(input[contentStart..<close.lowerBound])
            if token.delimiter == "~~" {
                // Strike: append plain text with combining longstroke.
                for ch in span {
                    out.append(ch)
                    out.append("\u{0336}")
                }
            } else {
                out.append(apply(to: span, style: token.style))
            }
            idx = close.upperBound
        }
        return out
    }

    // MARK: Forward — table-driven mapping

    private static func mapped(_ input: String, table: StyleTable) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            out.append(table.apply(ch))
        }
        return out
    }

    private static func table(for style: UnicodeFontStyle) -> StyleTable {
        switch style {
        case .bold:              return .bold
        case .italic:            return .italic
        case .boldItalic:        return .boldItalic
        case .script:            return .script
        case .boldScript:        return .boldScript
        case .fraktur:           return .fraktur
        case .boldFraktur:       return .boldFraktur
        case .doubleStruck:      return .doubleStruck
        case .sans:              return .sans
        case .sansBold:          return .sansBold
        case .sansItalic:        return .sansItalic
        case .sansBoldItalic:    return .sansBoldItalic
        case .monospace:         return .monospace
        case .fullwidth:         return .fullwidth
        case .smallCaps:         return .smallCaps
        case .circled:           return .circled
        case .filledCircled:     return .filledCircled
        case .squared:           return .squared
        case .filledSquared:     return .filledSquared
        case .upsideDown, .markdownAware, .plain:
            // Handled by direct functions; these tables are never queried.
            return .bold
        }
    }

    // MARK: Reverse — strip styling

    /// Convert any stylized text back to plain ASCII. Two-pass:
    ///   1. Unicode NFKC compatibility decomposition handles Math
    ///      Alphanumerics, Fullwidth, Circled (→ "(X)"), Squared,
    ///      Small Caps (some), Regional Indicator (some).
    ///   2. Custom reverse map handles Upside-down, Small Caps IPA glyphs,
    ///      and any other styled forms NFKC leaves alone.
    static func normalize(_ input: String) -> String {
        // Pass 1 — NFKC.
        let work = input.precomposedStringWithCompatibilityMapping
        // Pass 2 — custom reverse (upside-down + small-caps glyphs NFKC leaves
        // alone). All keys are non-ASCII, so plain text is never rewritten.
        var out = ""
        out.reserveCapacity(work.count)
        for ch in work {
            if let plain = customReverse[ch] {
                out.append(plain)
            } else {
                out.append(ch)
            }
        }
        // NOTE: an earlier "(X)" → X unwrap pass was removed (#A78). It existed
        // to undo NFKC's expansion of *parenthesized* letter glyphs (⒜ → "(a)"),
        // but it (a) dropped the character after any "(" that wasn't followed by
        // the full "(letter)" pattern — corrupting plain code like `foo()` into
        // `foo(` — and (b) unwrapped legitimate plain "(a)" / "(1)" to "a"/"1".
        // Circled letters (Ⓐ) already reverse correctly via NFKC alone, so the
        // only loss is the rare pasted parenthesized-letter glyph, which now
        // stays "(a)". Preserving literal parentheses matters far more.
        return out
    }

    // MARK: Upside-down

    /// Upside-down text — flip each glyph in place. Letters stay in their
    /// original positions; only the individual character shapes are rotated
    /// 180°. Reading order is unchanged (left-to-right). This matches the
    /// common "flipped text" social-media style users expect.
    static func upsideDown(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            out.append(upsideDownMap[ch] ?? ch)
        }
        return out
    }
}

// MARK: - StyleTable

/// Generic mapping descriptor: base code points for A / a / 0 plus a small
/// exception map for letters whose default base offset is reserved for a
/// pre-existing Unicode symbol (e.g. ℬ is the canonical Script Capital B).
private struct StyleTable {
    let upperBase: UInt32?
    let lowerBase: UInt32?
    let digitBase: UInt32?
    let exceptions: [Character: String]

    init(upperBase: UInt32?,
         lowerBase: UInt32?,
         digitBase: UInt32? = nil,
         exceptions: [Character: String] = [:]) {
        self.upperBase = upperBase
        self.lowerBase = lowerBase
        self.digitBase = digitBase
        self.exceptions = exceptions
    }

    func apply(_ ch: Character) -> String {
        if let mapped = exceptions[ch] { return mapped }
        guard let scalar = ch.unicodeScalars.first,
              ch.unicodeScalars.count == 1 else { return String(ch) }
        let v = scalar.value
        if let base = upperBase, (0x41...0x5A).contains(v),
           let mapped = Unicode.Scalar(base + (v - 0x41)) {
            return String(mapped)
        }
        if let base = lowerBase, (0x61...0x7A).contains(v),
           let mapped = Unicode.Scalar(base + (v - 0x61)) {
            return String(mapped)
        }
        if let base = digitBase, (0x30...0x39).contains(v),
           let mapped = Unicode.Scalar(base + (v - 0x30)) {
            return String(mapped)
        }
        return String(ch)
    }
}

// MARK: - Style tables

private extension StyleTable {

    // Math Bold — Serif Bold (𝐀-𝐳, 𝟎-𝟗).
    static let bold = StyleTable(
        upperBase: 0x1D400, lowerBase: 0x1D41A, digitBase: 0x1D7CE
    )

    // Math Italic — Serif Italic (𝐴-𝑧). 'h' is reserved (U+1D455 is unassigned);
    // canonical glyph is U+210E PLANCK CONSTANT.
    static let italic = StyleTable(
        upperBase: 0x1D434, lowerBase: 0x1D44E, digitBase: nil,
        exceptions: ["h": "\u{210E}"]
    )

    // Math Bold Italic — Serif Bold Italic (𝑨-𝒛).
    static let boldItalic = StyleTable(
        upperBase: 0x1D468, lowerBase: 0x1D482
    )

    // Math Script (𝒜-𝓏). Several capitals + lowercase letters are reserved;
    // canonical glyphs live in the Letterlike Symbols block.
    static let script = StyleTable(
        upperBase: 0x1D49C, lowerBase: 0x1D4B6, digitBase: nil,
        exceptions: [
            "B": "\u{212C}", "E": "\u{2130}", "F": "\u{2131}", "H": "\u{210B}",
            "I": "\u{2110}", "L": "\u{2112}", "M": "\u{2133}", "R": "\u{211B}",
            "e": "\u{212F}", "g": "\u{210A}", "o": "\u{2134}"
        ]
    )

    // Math Bold Script (𝓐-𝔃).
    static let boldScript = StyleTable(
        upperBase: 0x1D4D0, lowerBase: 0x1D4EA
    )

    // Math Fraktur (𝔄-𝔷). A handful of capitals are reserved.
    static let fraktur = StyleTable(
        upperBase: 0x1D504, lowerBase: 0x1D51E, digitBase: nil,
        exceptions: [
            "C": "\u{212D}", "H": "\u{210C}", "I": "\u{2111}",
            "R": "\u{211C}", "Z": "\u{2128}"
        ]
    )

    // Math Bold Fraktur (𝕬-𝖟).
    static let boldFraktur = StyleTable(
        upperBase: 0x1D56C, lowerBase: 0x1D586
    )

    // Math Double-struck — Blackboard Bold (𝔸-𝕫, 𝟘-𝟡). Several capitals
    // are pre-existing (ℂ, ℍ, ℕ, ℙ, ℚ, ℝ, ℤ).
    static let doubleStruck = StyleTable(
        upperBase: 0x1D538, lowerBase: 0x1D552, digitBase: 0x1D7D8,
        exceptions: [
            "C": "\u{2102}", "H": "\u{210D}", "N": "\u{2115}", "P": "\u{2119}",
            "Q": "\u{211A}", "R": "\u{211D}", "Z": "\u{2124}"
        ]
    )

    // Math Sans-serif (𝖠-𝗓, 𝟢-𝟫).
    static let sans = StyleTable(
        upperBase: 0x1D5A0, lowerBase: 0x1D5BA, digitBase: 0x1D7E2
    )

    // Math Sans-serif Bold (𝗔-𝘇, 𝟬-𝟵).
    static let sansBold = StyleTable(
        upperBase: 0x1D5D4, lowerBase: 0x1D5EE, digitBase: 0x1D7EC
    )

    // Math Sans-serif Italic (𝘈-𝘻).
    static let sansItalic = StyleTable(
        upperBase: 0x1D608, lowerBase: 0x1D622
    )

    // Math Sans-serif Bold Italic (𝙰-𝙯).
    static let sansBoldItalic = StyleTable(
        upperBase: 0x1D63C, lowerBase: 0x1D656
    )

    // Math Monospace (𝙰-𝚣, 𝟶-𝟿).
    static let monospace = StyleTable(
        upperBase: 0x1D670, lowerBase: 0x1D68A, digitBase: 0x1D7F6
    )

    // Halfwidth and Fullwidth Forms (Ａ-ｚ, ０-９). Space → U+3000 ideographic.
    static let fullwidth = StyleTable(
        upperBase: 0xFF21, lowerBase: 0xFF41, digitBase: 0xFF10,
        exceptions: [" ": "\u{3000}"]
    )

    // Small Caps — IPA glyphs that render as miniature uppercase. Only
    // lowercase a-z gets mapped; uppercase stays itself, digits unchanged.
    static let smallCaps: StyleTable = {
        let lookup: [Character: String] = [
            "a": "ᴀ", "b": "ʙ", "c": "ᴄ", "d": "ᴅ", "e": "ᴇ", "f": "ꜰ",
            "g": "ɢ", "h": "ʜ", "i": "ɪ", "j": "ᴊ", "k": "ᴋ", "l": "ʟ",
            "m": "ᴍ", "n": "ɴ", "o": "ᴏ", "p": "ᴘ", "q": "ǫ", "r": "ʀ",
            "s": "s", "t": "ᴛ", "u": "ᴜ", "v": "ᴠ", "w": "ᴡ", "x": "x",
            "y": "ʏ", "z": "ᴢ"
        ]
        return StyleTable(upperBase: nil, lowerBase: nil, digitBase: nil,
                          exceptions: lookup)
    }()

    // Enclosed Alphanumerics — Circled outlined (Ⓐ-Ⓩ, ⓐ-ⓩ, ⓪-⑨).
    static let circled = StyleTable(
        upperBase: 0x24B6, lowerBase: 0x24D0, digitBase: nil,
        exceptions: [
            "0": "\u{24EA}",
            "1": "\u{2460}", "2": "\u{2461}", "3": "\u{2462}",
            "4": "\u{2463}", "5": "\u{2464}", "6": "\u{2465}",
            "7": "\u{2466}", "8": "\u{2467}", "9": "\u{2468}"
        ]
    )

    // Enclosed Alphanumeric Supplement — Negative Circled / filled.
    // Lowercase has no canonical filled-circle form; lowercase falls back
    // to uppercase mapping for visual consistency.
    static let filledCircled: StyleTable = {
        var upper: [Character: String] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            if let scalar = Unicode.Scalar(0x1F150 + UInt32(i)) {
                upper[c] = String(scalar)
            }
        }
        var lower: [Character: String] = [:]
        for c in "abcdefghijklmnopqrstuvwxyz" {
            let upperEquiv = Character(c.uppercased())
            if let mapped = upper[upperEquiv] {
                lower[c] = mapped
            }
        }
        var digits: [Character: String] = [
            "0": "\u{24FF}",
            "1": "\u{2776}", "2": "\u{2777}", "3": "\u{2778}",
            "4": "\u{2779}", "5": "\u{277A}", "6": "\u{277B}",
            "7": "\u{277C}", "8": "\u{277D}", "9": "\u{277E}"
        ]
        var merged: [Character: String] = [:]
        upper.forEach   { merged[$0.key] = $0.value }
        lower.forEach   { merged[$0.key] = $0.value }
        digits.forEach  { merged[$0.key] = $0.value }
        return StyleTable(upperBase: nil, lowerBase: nil, digitBase: nil,
                          exceptions: merged)
    }()

    // Enclosed Alphanumeric Supplement — Squared (🄰-🅉).
    // Uppercase only; lowercase falls back to uppercase form.
    static let squared: StyleTable = {
        var upper: [Character: String] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            if let scalar = Unicode.Scalar(0x1F130 + UInt32(i)) {
                upper[c] = String(scalar)
            }
        }
        var lower: [Character: String] = [:]
        for c in "abcdefghijklmnopqrstuvwxyz" {
            let upperEquiv = Character(c.uppercased())
            if let mapped = upper[upperEquiv] {
                lower[c] = mapped
            }
        }
        var merged: [Character: String] = [:]
        upper.forEach { merged[$0.key] = $0.value }
        lower.forEach { merged[$0.key] = $0.value }
        return StyleTable(upperBase: nil, lowerBase: nil, digitBase: nil,
                          exceptions: merged)
    }()

    // Enclosed Alphanumeric Supplement — Negative Squared / filled (🅰-🆉).
    static let filledSquared: StyleTable = {
        var upper: [Character: String] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            if let scalar = Unicode.Scalar(0x1F170 + UInt32(i)) {
                upper[c] = String(scalar)
            }
        }
        var lower: [Character: String] = [:]
        for c in "abcdefghijklmnopqrstuvwxyz" {
            let upperEquiv = Character(c.uppercased())
            if let mapped = upper[upperEquiv] {
                lower[c] = mapped
            }
        }
        var merged: [Character: String] = [:]
        upper.forEach { merged[$0.key] = $0.value }
        lower.forEach { merged[$0.key] = $0.value }
        return StyleTable(upperBase: nil, lowerBase: nil, digitBase: nil,
                          exceptions: merged)
    }()

}

// MARK: - Upside-down map

/// Each ASCII letter / digit / punctuation glyph maps to its rotated
/// counterpart so the resulting string, when read right-to-left and rotated
/// 180°, reads naturally. The mapping is intentionally lossy — "a" and "ɐ"
/// don't NFKC-collapse, so the reverse pass uses `customReverse` to undo it.
private let upsideDownMap: [Character: Character] = [
    "a": "ɐ", "b": "q", "c": "ɔ", "d": "p", "e": "ǝ", "f": "ɟ",
    "g": "ƃ", "h": "ɥ", "i": "ᴉ", "j": "ɾ", "k": "ʞ", "l": "l",
    "m": "ɯ", "n": "u", "o": "o", "p": "d", "q": "b", "r": "ɹ",
    "s": "s", "t": "ʇ", "u": "n", "v": "ʌ", "w": "ʍ", "x": "x",
    "y": "ʎ", "z": "z",

    "A": "∀", "B": "𐐒", "C": "Ɔ", "D": "p", "E": "Ǝ", "F": "Ⅎ",
    "G": "פ", "H": "H", "I": "I", "J": "ſ", "K": "ʞ", "L": "˥",
    "M": "W", "N": "N", "O": "O", "P": "Ԁ", "Q": "Q", "R": "ᴿ",
    "S": "S", "T": "⊥", "U": "∩", "V": "Λ", "W": "M", "X": "X",
    "Y": "⅄", "Z": "Z",

    "0": "0", "1": "Ɩ", "2": "ᄅ", "3": "Ɛ", "4": "ㄣ",
    "5": "ϛ", "6": "9", "7": "ㄥ", "8": "8", "9": "6",

    ".": "˙", ",": "‘", "?": "¿", "!": "¡", "'": ",",
    "\"": "„", "(": ")", ")": "(", "[": "]", "]": "[",
    "{": "}", "}": "{", "<": ">", ">": "<", "&": "⅋",
    "_": "‾", ";": "؛"
]

// MARK: - Reverse lookup for normalize()

/// Reverse map used by `UnicodeStylizer.normalize` after NFKC. Built once
/// from upside-down + small-caps exceptions (NFKC doesn't collapse these).
///
/// Critical invariant: keys MUST be non-ASCII glyphs. Some upside-down
/// pairs use plain ASCII letters as the "fancy" form (e.g. `b: q` plus
/// `q: b`, where both forward mappings happen to swap two normal
/// ASCII letters). Adding such an entry to the reverse map would corrupt
/// every plain `q` / `b` / `d` / `p` / `n` / `u` that NFKC produced from
/// a Math Bold / Script / etc. character — turning "the quick" into
/// "the bnick", "and" into "auq", and so on. The `fancy.isASCII` guard
/// below filters those self-swapping pairs out of the reverse map.
private let customReverse: [Character: Character] = {
    var map: [Character: Character] = [:]
    for (plain, fancy) in upsideDownMap {
        // Skip entries whose fancy form is itself a plain ASCII letter /
        // digit. NFKC of Math Bold etc. produces plain ASCII, and we must
        // not re-rewrite those plain characters during the reverse pass.
        if fancy.isASCII { continue }
        // Multiple plain chars can share an upside-down glyph; keep the
        // first encountered to avoid clobbering the canonical direction.
        if map[fancy] == nil { map[fancy] = plain }
    }
    // Small caps lowercase glyphs.
    let smallCaps: [(String, Character)] = [
        ("ᴀ", "a"), ("ʙ", "b"), ("ᴄ", "c"), ("ᴅ", "d"), ("ᴇ", "e"),
        ("ꜰ", "f"), ("ɢ", "g"), ("ʜ", "h"), ("ɪ", "i"), ("ᴊ", "j"),
        ("ᴋ", "k"), ("ʟ", "l"), ("ᴍ", "m"), ("ɴ", "n"), ("ᴏ", "o"),
        ("ᴘ", "p"), ("ǫ", "q"), ("ʀ", "r"), ("ᴛ", "t"), ("ᴜ", "u"),
        ("ᴠ", "v"), ("ᴡ", "w"), ("ʏ", "y"), ("ᴢ", "z")
    ]
    for (sc, plain) in smallCaps {
        if let ch = sc.first { map[ch] = plain }
    }
    return map
}()
