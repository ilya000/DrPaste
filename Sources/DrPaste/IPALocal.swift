//
//  IPALocal.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Local, offline English → IPA phonetic transcription. Looks each word up in
//  a bundled 126k-word dictionary derived from CMUdict (ARPAbet → IPA, with
//  onset-based primary/secondary stress marks). Unknown words pass through
//  unchanged. Aimed at English learners — the most-studied language — for whom
//  an instant offline pronunciation guide is the common case. The multilingual
//  / proper-noun long tail stays on the AI action (`ai.text.ipa_transcription`).
//
//  The dictionary lives as a bundled RESOURCE FILE (cmudict-ipa.txt), not in
//  the binary, and is loaded ON DEMAND inside `apply` — never cached resident,
//  since this action runs only occasionally and the map would otherwise hold
//  ~tens of MB of RAM for the whole session for nothing.
//

import Foundation
import NaturalLanguage

enum IPALocal {

    /// How a transcription is rendered (mirrors the Convert-units append/replace
    /// choice). `.annotate` keeps each English word and adds its IPA in square
    /// brackets after it ("The [ðə] quick [ˈkwɪk]"); `.replace` swaps the word
    /// for its IPA ("ðə ˈkwɪk").
    enum Mode { case annotate, replace }

    /// URL of the bundled dictionary resource, if present.
    static func resourceURL() -> URL? {
        Bundle.module.url(forResource: "cmudict-ipa", withExtension: "txt")
    }

    /// Cheap presence check (no parse) — the resource file exists in the bundle.
    static var isAvailable: Bool { resourceURL() != nil }

    /// Parse the resource into a word → IPA map. Call once per transcription and
    /// let the result deallocate afterwards (no resident cache).
    static func loadDictionary() -> [String: String] {
        guard let url = resourceURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        map.reserveCapacity(130_000)
        for line in text.split(separator: "\n") {
            let pair = line.split(separator: "\t", maxSplits: 1)
            if pair.count == 2 { map[String(pair[0])] = String(pair[1]) }
        }
        return map
    }

    /// Transcribe `text` using a preloaded `dict`: known words become their IPA,
    /// unknown words pass through unchanged, punctuation / whitespace preserved.
    /// Returns the rendered string and how many words were transcribed.
    static func transcribe(_ text: String, using dict: [String: String],
                           mode: Mode = .annotate) -> (result: String, hits: Int) {
        var out = ""
        out.reserveCapacity(text.count * 2)
        var word = ""
        var hits = 0

        func isApos(_ c: Character) -> Bool { c == "'" || c == "\u{2019}" }

        func flush() {
            guard !word.isEmpty else { return }
            // Peel leading/trailing apostrophes (used as quotes around a word) off
            // the lookup core; keep INTERNAL ones (contractions like "don't").
            var core = Substring(word)
            var lead = "", trail = ""
            while let f = core.first, isApos(f) { lead.append(f); core = core.dropFirst() }
            while let l = core.last,  isApos(l) { trail = String(l) + trail; core = core.dropLast() }
            // CMUdict keys use a straight apostrophe; normalise the curly one.
            let key = core.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            if !core.isEmpty, let ipa = dict[key] {
                hits += 1
                switch mode {
                case .replace:  out += lead + ipa + trail
                case .annotate: out += word + " [" + ipa + "]"
                }
            } else {
                out += word   // unknown word — pass through unchanged in both modes
            }
            word.removeAll(keepingCapacity: true)
        }

        for ch in text {
            if ch.isLetter || ch == "'" || ch == "\u{2019}" {
                word.append(ch)
            } else {
                flush()
                out.append(ch)
            }
        }
        flush()
        return (out, hits)
    }

    /// Convenience: load + transcribe in one call (loads the resource each time).
    static func transcribe(_ text: String, mode: Mode = .annotate) -> (result: String, hits: Int) {
        transcribe(text, using: loadDictionary(), mode: mode)
    }
}

/// Per-action choice of how the local IPA action renders: annotate (default —
/// word + [IPA]) or replace (word → IPA). Stored per action ID, mirrors
/// `UnitConversionSettings`.
enum IPALocalSettings {
    private static func key(_ id: String) -> String { "drpaste.ipa.replaceMode.\(id)" }

    /// false (default) = annotate "The [ðə]"; true = replace "ðə".
    static func replaceMode(for id: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))
    }
    static func setReplaceMode(_ replace: Bool, for id: String) {
        UserDefaults.standard.set(replace, forKey: key(id))
    }
}

// MARK: - ClipboardAction

struct IPALocalAction: ClipboardAction {
    let id = "builtin.text.ipa_local"
    let title = "/aɪ/  English IPA"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard item.semantic == .text || item.semantic == .richText
                || item.semantic == .markdown else { return false }
        guard let text = item.previewText, !text.isEmpty else { return false }
        // Must carry ASCII Latin letters to have anything to transcribe.
        guard text.contains(where: { $0.isLetter && $0.isASCII }) else { return false }
        // Language gate — English only. Bounded sample keeps this cheap; the
        // heavy dictionary is NOT touched here, only in apply().
        let sample = String(text.prefix(1000))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let lang = recognizer.dominantLanguage {
            return lang == .english
        }
        // Undetermined (very short input) → allow; apply() no-ops if no match.
        return true
    }

    /// Type-only membership for the editor's "Applies to" grid — drop the
    /// English gate so it reports text / rich text / markdown (Codex #9 shape).
    func appliesToContentType(item: ClipboardItem, context: ContentContext) -> Bool {
        item.semantic == .text || item.semantic == .richText || item.semantic == .markdown
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let text = item.previewText, !text.isEmpty else {
            return .failed(original: item, reason: "English IPA: empty text.", recovery: nil)
        }
        let mode: IPALocal.Mode = IPALocalSettings.replaceMode(for: id) ? .replace : .annotate
        let (rendered, hits) = await runOffMain {
            IPALocal.transcribe(text, mode: mode)   // loads on demand, releases after
        }
        guard hits > 0 else {
            return .failed(original: item,
                           reason: "English IPA: no known English words found.",
                           recovery: nil)
        }
        return .preview(makeTextItem(rendered, from: item))
    }
}
