//
//  CuratedActionOrder.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Curated DEFAULT ordering of action chips per content kind. Applied by
//  `ActionRegistry.reorder` as a LIVE FALLBACK whenever the user has not
//  hand-ordered a kind (no `config.actionOrder[kind]`). Because it's a
//  fallback — not a stored migration — the order can be tuned freely and
//  every non-customized user picks up the change automatically; users who
//  dragged their own order keep it untouched.
//
//  Ordering philosophy (feature-frozen final pass):
//    1. `builtin.identity` ("Paste as is") stays pinned first (also enforced
//       structurally by `moveIdentityFirst`).
//    2. The most frequent, useful, and easy-to-predict actions lead. "Wow"
//       actions still matter, but they follow the core repair / rewrite /
//       convert actions instead of defining the first impression.
//    3. Trait-gated ("conditional") actions rank HIGH when they appear: they
//       already passed a relevance test, so showing them prominently is a
//       feature, not clutter (e.g. layout repair, clean OCR, strip tracking).
//    4. AI writing actions come early as the high-value text layer; expensive,
//       target-parameter, destructive, or presentation-only actions sink lower.
//    5. Novelty + low-frequency actions (Zalgo, leetspeak, UwU, pseudo-font
//       variants, IPA, wiki conversions, Base64, case-shuffles, text→image)
//       sink last unless the user explicitly enables or reorders them.
//
//  IDs that don't exist for a given build are harmless no-ops: `reorder`
//  only positions IDs it actually finds in the applicable list, and any
//  applicable action NOT listed here is appended afterwards in registration
//  order — so the list need not be exhaustive to push novelties to the tail.
//

import Foundation

enum CuratedActionOrder {

    /// Curated default order for a content kind, or `[]` if none is defined
    /// (callers then fall back to plain registration order).
    static func order(for kind: SemanticKind) -> [String] {
        byKind[kind.rawValue] ?? []
    }

    private static let byKind: [String: [String]] = [

        "text": [
            "builtin.identity",
            // Core writing / repair.
            "ai.text.fix_grammar", "ai.text.translate", "ai.text.summarize",
            "builtin.text.trim", "builtin.text.layout_repair", "ai.text.clean_ocr",
            "ai.text.improve_clarity", "ai.text.make_shorter",
            "ai.text.formal_tone", "ai.text.make_friendly",
            "ai.text.draft_email_reply", "ai.text.generate_email_subject",
            // Useful extraction / conversion.
            "builtin.text.unit_conversion",
            "builtin.text.extract_links", "builtin.text.extract_emails",
            "builtin.text.cyrillic_to_latin",
            "builtin.text.generate_qr", "builtin.text.to_files",
            // Local cleanup / shape changes.
            "builtin.text.remove_line_breaks",
            "builtin.text.sentence_case", "builtin.text.title_case",
            "builtin.text.lowercase", "builtin.text.uppercase",
            "builtin.text.unique_lines", "builtin.text.sort_lines",
            "builtin.text.word_count", "builtin.text.slugify",
            "builtin.text.wrap_quotes", "builtin.text.wrap_parens",
            "builtin.url.decode", "builtin.url.encode", "builtin.html.strip_tags",
            "builtin.text.type_slowly",
            // Chat / social styling.
            "builtin.text.font_bold", "builtin.text.font_italic",
            "builtin.text.font_bold_italic", "builtin.text.font_script",
            "builtin.text.font_monospace", "builtin.text.font_small_caps",
            // Niche / novelty.
            "builtin.text.latin_to_cyrillic", "ai.text.latin_to_cyrillic",
            "builtin.text.ipa_local", "ai.text.ipa_transcription",
            "ai.text.image_whiteboard",
            "builtin.text.camel_case", "builtin.text.snake_case", "builtin.text.kebab_case",
            "builtin.text.base64_decode", "builtin.text.base64_encode",
            "builtin.code.tabs_to_spaces", "builtin.code.spaces_to_tabs",
            "builtin.text.leetspeak", "builtin.text.uwu_speak", "builtin.text.zalgo",
        ],

        "richText": [
            "builtin.identity",
            // Core repair / conversion.
            "builtin.rich.strip_formatting", "builtin.rich.to_md",
            "ai.text.fix_grammar", "ai.text.translate", "ai.text.summarize",
            "builtin.image.ocr", "ai.text.clean_ocr",
            "ai.text.improve_clarity", "ai.text.make_shorter",
            "ai.text.formal_tone", "ai.text.make_friendly",
            "ai.text.draft_email_reply", "ai.text.generate_email_subject",
            "builtin.rich.to_html",
            "builtin.text.unit_conversion",
            "builtin.text.extract_links", "builtin.text.extract_emails",
            "builtin.text.trim", "builtin.md.extract_headings",
            "builtin.image.resize", "builtin.image.rotate_right", "builtin.image.rotate_left",
            "builtin.image.to_grayscale", "builtin.image.compress_jpeg", "builtin.image.invert_colors",
            // Presentation / niche.
            "builtin.rich.to_unicode_styled", "builtin.rich.to_wiki",
            "ai.text.latin_to_cyrillic", "ai.text.ipa_transcription",
        ],

        "url": [
            "builtin.identity",
            // Hero / WOW
            "builtin.url.strip_tracking", "builtin.url.preview_card", "builtin.text.generate_qr",
            // Everyday
            "builtin.url.to_md_link", "builtin.url.extract_domain", "builtin.url.decode",
            // Useful
            "builtin.url.to_html_link", "builtin.url.encode",
            // Niche
            "builtin.text.type_slowly",
        ],

        "json": [
            "builtin.identity",
            "builtin.code.pretty_local", "builtin.json.validate",
            "builtin.json.extract_keys", "builtin.json.minify",
            "builtin.json.flatten", "builtin.json.remove_nulls",
            "builtin.json.pretty",
        ],

        "table": [
            "builtin.identity",
            "builtin.table.to_rich", "builtin.table.to_md",
            "builtin.table.to_json", "builtin.table.to_html",
            "builtin.table.to_wiki",
        ],

        "markdown": [
            "builtin.identity",
            // Core conversion / writing.
            "builtin.md.to_rich", "builtin.rich.strip_formatting",
            "ai.text.fix_grammar", "ai.text.translate", "ai.text.summarize",
            "ai.text.improve_clarity", "ai.text.make_shorter",
            "ai.text.formal_tone", "ai.text.make_friendly",
            "builtin.md.extract_headings",
            "builtin.text.extract_links", "builtin.text.extract_emails",
            "builtin.text.trim", "builtin.text.remove_line_breaks",
            // Useful / specific
            "builtin.md.to_wiki",
            "builtin.text.unit_conversion",
            "builtin.text.sentence_case", "builtin.text.title_case",
            "builtin.text.lowercase", "builtin.text.uppercase",
            "builtin.text.unique_lines", "builtin.text.sort_lines",
            "builtin.text.word_count", "builtin.text.wrap_quotes", "builtin.text.wrap_parens",
            "builtin.md.extract_links", "builtin.url.decode", "builtin.url.encode",
            // Presentation / niche.
            "builtin.text.font_markdown", "builtin.rich.to_unicode_styled",
            "ai.text.image_whiteboard", "ai.text.latin_to_cyrillic",
            "ai.text.ipa_transcription", "builtin.text.uwu_speak",
        ],

        "code": [
            "builtin.identity",
            // Hero / Everyday
            "builtin.code.pretty_local", "ai.code.explain", "ai.code.find_bugs",
            "builtin.code.wrap_block",
            // Useful
            "ai.code.pretty",
            "builtin.text.extract_links", "builtin.text.extract_emails",
            "builtin.html.strip_tags", "builtin.html.unescape", "builtin.html.escape",
            // Specific
            "builtin.code.tabs_to_spaces", "builtin.code.spaces_to_tabs",
            "builtin.text.word_count",
            "builtin.text.base64_decode", "builtin.text.base64_encode",
            "builtin.text.camel_case", "builtin.text.snake_case", "builtin.text.kebab_case",
            "builtin.text.unique_lines", "builtin.text.sort_lines", "builtin.text.wrap_parens",
            // Niche / expensive
            "ai.code.translate", "builtin.text.leetspeak",
        ],

        "image": [
            "builtin.identity",
            // Core extraction / inspection.
            "builtin.image.ocr", "builtin.image.decode_qr",
            "builtin.image.info", "builtin.image.strip_metadata", "builtin.image.resize",
            "builtin.image.rotate_right", "builtin.image.rotate_left",
            "builtin.image.compress_jpeg", "builtin.image.to_grayscale", "builtin.image.invert_colors",
            // Presentation / novelty.
            "builtin.image.to_ascii_art",
            "ai.image.cartoon", "ai.image.sketch", "ai.image.watercolor",
        ],

        "files": [
            "builtin.identity",
            // Core file references.
            "builtin.files.copy_paths", "builtin.files.copy_filenames",
            "builtin.files.reveal_in_finder",
            "builtin.files.copy_shell_safe_paths", "builtin.files.extract_image",
            "builtin.image.resize",
            // Presentation / specific.
            "builtin.files.to_md_links", "builtin.files.to_rich_icons",
        ],
    ]
}
