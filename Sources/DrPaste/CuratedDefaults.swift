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

        // Text — whitespace / lines (core 2 + #A74 join).
        "builtin.text.sort_lines",
        "builtin.text.remove_line_breaks",        // #A74 new

        // Text — derived.
        "builtin.text.word_count",
        "builtin.text.unit_conversion",
        "builtin.text.generate_qr",
        // Text — wrap (#A74 new).
        "builtin.text.wrap_quotes",

        // URL — decode is common.
        "builtin.url.decode",

        // HTML / extraction (curated subset from 0.55).
        "builtin.html.strip_tags",
        "builtin.text.extract_emails",

        // Text — transliteration.
        "builtin.text.cyrillic_to_latin",
        "builtin.text.latin_to_cyrillic",

        // Text — Unicode pseudo-fonts (all 22).
        "builtin.text.font_bold",
        "builtin.text.font_italic",
        "builtin.text.font_bold_italic",
        "builtin.text.font_script",
        "builtin.text.font_bold_script",
        "builtin.text.font_fraktur",
        "builtin.text.font_bold_fraktur",
        "builtin.text.font_double_struck",
        "builtin.text.font_sans",
        "builtin.text.font_sans_bold",
        "builtin.text.font_sans_italic",
        "builtin.text.font_sans_bold_italic",
        "builtin.text.font_monospace",
        "builtin.text.font_fullwidth",
        "builtin.text.font_small_caps",
        "builtin.text.font_circled",
        "builtin.text.font_filled_circled",
        "builtin.text.font_squared",
        "builtin.text.font_filled_squared",
        "builtin.text.font_upside_down",
        "builtin.text.font_plain",

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

        // JSON — core 4.
        "builtin.json.pretty",
        "builtin.json.minify",
        "builtin.json.extract_keys",
        "builtin.json.validate",

        // Table — all 5 (narrow category, all useful).
        "builtin.table.to_json",
        "builtin.table.to_md",
        "builtin.table.to_wiki",
        "builtin.table.to_rich",

        // Markdown — core 3.
        "builtin.md.to_plain",
        "builtin.md.to_rich",
        "builtin.md.extract_headings",

        // Code — core 3.
        "builtin.code.wrap_block",
        "builtin.code.tabs_to_spaces",
        "builtin.code.pretty_local",

        // Image — core 10 (the strong defaults).
        "builtin.image.ocr",
        "builtin.image.decode_qr",
        "builtin.image.strip_metadata",
        "builtin.image.resize_max_1920",
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
    static func isEnabledByDefault(_ actionID: String) -> Bool {
        // AI seeds (`ai.*`) and user-created custom actions (`user.*`)
        // are always default-enabled.
        if actionID.hasPrefix("ai.") || actionID.hasPrefix("user.") { return true }
        return enabledByDefault.contains(actionID)
    }
}
