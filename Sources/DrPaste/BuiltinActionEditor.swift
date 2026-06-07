//
//  BuiltinActionEditor.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Bundled metadata for built-in actions — descriptions for the unified
//  ActionEditor and the Browse palette. Single source of truth.
//
//  Descriptions are SHORT descriptors (one line) shown as the second line
//  of the action row in Settings and inside the editor. The title says what
//  the action is; the descriptor adds the what/why in a few words. Keep them
//  brief — the row truncates to a single line.
//
//  IDs follow convention v2 (#A74, 0.56.0): `builtin.<content_kind>.<verb_noun>`.
//

import Foundation

enum BuiltinActionMetadata {
    static let descriptions: [String: String] = [
        // Universal anchor
        "builtin.identity": "Pastes the original, untouched — every format preserved.",

        // rich.* — rich-text transforms
        "builtin.rich.strip_formatting": "Strips all formatting and markup down to clean plain text.",
        "builtin.rich.to_md": "Rich text → Markdown, keeping bold, headings and links.",
        "builtin.rich.to_html": "Rich text → clean HTML.",
        "builtin.rich.to_wiki": "Rich text → MediaWiki (Wikipedia) markup.",
        "builtin.rich.to_unicode_styled": "Fakes bold/italic with Unicode glyphs — survives in bios and chats.",

        // text.* — plain-text transforms
        "builtin.text.trim": "Tidies whitespace and reflows PDF-wrapped lines into paragraphs.",
        "builtin.text.uppercase": "Makes every letter UPPERCASE.",
        "builtin.text.lowercase": "Makes every letter lowercase.",
        "builtin.text.title_case": "Capitalizes The First Letter Of Each Word.",
        "builtin.text.sentence_case": "Capitalizes the first letter of each sentence.",
        "builtin.text.camel_case": "Joins words into camelCase.",
        "builtin.text.snake_case": "Joins words with underscores → snake_case.",
        "builtin.text.kebab_case": "Joins words with hyphens → kebab-case.",
        "builtin.text.sort_lines": "Sorts lines alphabetically.",
        "builtin.text.unique_lines": "Removes duplicate lines, keeping order.",
        "builtin.text.base64_encode": "Encodes text to Base64.",
        "builtin.text.base64_decode": "Decodes Base64 back to text.",
        "builtin.text.slugify": "Makes a URL-safe slug (lowercase, hyphens).",
        "builtin.text.word_count": "Counts words, characters and lines.",
        "builtin.text.generate_qr": "Turns the text or URL into a QR code.",
        "builtin.text.layout_repair": "Fixes text typed in the wrong keyboard layout — English ↔ Russian / Ukrainian, both directions.",
        "builtin.text.ipa_local": "Offline English pronunciation in IPA, from a 126k-word dictionary.",
        "builtin.text.cyrillic_to_latin": "Transliterates Cyrillic to Latin, auto-detecting the language.",
        "builtin.text.latin_to_cyrillic": "Transliterates Latin back to Cyrillic.",
        "builtin.text.unit_conversion": "Adds metric/imperial equivalents in parentheses.",
        "builtin.text.remove_line_breaks": "Joins wrapped lines, keeping paragraph breaks.",
        "builtin.text.wrap_quotes": "Wraps the text in “smart” quotes.",
        "builtin.text.wrap_parens": "Wraps the text in parentheses.",
        "builtin.text.extract_emails": "Pulls out every email address, deduplicated.",
        "builtin.text.extract_links": "Pulls out every URL, deduplicated.",
        "builtin.text.leetspeak": "Rewrites text as 1337 l33tspeak.",
        "builtin.text.uwu_speak": "Rewrites text as cutesy UwU speak.",
        "builtin.text.zalgo": "Corrupts text with glitchy combining marks.",
        "builtin.text.type_slowly": "Types it key-by-key where paste is blocked.",

        // url.* — URL transforms
        "builtin.url.strip_tracking": "Drops utm_, fbclid and other tracking params.",
        "builtin.url.extract_domain": "Keeps just the domain.",
        "builtin.url.to_md_link": "Wraps the URL as a Markdown link.",
        "builtin.url.to_html_link": "Wraps the URL as an HTML link.",
        "builtin.url.encode": "Percent-encodes the URL.",
        "builtin.url.decode": "Decodes percent-encoding in the URL.",
        "builtin.url.preview_card": "Fetches the page and builds a rich title/description card.",

        // json.* — JSON transforms
        "builtin.json.pretty": "Pretty-prints JSON with 2-space indent.",
        "builtin.json.minify": "Strips JSON whitespace to one compact line.",
        "builtin.json.extract_keys": "Lists the top-level keys.",
        "builtin.json.flatten": "Flattens nested objects to dot-notation keys.",
        "builtin.json.remove_nulls": "Drops keys with null values.",
        "builtin.json.validate": "Checks the JSON and reports the first error.",

        // table.* — CSV / table transforms
        "builtin.table.to_json": "CSV / TSV → JSON array of objects.",
        "builtin.table.to_md": "CSV / TSV → Markdown table.",
        "builtin.table.to_wiki": "CSV → MediaWiki table.",
        "builtin.table.to_rich": "CSV → a real table for Mail, Notes and Pages.",
        "builtin.table.to_html": "CSV → an HTML table for Notion and Docs.",

        // md.* — Markdown transforms
        "builtin.md.to_rich": "Renders Markdown as formatted rich text.",
        "builtin.md.to_wiki": "Markdown → MediaWiki (Wikipedia) markup.",
        "builtin.md.extract_headings": "Lists the headings as an outline.",
        "builtin.md.extract_links": "Lists every Markdown link.",

        // code.* — code transforms
        "builtin.code.wrap_block": "Wraps code in a Markdown code fence.",
        "builtin.code.tabs_to_spaces": "Tabs → 4 spaces.",
        "builtin.code.spaces_to_tabs": "4 spaces → tabs.",
        "builtin.code.pretty_local": "Reformats JSON, XML, HTML or CSS offline.",

        // html.* — HTML transforms
        "builtin.html.strip_tags": "Removes tags, keeping the text.",
        "builtin.html.escape": "Escapes < > & into HTML entities.",
        "builtin.html.unescape": "Turns HTML entities back into characters.",

        // image.* — image transforms
        "builtin.image.ocr": "Reads text out of the image (or each image in rich text).",
        "builtin.image.decode_qr": "Reads a QR code or barcode in the image.",
        "builtin.image.info": "Shows dimensions, format, size and camera metadata.",
        "builtin.image.strip_metadata": "Removes EXIF / GPS data for privacy.",
        "builtin.image.compress_jpeg": "Re-saves as JPEG at 80% to shrink it.",
        "builtin.image.to_grayscale": "Makes the image grayscale.",
        "builtin.image.invert_colors": "Inverts the image's colors.",
        "builtin.image.rotate_right": "Rotates 90° clockwise.",
        "builtin.image.rotate_left": "Rotates 90° counter-clockwise.",
        "builtin.image.to_ascii_art": "Turns the image into monospace ASCII art.",
        "builtin.image.resize": "Shrinks images to a max size you set (never enlarges).",

        // files.* — files transforms
        "builtin.files.copy_paths": "Copies the files' full paths as text, one per line.",
        "builtin.files.copy_filenames": "Copies just the filenames.",
        "builtin.files.to_md_links": "Wraps each file as a Markdown link.",
        "builtin.files.reveal_in_finder": "Opens Finder with the files selected.",
        "builtin.files.copy_shell_safe_paths": "Copies quoted paths, safe to paste in Terminal.",
        "builtin.files.to_rich_icons": "Lists the files with their Finder icons inline.",
        "builtin.files.extract_image": "Pulls an image out of a PDF or photo file.",
        "builtin.text.to_files": "Turns a list of paths back into real files.",

        // ai.* — bundled default AI actions (descriptor shown in the list
        // instead of the raw prompt template).
        "ai.text.summarize": "Boils the text down to 1–3 sentences.",
        "ai.text.translate": "Translates the text (Spanish ↔ English by default).",
        "ai.text.fix_grammar": "Fixes grammar, spelling and punctuation.",
        "ai.text.formal_tone": "Rewrites it in a polished, professional tone.",
        "ai.text.ipa_transcription": "Shows how it's pronounced, in IPA.",
        "ai.text.latin_to_cyrillic": "AI transliteration with correct proper-noun spellings.",
        "ai.code.pretty": "AI-reformats code in any language.",
        "ai.image.sketch": "Redraws the photo as a pencil sketch.",
        "ai.image.watercolor": "Repaints the photo as a watercolor.",
        "ai.image.cartoon": "Restyles the photo as a cartoon.",
        "ai.text.image_whiteboard": "Turns the idea into a whiteboard sketch.",
        "ai.text.make_shorter": "Tightens the text without losing meaning.",
        "ai.text.improve_clarity": "Rewrites for clarity and flow.",
        "ai.text.make_friendly": "Warms the tone up to friendly and casual.",
        "ai.code.explain": "Explains what the code does.",
        "ai.code.find_bugs": "Hunts for bugs and risky spots.",
        "ai.code.translate": "Ports the code to another language.",
        "ai.text.draft_email_reply": "Drafts a reply to the email.",
        "ai.text.generate_email_subject": "Suggests a subject line for the email.",
        "ai.text.clean_ocr": "Fixes line breaks and artifacts in OCR'd text."
    ]
}
