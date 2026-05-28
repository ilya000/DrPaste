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

        // Rich text — all three (narrow category).
        "builtin.rich_to_md",
        "builtin.rich_to_html",
        "builtin.rich_to_wiki",

        // URL — core 3.
        "builtin.url_strip_tracking",
        "builtin.url_just_domain",
        "builtin.url_decode",                // decode is common; encode lives in the palette.

        // JSON — core 3.
        "builtin.json_pretty",
        "builtin.json_minify",
        "builtin.json_extract_keys",

        // Table — core 2.
        "builtin.table_to_json",
        "builtin.table_to_md",

        // Markdown — core 2.
        "builtin.md_to_plain",
        "builtin.md_extract_headings",

        // Code — core 2.
        "builtin.code_wrap",
        "builtin.tabs_to_spaces",

        // Image — core 5.
        "builtin.image_ocr",
        "builtin.image_decode_qr",
        "builtin.image_strip_metadata",
        "builtin.image_resize_1920",
        "builtin.image_grayscale",

        // Files — core 4.
        "builtin.files_paths",
        "builtin.files_names",
        "builtin.files_md_links",
        "builtin.files_reveal",

        // Type Slowly (optional, useful for forms that block paste).
        "builtin.type_slowly"

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
