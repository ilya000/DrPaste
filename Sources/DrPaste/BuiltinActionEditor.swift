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
//  IDs follow convention v2 (#A74, 0.56.0): `builtin.<content_kind>.<verb_noun>`.
//

import Foundation

enum BuiltinActionMetadata {
    static let descriptions: [String: String] = [
        // Universal anchor
        "builtin.identity": "Restores the clipboard payload exactly as it was copied — preserves all formats and representations.",

        // rich.* — rich-text transforms
        "builtin.rich.strip_formatting": "Strips rich-text formatting (HTML / RTF / styles) and trims surrounding whitespace. The most common cleanup operation — pastes as plain text everywhere.",
        "builtin.rich.to_md": "Converts rich text to Markdown — preserves bold, italic, headings, links.",
        "builtin.rich.to_html": "Converts rich text to HTML — uses native NSAttributedString HTML export.",
        "builtin.rich.to_wiki": "Converts rich text to MediaWiki markup (Wikipedia syntax).",
        "builtin.rich.to_unicode_styled": "Renders bold runs as Unicode Bold (𝐁𝐨𝐥𝐝), italic as Italic (𝐼𝑡𝑎𝑙𝑖𝑐), bold-italic as 𝑩𝒐𝒍𝒅 𝑰𝒕𝒂𝒍𝒊𝒄, and monospace runs as 𝙼𝚘𝚗𝚘. Result is plain text that preserves emphasis when pasted into Twitter / X, Telegram bios, LinkedIn captions, Discord profiles — anywhere rich-text formatting isn't supported.",

        // text.* — plain-text transforms
        "builtin.text.trim": "Trims leading and trailing whitespace from each line. Removes blank lines at start/end.",
        "builtin.text.uppercase": "Converts all letters to UPPERCASE.",
        "builtin.text.lowercase": "Converts all letters to lowercase.",
        "builtin.text.title_case": "Capitalizes the first letter of each word.",
        "builtin.text.sentence_case": "Capitalizes only the first letter of each sentence.",
        "builtin.text.camel_case": "Converts spaces and underscores to camelCase.",
        "builtin.text.snake_case": "Converts spaces and hyphens to snake_case.",
        "builtin.text.kebab_case": "Converts spaces and underscores to kebab-case.",
        "builtin.text.sort_lines": "Sorts lines alphabetically.",
        "builtin.text.unique_lines": "Removes duplicate lines (keeps order).",
        "builtin.text.base64_encode": "Encodes text to Base64.",
        "builtin.text.base64_decode": "Decodes Base64-encoded text.",
        "builtin.text.slugify": "Converts text to URL-safe slug (lowercase, hyphens).",
        "builtin.text.word_count": "Returns word/character/line counts as info text.",
        "builtin.text.generate_qr": "Generates a QR code image from the text — useful for sharing URLs to mobile.",
        "builtin.text.layout_repair": "Detects text mistyped in the wrong keyboard layout (e.g. text accidentally typed with Cyrillic keys while in English layout) and corrects it.",
        "builtin.text.cyrillic_to_latin": "Transliterate Cyrillic text into Latin. Auto-detects script variant via marker letters: ћ ђ ј љ њ џ → Serbian/Macedonian (Gaj's diacritic scheme — ж→ž, ч→č, ш→š); ъ without ы/э/ё → Bulgarian (Streamlined 2009 — щ→sht, ъ→a); є ї ґ → Ukrainian; ў → Belarusian; otherwise Russian default (zh, ch, sh, kh digraphs). Preserves word case (Привет → Privet, ПРИВЕТ → PRIVET). Chains well with the Unicode pseudo-font actions: paste a Cyrillic name → transliterate → ⌥⌘Space → 𝐀 Bold for stylized output.",
        "builtin.text.latin_to_cyrillic": "Reverse-transliterate Latin into Cyrillic using a target-language scheme: Russian (default), Ukrainian, Bulgarian, or Serbian. Recognises common digraphs (zh→ж, ch→ч, sh→ш, shch→щ, yo→ё, yu→ю, ya→я). Preserves case (Privet→Привет, PRIVET→ПРИВЕТ). Pair with Unicode pseudo-fonts for one-shot Cyrillic styling.",
        "builtin.text.unit_conversion": "Detects metric / imperial measurements in the text and inserts the converted equivalent in parentheses. Handles length (m / cm / mm / km, in / ft / yd / mi), weight (g / kg, oz / lb), temperature (°C / °F), volume (L / mL, fl oz / gal / qt / pt), speed (km/h / mph), and area (m² / ft²). Compound forms like \"6 feet 7 in\" and \"5'11\\\"\" are recognised.",
        "builtin.text.normalize_spaces": "Collapses runs of whitespace into a single space within each line. Preserves line breaks. Useful after pasting from PDFs or websites where words have extra spacing.",
        "builtin.text.collapse_blank_lines": "Collapses sequences of 2+ blank lines into a single blank line. Preserves paragraph boundaries.",
        "builtin.text.remove_line_breaks": "Joins single line breaks into spaces but preserves paragraph breaks (2+ consecutive newlines). Useful for pasting reflowed prose from PDFs or hard-wrapped email quotes.",
        "builtin.text.wrap_quotes": "Wraps the entire text in typographic double quotes (\u{201C} \u{201D}).",
        "builtin.text.wrap_parens": "Wraps the entire text in parentheses (…).",
        "builtin.text.extract_emails": "Extracts email addresses (one per line) from the text, deduplicated.",
        "builtin.text.extract_links": "Extracts URLs (one per line) from the text, deduplicated.",
        "builtin.text.leetspeak": "Convert text to 1337 leetspeak: a→4, e→3, i→1, o→0, s→5, t→7. Aggressive mode adds l→1, g→9, b→8. For nostalgia and screenshot-able humor.",
        "builtin.text.uwu_speak": "Convert text to UwU speech: r and l → w (case-preserving), n + vowel → ny + vowel. With Faces on, rotates UwU / OwO / nya~ after sentence-ending punctuation.",
        "builtin.text.zalgo": "Corrupt text with overlapping Unicode combining marks. Intensity Light / Medium / Heavy controls density (1 / 3 / 8 marks per char above + below). Whitespace stays clean. Heavy Zalgo can break line wrapping in some apps — use sparingly.",
        "builtin.text.type_slowly": "Types the text character-by-character with a small delay between keys. Useful for input fields that don't accept paste, demos, screen recordings, or accessibility workflows.",

        // url.* — URL transforms
        "builtin.url.strip_tracking": "Removes tracking parameters from URLs (utm_*, fbclid, gclid, etc.).",
        "builtin.url.extract_domain": "Returns only the domain part of the URL.",
        "builtin.url.to_md_link": "Wraps URL as Markdown link [domain](url).",
        "builtin.url.to_html_link": "Wraps URL as HTML <a href> link.",
        "builtin.url.encode": "Percent-encodes special characters for URLs.",
        "builtin.url.decode": "Decodes percent-encoded URL characters.",
        "builtin.url.preview_card": "Fetch a URL and build a rich-text preview card: page title (bold), description, link. Reads Open Graph tags (og:title / og:description / og:image) with a fallback to standard `<title>` and `<meta name=\"description\">`. Single GET, 20-second timeout, no JavaScript. Fails gracefully if the host is unreachable.",

        // json.* — JSON transforms
        "builtin.json.pretty": "Reformats JSON with 2-space indentation.",
        "builtin.json.minify": "Removes whitespace from JSON for compact transmission.",
        "builtin.json.extract_keys": "Lists all top-level keys (one per line) — useful for understanding API responses.",
        "builtin.json.flatten": "Flattens nested objects into dot-notation keys (e.g. {a:{b:1}} → {a.b:1}).",
        "builtin.json.remove_nulls": "Removes keys with null values.",
        "builtin.json.validate": "Validates the input as JSON; emits a success info chip or a parser error with byte offset.",

        // table.* — CSV / table transforms
        "builtin.table.to_json": "Converts CSV / TSV to JSON array of objects.",
        "builtin.table.to_md": "Converts CSV / TSV to Markdown table.",
        "builtin.table.to_wiki": "Convert CSV (comma-separated) text into a MediaWiki / DokuWiki table: `{| class=\"wikitable\"`, header row with `!` separators, body rows separated by `|-`. Handles quoted fields with embedded commas, newlines, and \"\"-escaped quotes; CRLF and LF endings.",
        "builtin.table.to_rich": "Convert CSV into a rendered NSTextTable. Pastes as a real table into Mail / Notes / Pages / Word / TextEdit (RTFD-aware editors). The header row is bold. Slack and Notion don't honour RTFD tables and will fall back to plain text — by design.",
        "builtin.table.to_html": "Convert CSV into a clean HTML `<table>` with `<thead>` and `<tbody>` sections. Header row in `<th>`, body rows in `<td>`. Pastes as a real table into Notion / Confluence / Google Docs.",

        // md.* — Markdown transforms
        "builtin.md.to_plain": "Strips Markdown markup, keeps only readable prose.",
        "builtin.md.to_rich": "Renders Markdown source as rich text (bold, italic, inline code, links). Pastes into Mail / Pages / Notes / Word with formatting intact.",
        "builtin.md.extract_headings": "Lists all Markdown headings — for building a TOC.",
        "builtin.md.extract_links": "Lists all Markdown links.",

        // code.* — code transforms
        "builtin.code.wrap_block": "Wraps text in a Markdown code block (triple backticks).",
        "builtin.code.tabs_to_spaces": "Replaces tabs with 4 spaces.",
        "builtin.code.spaces_to_tabs": "Replaces 4 spaces with tabs.",
        "builtin.code.pretty_local": "Deterministic offline code reformatter. Auto-detects format: JSON via JSONSerialization (.prettyPrinted + .sortedKeys); XML via XMLDocument .nodePrettyPrint; HTML reflow (newline after tags + tag-depth indent); CSS (newline after ;, indent rule body 2 spaces); otherwise generic whitespace cleanup. Sub-50 ms typical. An AI counterpart for arbitrary languages ships separately.",

        // html.* — HTML transforms
        "builtin.html.strip_tags": "Removes HTML tags, keeps only text content.",
        "builtin.html.escape": "Escapes HTML special characters (< > & \" ') into entities.",
        "builtin.html.unescape": "Decodes HTML entities (&amp; &lt; &#39; …) into characters.",

        // image.* — image transforms
        "builtin.image.ocr": "Extracts text from an image using Vision OCR.",
        "builtin.image.decode_qr": "Decodes a QR code or barcode embedded in the image.",
        "builtin.image.strip_metadata": "Removes EXIF / GPS metadata for privacy.",
        "builtin.image.resize_max_1920": "Resizes the image to max 1920 pixels in the longer dimension.",
        "builtin.image.compress_jpeg": "Compresses the image as JPEG at 80% quality for sharing.",
        "builtin.image.to_grayscale": "Converts the image to grayscale.",
        "builtin.image.invert_colors": "Inverts the image colors.",
        "builtin.image.rotate_right": "Rotates the image 90° clockwise (right).",
        "builtin.image.rotate_left": "Rotates the image 90° counter-clockwise (left).",
        "builtin.image.to_ascii_art": "Converts the image to ASCII art — downsamples to a monospace grid (default 40 columns since 0.42.0) and maps each cell's brightness to a glyph from \" .:-=+*#%@\". Output is rich text with a monospaced font so columns survive paste into Mail / Notes / Pages.",
        "builtin.image.resize": "Resizes images to a target longer-side dimension (default 1920 pixels). Works on image clips, file lists of images, and rich-text clips with embedded image attachments. Never enlarges — images already at or below the target are passed through unchanged.",

        // files.* — files transforms
        "builtin.files.copy_paths": "Returns absolute file paths as text, one per line.",
        "builtin.files.copy_filenames": "Returns just the filenames (without paths).",
        "builtin.files.to_md_links": "Wraps files as Markdown links [name](file:///path).",
        "builtin.files.reveal_in_finder": "Reveals the files in Finder (side-effect — closes HUD on commit).",
        "builtin.files.copy_shell_safe_paths": "Returns POSIX-single-quote-escaped paths, space-separated — safe to paste into Terminal as a command argument list (single quotes inside paths are escaped via the '\\'' idiom).",
        "builtin.files.to_rich_icons": "Builds a rich-text representation of the file list with Finder icons inline next to each filename. Pastes into Mail / Notes / Pages preserving icons.",
        "builtin.files.extract_image": "Extracts an image from a single file clip. PDFs render page 1 at 2× scale; HEIC / TIFF / BMP / GIF files are re-encoded as PNG. Multi-page PDFs and multi-file clips are intentionally not supported (use a dedicated PDF tool for full extraction)."
    ]
}
