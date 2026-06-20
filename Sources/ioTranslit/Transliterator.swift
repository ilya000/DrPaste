import Foundation

/// Deterministic, offline, bidirectional Latin ↔ Cyrillic transliteration across 14
/// languages plus the neutral Interslavic fallback. Each direction can take an explicit
/// language (by ISO-ish code — `ru`, `uk`/`ua`, `sr`, `bg`, … — or full id like `russian`),
/// or `nil` to auto-detect from the text (with an optional `prefer` hint, e.g. the host's
/// active keyboard layout, used to break ties). Case is preserved per word run.
public enum Transliterator {

    /// A supported language: stable `id` (e.g. "russian") + display `name`.
    public struct Language: Equatable { public let id: String; public let name: String }

    /// All supported languages, by descending prevalence. (Excludes the synthetic
    /// `interslavic` target, which is only a Latin→Cyrillic fallback, not a detectable one.)
    public static let languages: [Language] =
        CyrillicModel.langs.map { Language(id: $0.id, name: $0.name) }

    /// Override the locale-derived tie-break language id (nil = recompute from system).
    /// Hosts that know the user's context can set this once; tests pin it for determinism.
    public static var localeLanguageID: String? {
        get { CyrillicModel.localePreferredID }
        set { CyrillicModel.localePreferredID = newValue.flatMap(internalID) }
    }

    // MARK: Latin → Cyrillic

    /// Transliterate Latin → Cyrillic.
    /// - target: language code/id, or nil to auto-detect from `text`.
    /// - prefer: code/id hint used only to break ambiguity when `target` is nil.
    public static func latinToCyrillic(_ text: String, target: String? = nil,
                                       prefer: String? = nil) -> String {
        let resolved = internalID(target)
            ?? CyrillicModel.autoDetectLatinTarget(text, prefer: internalID(prefer))
        return CyrillicModel.latToCyr(text, target: resolved)
    }

    /// One plausible Latin→Cyrillic reading. `variants` records the non-base choices it made
    /// (source Latin token → Cyrillic), so a host can learn the user's habit and rank by it.
    public struct Candidate: Equatable {
        public let text: String
        public let variants: [String: String]
    }

    /// All plausible Latin→Cyrillic readings of `text` for `target`, under the standard map PLUS the
    /// scheme alternatives (the translit "zoo": w→ш, x→х|ь, …). Base reading first, then variants;
    /// capped at `max`. The host gates each (real word?) and picks, optionally by learned habit.
    public static func latinToCyrillicCandidates(_ text: String, target: String,
                                                 max: Int = 16) -> [Candidate] {
        guard let tgt = internalID(target) else { return [] }
        let base = CyrillicModel.lat2cyrMap(for: tgt)
        let alts = CyrillicModel.lat2cyrAlternatives(for: tgt)
        let digraphs = CyrillicModel.lat2cyrDigraphs(for: tgt)
        return CyrillicModel.candidates(text, base: base, alts: alts, digraphs: digraphs, max: max)
            .map { Candidate(text: $0.text, variants: $0.variants) }
    }

    // MARK: Cyrillic → Latin

    /// Transliterate Cyrillic → Latin.
    /// - source: language code/id, or nil to auto-detect from `text`.
    /// - prefer: code/id hint used only to break ambiguity when `source` is nil.
    public static func cyrillicToLatin(_ text: String, source: String? = nil,
                                       prefer: String? = nil) -> String {
        let lang: CyrillicLang = internalID(source).map(CyrillicModel.lang(id:))
            ?? CyrillicModel.detect(text, prefer: internalID(prefer))
        return CyrillicModel.cyrToLat(text, lang: lang)
    }

    // MARK: detection (exposed for hosts that want to label the result)

    /// The language id auto-detected for Cyrillic→Latin on `text`.
    public static func detectCyrillic(_ text: String, prefer: String? = nil) -> String {
        CyrillicModel.detect(text, prefer: internalID(prefer)).id
    }

    /// The target language id auto-detected for Latin→Cyrillic on `text`.
    public static func detectLatinTarget(_ text: String, prefer: String? = nil) -> String {
        CyrillicModel.autoDetectLatinTarget(text, prefer: internalID(prefer))
    }

    /// `true` if `text` already contains Cyrillic letters (helps a caller pick a direction).
    public static func looksCyrillic(_ text: String) -> Bool {
        text.contains { CyrillicModel.allLetters.contains(Character($0.lowercased())) }
    }

    /// Auto-direction: Cyrillic text → Latin, otherwise Latin → Cyrillic.
    public static func transliterate(_ text: String, prefer: String? = nil) -> String {
        looksCyrillic(text) ? cyrillicToLatin(text, prefer: prefer)
                            : latinToCyrillic(text, prefer: prefer)
    }

    // MARK: helpers

    /// Normalize a public code/id to an internal language id. nil/empty/"auto" → nil
    /// (meaning "detect"). Accepts `ua` as an alias for Ukrainian and any full id verbatim.
    static func internalID(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased(),
              !s.isEmpty, s != "auto" else { return nil }
        if s == "interslavic" { return "interslavic" }
        if let id = CyrillicModel.codeToID[s] { return id }
        if CyrillicModel.langs.contains(where: { $0.id == s }) { return s }
        return s            // unknown → pass through (lang(id:) falls back to Russian)
    }
}
