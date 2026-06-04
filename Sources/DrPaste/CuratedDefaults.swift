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
    /// Default-enabled actions on first launch. Anything not in this set starts
    /// disabled. Per-user config.enabledFlags takes precedence over this set.
    static let enabledByDefault: Set<String> = [
        // Universal — always visible.
        "builtin.identity",                  // Paste as is (anchor).
        "builtin.paste_as_text",             // Combined clean + trim.

        // Plain text — core 5.
        "builtin.uppercase",
        "builtin.lowercase",
        "builtin.sort_lines",
        "builtin.word_count",
        "builtin.generate_qr",               // QR from URL.

        // Rich text — all four (narrow category).
        "builtin.rich_to_md",
        "builtin.rich_to_html",
        "builtin.rich_to_wiki",
        "builtin.rich_to_unicode_style",

        // URL — core 3.
        "builtin.url_strip_tracking",
        "builtin.url_just_domain",
        "builtin.url_decode",                // decode is common; encode lives in the palette.

        // JSON — core 3.
        "builtin.json_pretty",
        "builtin.json_minify",
        // The descriptor seeded by DefaultTransformationSeed is `builtin.json_keys`
        // (current ID); `builtin.json_extract_keys` is the legacy ID that some
        // older configs / tests still reference. Pointing the curated set at the
        // legacy ID would leave Extract Keys disabled by default for fresh
        // installs because the matching descriptor doesn't exist under that
        // name — caught by the test suite on a clean machine.
        "builtin.json_keys",

        // Table — core 2.
        "builtin.table_to_json",
        "builtin.table_to_md",

        // Markdown — core 3 (added md → rich).
        "builtin.md_to_plain",
        "builtin.md_to_rich",
        // Same legacy/current rename as the JSON case above: the seed
        // uses `builtin.md_headings`; `builtin.md_extract_headings`
        // is the legacy ID.
        "builtin.md_headings",

        // Code — core 2.
        "builtin.code_wrap",
        "builtin.tabs_to_spaces",

        // Image — core 8 (added ASCII art + Rotate left/right pair).
        "builtin.image_ocr",
        "builtin.image_decode_qr",
        "builtin.image_strip_metadata",
        "builtin.image_resize_1920",
        "builtin.image_grayscale",
        "builtin.image_rotate",         // right (90° CW)
        "builtin.image_rotate_left",    // left (90° CCW)
        "builtin.image_ascii_art",

        // NOTE: AI image styles (Pencil sketch / Watercolor / Cartoon)
        // are NOT listed here. They're CustomAIDescriptor entries
        // seeded with kind == .image, and their enabled flag lives on
        // the descriptor itself (which defaults to true) — same model
        // as the text AI defaults (Translate, Fix grammar). The
        // `actionID.hasPrefix("user.")` arm in isEnabledByDefault below
        // covers them on the rare path where curated defaults are
        // consulted for a customAI id.

        // Files — core 4.
        "builtin.files_paths",
        "builtin.files_names",
        "builtin.files_md_links",
        "builtin.files_reveal",

        // Type Slowly (optional, useful for forms that block paste).
        "builtin.type_slowly",

        // Unicode pseudo-font family — "Font: <style>". All on by default per
        // the marketing brief; user can disable individual styles in Settings.
        "builtin.font_bold",
        "builtin.font_italic",
        "builtin.font_bold_italic",
        "builtin.font_script",
        "builtin.font_bold_script",
        "builtin.font_fraktur",
        "builtin.font_bold_fraktur",
        "builtin.font_double_struck",
        "builtin.font_sans",
        "builtin.font_sans_bold",
        "builtin.font_sans_italic",
        "builtin.font_sans_bold_italic",
        "builtin.font_monospace",
        "builtin.font_fullwidth",
        "builtin.font_small_caps",
        "builtin.font_circled",
        "builtin.font_filled_circled",
        "builtin.font_squared",
        "builtin.font_filled_squared",
        "builtin.font_upside_down",
        "builtin.font_plain",

        // Cyrillic transliteration — small but high-utility helper for
        // Russian / Ukrainian / Belarusian / Bulgarian / Serbian /
        // Macedonian text needing romanization or Latin-only contexts.
        "builtin.cyrillic_translit"

        // AI actions (ids beginning with "ai.") are managed separately by the
        // provider registry; their enabled state does not flow through this table.
    ]

    /// Available in the palette but disabled by default: other case-, encode/decode-,
    /// snake/kebab/camel-case, Base64, slugify, sentence case, Title Case, Fix keyboard layout,
    /// standalone trim, standalone clean formatting, html_link, query_params, json_flatten,
    /// json_nulls, md_extract_links, spaces_to_tabs, image_rotate, image_invert,
    /// image_compress, sha256, bash_list, parent_folder, file_paths_html, and so on.
    static func isEnabledByDefault(_ actionID: String) -> Bool {
        // AI actions are always default-enabled to aid discovery.
        if actionID.hasPrefix("ai.") || actionID.hasPrefix("user.") { return true }
        return enabledByDefault.contains(actionID)
    }
}
