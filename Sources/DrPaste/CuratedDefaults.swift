//
//  CuratedDefaults.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Curated default-enabled subset of built-in actions.
//  Goal: on first install the user sees only the immediately useful actions for
//  each content type (about 5-10 per type); the rest remain available but
//  disabled and can be turned on manually in Settings. This addresses the
//  "too many actions" feedback.
//

import Foundation

enum CuratedDefaults {
    /// Default-enabled actions on first launch (#A74 / 0.56.0 convention v2:
    /// `<namespace>.<content_kind>.<verb_noun>`). Anything not in this set
    /// starts disabled. Per-user config.enabledFlags takes precedence.
    static let enabledByDefault: Set<String> = [
        // Universal anchor (no category — applies to everything).
        "builtin.identity",                       // Paste as is

        // Rich — strip formatting (replaces the old paste_as_text +
        // clean_formatting duplicate pair).
        "builtin.rich.strip_formatting",

        // Text — case (core 2).
        "builtin.text.uppercase",
        "builtin.text.lowercase",

        // Text — whitespace / lines. "Tidy text" (builtin.text.trim) is now
        // the one universal cleanup: it trims, normalises spacing, collapses
        // blank lines AND reflows PDF-wrapped lines, so sort_lines (niche) and
        // remove_line_breaks (merged) are OFF by default.
        "builtin.text.trim",

        // Text — derived.
        "builtin.text.word_count",
        "builtin.text.unit_conversion",
        "builtin.text.generate_qr",
        // Text — wrap (#A74 new).
        "builtin.text.wrap_quotes",

        // URL — decode is common.
        "builtin.url.decode",

        // HTML / extraction (curated subset from 0.55). The universal
        // "Extract links" (text.extract_links, gated by containsURLs) is the
        // one kept on — the markdown-only md.extract_links duplicate is off.
        "builtin.html.strip_tags",
        "builtin.text.extract_emails",
        "builtin.text.extract_links",

        // Text — transliteration. Cyrillic→Latin is curated everywhere
        // (honest trigger: containsCyrillic). Latin→Cyrillic's default is
        // locale-aware (#A77) — handled in `isEnabledByDefault`, not listed
        // here, because Latin text is ubiquitous and the action is only
        // routinely wanted by Cyrillic-script users.
        "builtin.text.cyrillic_to_latin",

        // Text — Unicode pseudo-fonts. Only the handful that are genuinely
        // useful + visually striking are ON by default; the long tail (sans
        // variants, fraktur, double-struck, circled/squared, upside-down, …)
        // stays available but OFF so the HUD isn't buried under 20 near-
        // identical "fancy text" rows. `font_plain` is gone from the defaults
        // entirely — the universal "Plain text" cleaner now denormalises
        // Unicode styling, so a dedicated reverse action is redundant.
        "builtin.text.font_bold",
        "builtin.text.font_italic",
        "builtin.text.font_bold_italic",
        "builtin.text.font_script",
        "builtin.text.font_monospace",
        "builtin.text.font_small_caps",

        // Text — type slowly bypass.
        "builtin.text.type_slowly",

        // Rich — all four direction-out converters.
        "builtin.rich.to_md",
        "builtin.rich.to_html",
        "builtin.rich.to_wiki",
        "builtin.rich.to_unicode_styled",

        // URL — core 4.
        "builtin.url.strip_tracking",
        "builtin.url.extract_domain",
        "builtin.url.preview_card",

        // JSON — `json.pretty` is OFF by default: "Pretty Code (local)" now
        // covers JSON with byte-identical output, so the dedicated action is
        // redundant.
        "builtin.json.minify",
        "builtin.json.extract_keys",
        "builtin.json.validate",

        // Table — all 5 (narrow category, all useful).
        "builtin.table.to_json",
        "builtin.table.to_md",
        "builtin.table.to_wiki",
        "builtin.table.to_rich",

        // Markdown — core. `md.to_plain` is OFF by default: the universal
        // "Plain text" cleaner now also strips Markdown, so it's redundant.
        "builtin.md.to_rich",
        "builtin.md.to_wiki",
        "builtin.md.extract_headings",

        // Code — core. Indentation flips (tabs_to_spaces / spaces_to_tabs) are
        // OFF by default: Pretty Code (local) handles indentation as part of
        // formatting, so the standalone flips just clutter the Code tab.
        "builtin.code.wrap_block",
        "builtin.code.pretty_local",

        // Image — core 10 (the strong defaults).
        "builtin.image.ocr",
        "builtin.image.decode_qr",
        "builtin.image.info",
        "builtin.image.strip_metadata",
        "builtin.image.to_grayscale",
        "builtin.image.rotate_right",
        "builtin.image.rotate_left",
        "builtin.image.to_ascii_art",
        "builtin.image.resize",

        // Files — all 6 (narrow + #A74 new).
        "builtin.files.copy_paths",
        "builtin.files.copy_filenames",
        "builtin.files.copy_shell_safe_paths",    // #A74 new
        "builtin.files.to_md_links",
        "builtin.files.to_rich_icons",            // #A74 new
        "builtin.files.reveal_in_finder",
        "builtin.files.extract_image"

        // NOTE: AI seeds (ids beginning with `ai.`) are managed via their
        // descriptor `enabled` flag (defaults true), not this table.
        // `isEnabledByDefault` handles both prefixes.

        // NOT curated by design:
        //   • Fun / Internet Slang (leetspeak / uwu / zalgo) — palette
        //     only so default chip strip stays serious.
        //   • HTML escape / unescape — niche.
        //   • normalize_spaces / collapse_blank_lines — overlap with
        //     remove_line_breaks; ship in palette.
        //   • extract_links — md_extract_links covers markdown clips.
        //   • table.to_html — niche CMS workflow.
        //   • text.wrap_parens — wrap_quotes covers the common case.
        //   • case ops beyond UPPER/lower, encoding ops, font_markdown —
        //     all in palette.
    ]

    /// Available in the palette but disabled by default: other case-, encode/decode-,
    /// snake/kebab/camel-case, Base64, slugify, sentence case, Title Case, Fix keyboard layout,
    /// standalone trim, standalone clean formatting, html_link, query_params, json_flatten,
    /// json_nulls, md_extract_links, spaces_to_tabs, image_rotate, image_invert,
    /// image_compress, sha256, bash_list, parent_folder, file_paths_html, and so on.
    /// AI seeds that ship OFF by default — novelty / niche / expensive. The
    /// core writing, code-understanding and OCR-cleanup AI actions stay on; the
    /// rest are discoverable in the list but don't clutter the HUD.
    static let aiOffByDefault: Set<String> = [
        "ai.text.ipa_transcription",     // phonetic transcription (niche)
        "ai.text.latin_to_cyrillic",     // local sibling covers 80%
        "ai.code.translate",             // requires a target language
        "ai.code.pretty",                // local "Pretty Code" covers it
        "ai.image.sketch", "ai.image.watercolor", "ai.image.cartoon",
        "ai.text.image_whiteboard"       // text→image styles (generate cost)
    ]

    static func isEnabledByDefault(_ actionID: String) -> Bool {
        // AI seeds: on by default EXCEPT the curated novelty/niche set.
        if actionID.hasPrefix("ai.") { return !aiOffByDefault.contains(actionID) }
        // User-created custom actions are always default-enabled.
        if actionID.hasPrefix("user.") { return true }
        // #A77 — Latin→Cyrillic is curated-on only for Cyrillic-script users.
        // (Cyrillic→Latin has an honest content trigger and is on everywhere.)
        if actionID == "builtin.text.latin_to_cyrillic" { return localePrefersCyrillic }
        return enabledByDefault.contains(actionID)
    }

    /// True when any of the user's preferred languages is written in
    /// Cyrillic. An explicit Latin script subtag (e.g. `sr-Latn`, `kk-Latn`)
    /// is respected and excluded. Computed once.
    static let localePrefersCyrillic: Bool = {
        let cyrillicCodes: Set<String> = [
            "ru", "uk", "be", "bg", "sr", "mk", "kk", "ky", "tg", "mn",
            "tt", "ba", "cv", "ce", "ab", "os", "kv", "sah", "tk", "cu"
        ]
        for lang in Locale.preferredLanguages {
            let l = Locale.Language(identifier: lang)
            if let script = l.script?.identifier {
                if script == "Cyrl" { return true }
                if script == "Latn" { continue }
            }
            let code = (l.languageCode?.identifier ?? String(lang.prefix(2))).lowercased()
            if cyrillicCodes.contains(code) { return true }
        }
        return false
    }()
}
