//
//  IDMigration056.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Pre-distribution ID consolidation (#A74). Reformulates every
//  default-shipped action ID under convention v2:
//
//      <namespace>.<content_kind>.<verb_noun>
//
//  Where:
//    namespace    = builtin | ai (user.* remains for actually
//                   user-created descriptors)
//    content_kind = source SemanticKind matching userVisibleKinds
//                   (text, rich, url, json, code, md, table, image,
//                   files)
//    verb_noun    = imperative form (extract_emails, strip_tags,
//                   to_grayscale, from_file, wrap_quotes)
//
//  Sub-domain hints (translit, email, OCR, fun, HTML, data extract)
//  go into title + verb_noun, NOT into category — HUD filtering is
//  driven by `applicableTypes` + `isApplicable`, not by ID parsing.
//
//  Migration mechanics:
//    1. Migration runs in ActionRegistry.runFirstLaunchSeeds() BEFORE
//       remapLegacyActionIDs / seedTransformations / seedAI.
//    2. Single-shot guarded by `seedTransformationVersion < 9` — once
//       the seed pass bumps the version, this migration is skipped.
//    3. Rewrites every dict-keyed-by-action-ID in ActionConfig:
//       enabledFlags, customTitles, customDescriptions, actionHotkeys,
//       actionTestSamples, actionTestImageBlobs, plus actionOrder
//       (which is [String: [String]] — rewrite each list).
//    4. customTransformations / customAI arrays carry their own .id
//       field — rewritten in-place.
//
//  Two duplicate actions are merged in the same pass:
//    builtin.paste_as_text    ─┐
//                              ├→ builtin.rich.strip_formatting
//    builtin.clean_formatting ─┘
//

import Foundation

enum IDMigration056 {

    /// Old ID → new ID table. ~100 entries; populated below.
    /// Order doesn't matter — lookups are O(1).
    static let table: [String: String] = [

        // MARK: - paste anchor (no category — universal)
        "builtin.identity": "builtin.identity",

        // MARK: - text transformations
        "builtin.uppercase":          "builtin.text.uppercase",
        "builtin.lowercase":          "builtin.text.lowercase",
        "builtin.title_case":         "builtin.text.title_case",
        "builtin.sentence_case":      "builtin.text.sentence_case",
        "builtin.camel_case":         "builtin.text.camel_case",
        "builtin.snake_case":         "builtin.text.snake_case",
        "builtin.kebab_case":         "builtin.text.kebab_case",
        "builtin.trim":               "builtin.text.trim",
        "builtin.sort_lines":         "builtin.text.sort_lines",
        "builtin.unique_lines":       "builtin.text.unique_lines",
        "builtin.base64_encode":      "builtin.text.base64_encode",
        "builtin.base64_decode":      "builtin.text.base64_decode",
        "builtin.url_encode":         "builtin.url.encode",
        "builtin.url_decode":         "builtin.url.decode",
        "builtin.slugify":            "builtin.text.slugify",
        "builtin.word_count":         "builtin.text.word_count",
        "builtin.normalize_spaces":   "builtin.text.normalize_spaces",
        "builtin.collapse_blank_lines": "builtin.text.collapse_blank_lines",
        "builtin.unit_conversion":    "builtin.text.unit_conversion",
        "builtin.layout_repair":      "builtin.text.layout_repair",
        "builtin.type_slowly":        "builtin.text.type_slowly",
        "builtin.cyrillic_translit":  "builtin.text.cyrillic_to_latin",
        "builtin.latin_to_cyrillic":  "builtin.text.latin_to_cyrillic",
        "builtin.html_strip_tags":    "builtin.html.strip_tags",
        "builtin.html_escape":        "builtin.html.escape",
        "builtin.html_unescape":      "builtin.html.unescape",
        "builtin.extract_emails":     "builtin.text.extract_emails",
        "builtin.extract_links":      "builtin.text.extract_links",
        "builtin.leetspeak":          "builtin.text.leetspeak",
        "builtin.uwu_speak":          "builtin.text.uwu_speak",
        "builtin.zalgo":              "builtin.text.zalgo",
        "builtin.generate_qr":        "builtin.text.generate_qr",
        "builtin.font_bold":          "builtin.text.font_bold",
        "builtin.font_italic":        "builtin.text.font_italic",
        "builtin.font_bold_italic":   "builtin.text.font_bold_italic",
        "builtin.font_script":        "builtin.text.font_script",
        "builtin.font_bold_script":   "builtin.text.font_bold_script",
        "builtin.font_fraktur":       "builtin.text.font_fraktur",
        "builtin.font_bold_fraktur":  "builtin.text.font_bold_fraktur",
        "builtin.font_double_struck": "builtin.text.font_double_struck",
        "builtin.font_sans":          "builtin.text.font_sans",
        "builtin.font_sans_bold":     "builtin.text.font_sans_bold",
        "builtin.font_sans_italic":   "builtin.text.font_sans_italic",
        "builtin.font_sans_bold_italic": "builtin.text.font_sans_bold_italic",
        "builtin.font_monospace":     "builtin.text.font_monospace",
        "builtin.font_fullwidth":     "builtin.text.font_fullwidth",
        "builtin.font_small_caps":    "builtin.text.font_small_caps",
        "builtin.font_circled":       "builtin.text.font_circled",
        "builtin.font_filled_circled": "builtin.text.font_filled_circled",
        "builtin.font_squared":       "builtin.text.font_squared",
        "builtin.font_filled_squared": "builtin.text.font_filled_squared",
        "builtin.font_upside_down":   "builtin.text.font_upside_down",
        "builtin.font_plain":         "builtin.text.font_plain",
        "builtin.font_markdown":      "builtin.text.font_markdown",

        // MARK: - rich text source
        "builtin.rich_to_md":             "builtin.rich.to_md",
        "builtin.rich_to_html":           "builtin.rich.to_html",
        "builtin.rich_to_wiki":           "builtin.rich.to_wiki",
        "builtin.rich_to_unicode_style":  "builtin.rich.to_unicode_styled",
        // Merge duplicate "rich → plain" actions into one.
        "builtin.paste_as_text":          "builtin.rich.strip_formatting",
        "builtin.clean_formatting":       "builtin.rich.strip_formatting",

        // MARK: - URL
        "builtin.url_strip_tracking": "builtin.url.strip_tracking",
        "builtin.url_just_domain":    "builtin.url.extract_domain",
        // legacy aliases sometimes referenced as `url_domain`
        "builtin.url_domain":         "builtin.url.extract_domain",
        "builtin.url_markdown_link":  "builtin.url.to_md_link",
        "builtin.url_html_link":      "builtin.url.to_html_link",
        "builtin.url_preview_card":   "builtin.url.preview_card",

        // MARK: - JSON
        "builtin.json_pretty":        "builtin.json.pretty",
        "builtin.json_minify":        "builtin.json.minify",
        "builtin.json_validate":      "builtin.json.validate",
        "builtin.json_keys":          "builtin.json.extract_keys",
        // legacy alias from before json_keys rename in 0.46
        "builtin.json_extract_keys":  "builtin.json.extract_keys",
        "builtin.json_flatten":       "builtin.json.flatten",
        "builtin.json_remove_nulls":  "builtin.json.remove_nulls",

        // MARK: - Code
        "builtin.code_wrap":          "builtin.code.wrap_block",
        "builtin.tabs_to_spaces":     "builtin.code.tabs_to_spaces",
        "builtin.spaces_to_tabs":     "builtin.code.spaces_to_tabs",
        "builtin.pretty_code_local": "builtin.code.pretty_local",

        // MARK: - Markdown
        "builtin.md_to_plain":        "builtin.md.to_plain",
        "builtin.md_to_rich":         "builtin.md.to_rich",
        "builtin.md_headings":        "builtin.md.extract_headings",
        // legacy alias from before md_headings rename
        "builtin.md_extract_headings": "builtin.md.extract_headings",
        "builtin.md_links":           "builtin.md.extract_links",
        "builtin.md_extract_links":   "builtin.md.extract_links",

        // MARK: - Table
        "builtin.table_to_md":        "builtin.table.to_md",
        "builtin.table_to_json":      "builtin.table.to_json",
        "builtin.csv_to_wiki_table":  "builtin.table.to_wiki",
        "builtin.csv_to_rtfd_table":  "builtin.table.to_rich",

        // MARK: - Image
        "builtin.image_ocr":              "builtin.image.ocr",
        "builtin.image_decode_qr":        "builtin.image.decode_qr",
        "builtin.image_grayscale":        "builtin.image.to_grayscale",
        "builtin.image_invert":           "builtin.image.invert_colors",
        "builtin.image_rotate":           "builtin.image.rotate_right",
        "builtin.image_rotate_left":      "builtin.image.rotate_left",
        "builtin.image_resize_universal": "builtin.image.resize",
        "builtin.image_resize_1920":      "builtin.image.resize_max_1920",
        "builtin.image_compress_jpeg":    "builtin.image.compress_jpeg",
        "builtin.image_strip_meta":       "builtin.image.strip_metadata",
        // legacy drift fix typo from earlier batches
        "builtin.image_strip_metadata":   "builtin.image.strip_metadata",
        "builtin.image_ascii_art":        "builtin.image.to_ascii_art",

        // MARK: - Files
        "builtin.files_paths":            "builtin.files.copy_paths",
        "builtin.files_names":            "builtin.files.copy_filenames",
        "builtin.files_md_links":         "builtin.files.to_md_links",
        "builtin.files_reveal":           "builtin.files.reveal_in_finder",
        // File → image extraction renamed from image-prefixed legacy.
        "builtin.file_to_image":          "builtin.files.extract_image",

        // MARK: - AI seeds (user.* → ai.* namespace)
        "user.translate":                  "ai.text.translate",
        "user.summarize":                  "ai.text.summarize",
        "user.fix_grammar":                "ai.text.fix_grammar",
        "user.formal_tone":                "ai.text.formal_tone",
        "user.ai_latin_to_cyrillic":       "ai.text.latin_to_cyrillic",
        "user.translate_rich":             "ai.rich.translate",
        "user.fix_grammar_rich":           "ai.rich.fix_grammar",
        "user.ai_pretty_code":             "ai.code.pretty",
        "user.ai_image_sketch":            "ai.image.sketch",
        "user.ai_image_watercolor":        "ai.image.watercolor",
        "user.ai_image_cartoon":           "ai.image.cartoon",
        "user.ai_text_to_image_whiteboard": "ai.text.image_whiteboard"
    ]

    /// Apply the migration to a mutable ActionConfig in-place.
    /// Idempotent — running twice rewrites no-op because new IDs
    /// aren't in the table as keys.
    ///
    /// Returns the count of entries actually rewritten (for the
    /// NSLog summary).
    @discardableResult
    static func apply(to config: inout ActionConfig) -> Int {
        var rewrites = 0

        // enabledFlags : [String: Bool]
        let oldEnabled = config.enabledFlags
        config.enabledFlags = remapDict(oldEnabled, table: table,
                                        mergePolicy: { $0 || $1 })
        rewrites += oldEnabled.count - config.enabledFlags.count

        // customTitles : [String: String]
        let oldTitles = config.customTitles
        config.customTitles = remapDict(oldTitles, table: table,
                                        mergePolicy: { first, _ in first })
        rewrites += oldTitles.count - config.customTitles.count

        // customDescriptions : [String: String]
        let oldDescriptions = config.customDescriptions
        config.customDescriptions = remapDict(oldDescriptions, table: table,
                                              mergePolicy: { first, _ in first })
        rewrites += oldDescriptions.count - config.customDescriptions.count

        // actionHotkeys : [String: ActionHotkey]
        let oldHotkeys = config.actionHotkeys
        config.actionHotkeys = remapDict(oldHotkeys, table: table,
                                         mergePolicy: { first, _ in first })
        rewrites += oldHotkeys.count - config.actionHotkeys.count

        // actionTestSamples : [String: String]
        let oldSamples = config.actionTestSamples
        config.actionTestSamples = remapDict(oldSamples, table: table,
                                             mergePolicy: { first, _ in first })
        rewrites += oldSamples.count - config.actionTestSamples.count

        // actionTestImageBlobs : [String: String]
        let oldImages = config.actionTestImageBlobs
        config.actionTestImageBlobs = remapDict(oldImages, table: table,
                                                mergePolicy: { first, _ in first })
        rewrites += oldImages.count - config.actionTestImageBlobs.count

        // actionOrder : [String: [String]] — rewrite each list value.
        for (kind, ids) in config.actionOrder {
            let remapped = ids.map { table[$0] ?? $0 }
            // Dedupe — two old IDs may collide on the new ID after
            // the paste_as_text / clean_formatting merge.
            var seen = Set<String>()
            let unique = remapped.filter { seen.insert($0).inserted }
            if unique != ids {
                rewrites += abs(ids.count - unique.count)
                config.actionOrder[kind] = unique
            }
        }

        // customTransformations / customAI — descriptors carry their
        // own .id field. Rewrite in-place when matched.
        config.customTransformations = config.customTransformations.map {
            var d = $0
            if let new = table[d.id], new != d.id {
                d.id = new
                rewrites += 1
            }
            return d
        }
        config.customAI = config.customAI.map {
            var d = $0
            if let new = table[d.id], new != d.id {
                d.id = new
                rewrites += 1
            }
            return d
        }

        return rewrites
    }

    /// Generic dict-remap helper. When two old keys collide on the
    /// same new key (e.g. paste_as_text + clean_formatting both →
    /// rich.strip_formatting), the `mergePolicy` closure decides
    /// which value wins.
    private static func remapDict<V>(_ source: [String: V],
                                     table: [String: String],
                                     mergePolicy: (V, V) -> V) -> [String: V] {
        var out: [String: V] = [:]
        for (oldKey, value) in source {
            let newKey = table[oldKey] ?? oldKey
            if let existing = out[newKey] {
                out[newKey] = mergePolicy(existing, value)
            } else {
                out[newKey] = value
            }
        }
        return out
    }
}
