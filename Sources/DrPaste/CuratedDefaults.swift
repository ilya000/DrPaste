//
//  CuratedDefaults.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Curated default-enabled subset built-in actions (правка #8 lite).
//  Цель: при первой установке у пользователя видны только реально полезные actions
//  per content type (~5–10 штук), остальные доступны но disabled — включает вручную
//  через Settings if needed. Это решает "перегрузка списка actions" feedback.
//

import Foundation

enum CuratedDefaults {
    /// Default-enabled actions при первом запуске. Всё что не в этом set'е — disabled.
    /// Пользовательский config.enabledFlags имеет приоритет.
    static let enabledByDefault: Set<String> = [
        // Универсальные — всегда видны
        "builtin.identity",                  // Paste as is (anchor)
        "builtin.paste_as_text",             // ★ combined clean+trim

        // Plain text — core 5
        "builtin.uppercase",
        "builtin.lowercase",
        "builtin.sort_lines",
        "builtin.word_count",
        "builtin.generate_qr",               // ★ QR из URL

        // Rich text — все 3 (узкая категория)
        "builtin.rich_to_md",
        "builtin.rich_to_html",
        "builtin.rich_to_wiki",

        // URL — core 3
        "builtin.url_strip_tracking",
        "builtin.url_just_domain",
        "builtin.url_decode",                // decode частый, encode — в palette

        // JSON — core 3
        "builtin.json_pretty",
        "builtin.json_minify",
        "builtin.json_extract_keys",

        // Table — core 3
        "builtin.table_to_json",
        "builtin.table_to_md",
        "builtin.table_transpose",

        // Markdown — core 2
        "builtin.md_to_plain",
        "builtin.md_extract_headings",

        // Code — core 2
        "builtin.code_wrap",
        "builtin.tabs_to_spaces",

        // Image — core 5
        "builtin.image_ocr",
        "builtin.image_decode_qr",
        "builtin.image_strip_metadata",
        "builtin.image_resize_1920",
        "builtin.image_grayscale",

        // Files — core 5
        "builtin.files_paths",
        "builtin.files_names",
        "builtin.files_md_links",
        "builtin.files_size",
        "builtin.files_reveal",

        // Type Slowly (опциональный, но нужен для anti-paste forms)
        "builtin.type_slowly"

        // AI actions (id "ai.*") — управляются отдельно через registry,
        // их enabled state не идёт через эту таблицу.
    ]

    /// В palette (можно добавить вручную через Settings): остальные case-, encode/decode-,
    /// snake/kebab/camel-case, Base64, slugify, sentence case, Title Case, Fix keyboard layout,
    /// trim alone, clean formatting alone, html_link, query_params, json_flatten, json_nulls,
    /// md_extract_links, spaces_to_tabs, image_rotate, image_invert, image_compress, sha256,
    /// bash_list, parent_folder, file_paths_html, и т.д.
    static func isEnabledByDefault(_ actionID: String) -> Bool {
        // AI actions всегда default-enabled (discovery — Backlog #2).
        if actionID.hasPrefix("ai.") || actionID.hasPrefix("user.") { return true }
        return enabledByDefault.contains(actionID)
    }
}
