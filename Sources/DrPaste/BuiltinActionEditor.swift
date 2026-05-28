//
//  BuiltinActionEditor.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Bundled metadata для built-in actions — descriptions для unified ActionEditor
//  (0.7.0) и палитры (правка #8). Один источник правды.
//

import Foundation

enum BuiltinActionMetadata {
    static let descriptions: [String: String] = [
        "builtin.identity": "Restores the clipboard payload exactly as it was copied — preserves all formats and representations.",
        "builtin.paste_as_text": "Strips formatting (rich text, HTML, RTF) and trims leading/trailing whitespace. The most common cleanup operation.",
        "builtin.clean_formatting": "Removes rich text formatting, keeping only plain text. Use Paste as text for cleanup + trim in one step.",
        "builtin.trim": "Trims leading and trailing whitespace from each line. Removes blank lines at start/end.",
        "builtin.uppercase": "Converts all letters to UPPERCASE.",
        "builtin.lowercase": "Converts all letters to lowercase.",
        "builtin.layout_repair": "Detects text mistyped in the wrong keyboard layout (e.g. text accidentally typed with Cyrillic keys while in English layout) and corrects it.",
        "builtin.rich_to_md": "Converts rich text to Markdown — preserves bold, italic, headings, links.",
        "builtin.rich_to_html": "Converts rich text to HTML — uses native NSAttributedString HTML export.",
        "builtin.rich_to_wiki": "Converts rich text to MediaWiki markup (Wikipedia syntax).",
        "builtin.json_pretty": "Reformats JSON with 2-space indentation.",
        "builtin.json_minify": "Removes whitespace from JSON for compact transmission.",
        "builtin.json_extract_keys": "Lists all top-level keys (one per line) — useful for understanding API responses.",
        "builtin.json_flatten": "Flattens nested objects into dot-notation keys (e.g. {a:{b:1}} → {a.b:1}).",
        "builtin.json_remove_nulls": "Removes keys with null values.",
        "builtin.url_strip_tracking": "Removes tracking parameters from URLs (utm_*, fbclid, gclid, etc.).",
        "builtin.url_just_domain": "Returns only the domain part of the URL.",
        "builtin.url_md_link": "Wraps URL as Markdown link [domain](url).",
        "builtin.url_html_link": "Wraps URL as HTML <a href> link.",
        "builtin.url_query_params": "Extracts query parameters as a key/value table.",
        "builtin.table_to_json": "Converts CSV / TSV to JSON array of objects.",
        "builtin.table_to_md": "Converts CSV / TSV to Markdown table.",
        "builtin.table_transpose": "Swaps rows and columns.",
        "builtin.md_to_plain": "Strips Markdown markup, keeps only readable prose.",
        "builtin.md_extract_headings": "Lists all Markdown headings — for building a TOC.",
        "builtin.md_extract_links": "Lists all Markdown links.",
        "builtin.code_wrap": "Wraps text in a Markdown code block (triple backticks).",
        "builtin.tabs_to_spaces": "Replaces tabs with 4 spaces.",
        "builtin.spaces_to_tabs": "Replaces 4 spaces with tabs.",
        "builtin.title_case": "Capitalizes the first letter of each word.",
        "builtin.sentence_case": "Capitalizes only the first letter of each sentence.",
        "builtin.camel_case": "Converts spaces and underscores to camelCase.",
        "builtin.snake_case": "Converts spaces and hyphens to snake_case.",
        "builtin.kebab_case": "Converts spaces and underscores to kebab-case.",
        "builtin.sort_lines": "Sorts lines alphabetically.",
        "builtin.unique_lines": "Removes duplicate lines (keeps order).",
        "builtin.base64_encode": "Encodes text to Base64.",
        "builtin.base64_decode": "Decodes Base64-encoded text.",
        "builtin.url_encode": "Percent-encodes special characters for URLs.",
        "builtin.url_decode": "Decodes percent-encoded URL characters.",
        "builtin.slugify": "Converts text to URL-safe slug (lowercase, hyphens).",
        "builtin.word_count": "Returns word/character/line counts as info text.",
        "builtin.generate_qr": "Generates a QR code image from the text — useful for sharing URLs to mobile.",
        "builtin.image_ocr": "Extracts text from an image using Vision OCR.",
        "builtin.image_decode_qr": "Decodes a QR code or barcode embedded in the image.",
        "builtin.image_strip_metadata": "Removes EXIF / GPS metadata for privacy.",
        "builtin.image_resize_1920": "Resizes the image to max 1920 pixels in the longer dimension.",
        "builtin.image_compress_jpeg": "Compresses the image as JPEG at 80% quality for sharing.",
        "builtin.image_grayscale": "Converts the image to grayscale.",
        "builtin.image_rotate_90": "Rotates the image 90° clockwise.",
        "builtin.image_invert": "Inverts the image colors.",
        "builtin.type_slowly": "Types the text character-by-character with a small delay between keys. Useful for input fields that don't accept paste, demos, screen recordings, or accessibility workflows.",
        "builtin.files_paths": "Returns absolute file paths as text, one per line.",
        "builtin.files_names": "Returns just the filenames (without paths).",
        "builtin.files_md_links": "Wraps files as Markdown links [name](file:///path).",
        "builtin.files_bash_list": "Quotes filenames bash-style: \"file 1\" \"file 2\".",
        "builtin.files_size": "Returns total size and count of files.",
        "builtin.files_sha256": "Returns SHA-256 hash of the first file.",
        "builtin.files_reveal": "Reveals the files in Finder (side-effect — closes HUD on commit)."
    ]
}
