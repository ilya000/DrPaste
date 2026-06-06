//
//  DefaultTransformationSeed.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Bundled transformation actions seeded into `config.customTransformations`
//  on first launch. They use stable `builtin.*` IDs so user customizations
//  (custom titles, hotkeys, ordering, enabled flags) survive the migration
//  from previously-hardcoded ClipboardAction structs to descriptor form.
//
//  Adding a new bundled transformation:
//    1. Append a `CustomTransformationDescriptor` to `defaults()`.
//    2. Increment `currentSeedVersion`.
//    3. New installs see it immediately. Existing installs receive it on the
//       next launch via the version-bump migration path in
//       `ActionRegistry.runFirstLaunchSeeds()`.
//

import Foundation

enum DefaultTransformationSeed {

    /// Bump when adding or renaming a bundled transformation so existing
    /// installations re-run the seed pass and pick up the new entries.
    /// 2 — added Unicode pseudo-font family ("Font: Bold", etc.).
    /// 3 — rebranded fancy-text actions to stylized-letter prefix
    ///     ("𝐀  Bold"), restricted them to .text only, dropped Regional
    ///     Indicator, fixed Upside Down to keep letter order. Migration in
    ///     ActionRegistry.rebrandFancyTextIfNeeded picks these changes up
    ///     on existing installs without nuking user customizations.
    /// 4 — added "К → K  Cyrillic transliteration" (Russian / Ukrainian /
    ///     Belarusian / Bulgarian / Serbian / Macedonian with auto-detect).
    /// 5 — expanded `builtin.md_headings` and `builtin.md_links` from
    ///     [.markdown] to [.markdown, .text, .richText] so they're
    ///     applicable to plain text and rich-text clips too. Migration
    ///     in `ActionRegistry.expandMarkdownExtractTypesIfNeeded` patches
    ///     existing installs without touching user-edited applicableTypes.
    /// 6 — added `builtin.font_markdown` (Markdown styles → Unicode):
    ///     parses **bold** / *italic* / `code` / ~~strike~~ and applies
    ///     pseudo-fonts span-by-span. Seeded via the normal new-entry
    ///     path in `seedTransformations`; no extra migration required.
    /// 7 — added 0.53.0 batch: Latin → Cyrillic (target-language reverse
    ///     transliteration, mirrors Cyrillic → Latin), Pretty Code Local
    ///     (deterministic JSON/XML/HTML/CSS/generic), and three Fun /
    ///     Internet Slang entries (Leetspeak, UwU, Zalgo). Seeded via the
    ///     normal new-entry path in `seedTransformations`; no migration
    ///     required.
    /// 8 — added 0.55.0 batch (#A72 missing actions audit): HTML strip
    ///     tags / escape / unescape, JSON validate, normalize spaces,
    ///     collapse blank lines, extract emails, extract links. Filling
    ///     gaps the brain-storm spec flagged that weren't covered by
    ///     existing engines. Seeded via the normal new-entry path; no
    ///     migration required.
    /// 9 — #A74 pre-distribution ID consolidation (0.56.0). Every
    ///     default-shipped action ID renamed under convention v2
    ///     (`<namespace>.<content_kind>.<verb_noun>`). Migration in
    ///     `IDMigration056.apply()` runs first in
    ///     `runFirstLaunchSeeds` and rewrites every dict key in
    ///     ActionConfig. Also bundles new transformations: text
    ///     remove_line_breaks + 2 wrap descriptors (smart quotes,
    ///     parens), table.to_html. Plus merges duplicate
    ///     `paste_as_text` + `clean_formatting` → single
    ///     `builtin.rich.strip_formatting`.
    static let currentSeedVersion: Int = 9

    /// All bundled transformations. IDs follow convention v2 (#A74, 0.56.0):
    /// `<namespace>.<content_kind>.<verb_noun>`. Content kind = source
    /// SemanticKind (matches HUD chip filter). Sub-domain (translit /
    /// HTML / fun / etc.) lives in title + verb_noun, NOT in category.
    static func defaults() -> [CustomTransformationDescriptor] {
        [
            // MARK: text — case
            descriptor(id: "builtin.text.uppercase",      title: "UPPERCASE",       engine: .caseChange,   params: ["case": "upper"],     types: [.text, .markdown, .code]),
            descriptor(id: "builtin.text.lowercase",      title: "lowercase",       engine: .caseChange,   params: ["case": "lower"],     types: [.text, .markdown, .code]),
            descriptor(id: "builtin.text.title_case",     title: "Title Case",      engine: .caseChange,   params: ["case": "title"],     types: [.text, .markdown]),
            descriptor(id: "builtin.text.sentence_case",  title: "Sentence case",   engine: .caseChange,   params: ["case": "sentence"],  types: [.text, .markdown]),
            descriptor(id: "builtin.text.camel_case",     title: "camelCase",       engine: .camelCase,    params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.text.snake_case",     title: "snake_case",      engine: .snakeCase,    params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.text.kebab_case",     title: "kebab-case",      engine: .kebabCase,    params: [:],                   types: [.text, .code]),

            // MARK: text — whitespace and lines
            descriptor(id: "builtin.text.trim",           title: "Trim whitespace", engine: .trim,         params: [:],                   types: [.text, .markdown, .code]),
            descriptor(id: "builtin.text.sort_lines",     title: "Sort lines",      engine: .sortLines,    params: ["direction": "asc", "caseInsensitive": "false"], types: [.text, .markdown, .code]),
            descriptor(id: "builtin.text.unique_lines",   title: "Unique lines",    engine: .uniqueLines,  params: [:],                   types: [.text, .markdown, .code]),
            // #A74 (0.56.0) — new: join soft-wrapped lines.
            descriptor(id: "builtin.text.remove_line_breaks", title: "Remove line breaks", engine: .removeLineBreaks, params: [:], types: [.text, .markdown, .richText], requiredTraits: ["wrappedLines"]),

            // MARK: text — encoding
            descriptor(id: "builtin.text.base64_encode", title: "Base64 encode",   engine: .base64Encode, params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.text.base64_decode", title: "Base64 decode",   engine: .base64Decode, params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.url.encode",         title: "URL encode",      engine: .urlPercentEncode, params: [:],               types: [.text, .url, .code]),
            descriptor(id: "builtin.url.decode",         title: "URL decode",      engine: .urlPercentDecode, params: [:],               types: [.text, .url, .code]),

            // MARK: text — derived
            descriptor(id: "builtin.text.slugify",       title: "Slugify",         engine: .slugify,      params: [:],                   types: [.text]),
            descriptor(id: "builtin.text.word_count",    title: "Word / char count", engine: .wordCount,  params: [:],                   types: [.text, .markdown, .code]),

            // MARK: text — wrap (#A74, 0.56.0 — uses existing wrap engine)
            descriptor(id: "builtin.text.wrap_quotes",   title: "Wrap in “smart quotes”", engine: .wrap, params: ["prefix": "\u{201C}", "suffix": "\u{201D}"], types: [.text, .code, .markdown]),
            descriptor(id: "builtin.text.wrap_parens",   title: "Wrap in (parens)",       engine: .wrap, params: ["prefix": "(", "suffix": ")"], types: [.text, .code, .markdown]),

            // MARK: json
            descriptor(id: "builtin.json.pretty",        title: "Pretty JSON",     engine: .jsonFormat,   params: ["operation": "pretty"],  types: [.json]),
            descriptor(id: "builtin.json.minify",        title: "Minify JSON",     engine: .jsonFormat,   params: ["operation": "minify"],  types: [.json]),
            descriptor(id: "builtin.json.extract_keys",  title: "Extract keys",    engine: .jsonFormat,   params: ["operation": "extractKeysRecursive"], types: [.json]),

            // MARK: code
            descriptor(id: "builtin.code.wrap_block",      title: "Wrap in code block", engine: .wrap,        params: ["prefix": "```\n", "suffix": "\n```"], types: [.text, .code, .markdown]),
            descriptor(id: "builtin.code.tabs_to_spaces",  title: "Tabs → 4 spaces",    engine: .findReplace, params: ["find": "\t", "replace": "    ", "caseInsensitive": "false"], types: [.text, .code]),
            descriptor(id: "builtin.code.spaces_to_tabs",  title: "4 spaces → tabs",    engine: .findReplace, params: ["find": "    ", "replace": "\t", "caseInsensitive": "false"], types: [.text, .code]),

            // MARK: md
            descriptor(id: "builtin.md.to_plain",          title: "Markdown → plain",   engine: .mdToPlain,         params: [:], types: [.markdown]),
            descriptor(id: "builtin.md.extract_headings",  title: "Extract headings",   engine: .mdExtractHeadings, params: [:], types: [.markdown, .text, .richText]),
            descriptor(id: "builtin.md.extract_links",     title: "Extract links",      engine: .mdExtractLinks,    params: [:], types: [.markdown, .text, .richText]),

            // MARK: url
            descriptor(id: "builtin.url.strip_tracking",   title: "Clean URL",          engine: .urlStripTracking,  params: [:], types: [.url]),

            // Unicode pseudo-fonts ("Fancy text"). Each action shows a
            // stylized capital A as the title prefix so the user sees at a
            // glance what the output looks like, no separate "Font:" word
            // required. These are NOT real font changes — they're decorative
            // Unicode code points — so the prefix uses the actual styled
            // glyph as a self-demonstrating preview. All restricted to .text
            // only (decorative styling is inappropriate for code / URLs /
            // markdown which need exact glyphs preserved).
            unicodeFontDescriptor("builtin.text.font_bold",                  .bold,             prefix: "𝐀"),
            unicodeFontDescriptor("builtin.text.font_italic",                .italic,           prefix: "𝐴"),
            unicodeFontDescriptor("builtin.text.font_bold_italic",           .boldItalic,       prefix: "𝑨"),
            unicodeFontDescriptor("builtin.text.font_script",                .script,           prefix: "𝒜"),
            unicodeFontDescriptor("builtin.text.font_bold_script",           .boldScript,       prefix: "𝓐"),
            unicodeFontDescriptor("builtin.text.font_fraktur",               .fraktur,          prefix: "𝔄"),
            unicodeFontDescriptor("builtin.text.font_bold_fraktur",          .boldFraktur,      prefix: "𝕬"),
            unicodeFontDescriptor("builtin.text.font_double_struck",         .doubleStruck,     prefix: "𝔸"),
            unicodeFontDescriptor("builtin.text.font_sans",                  .sans,             prefix: "𝖠"),
            unicodeFontDescriptor("builtin.text.font_sans_bold",             .sansBold,         prefix: "𝗔"),
            unicodeFontDescriptor("builtin.text.font_sans_italic",           .sansItalic,       prefix: "𝘈"),
            unicodeFontDescriptor("builtin.text.font_sans_bold_italic",      .sansBoldItalic,   prefix: "𝘼"),
            unicodeFontDescriptor("builtin.text.font_monospace",             .monospace,        prefix: "𝙰"),
            unicodeFontDescriptor("builtin.text.font_fullwidth",             .fullwidth,        prefix: "Ａ"),
            unicodeFontDescriptor("builtin.text.font_small_caps",            .smallCaps,        prefix: "ᴀ"),
            unicodeFontDescriptor("builtin.text.font_circled",               .circled,          prefix: "Ⓐ"),
            unicodeFontDescriptor("builtin.text.font_filled_circled",        .filledCircled,    prefix: "🅐"),
            unicodeFontDescriptor("builtin.text.font_squared",               .squared,          prefix: "🄰"),
            unicodeFontDescriptor("builtin.text.font_filled_squared",        .filledSquared,    prefix: "🅰"),
            unicodeFontDescriptor("builtin.text.font_upside_down",           .upsideDown,       prefix: "∀"),
            // Markdown-aware stylization. Parses **bold** / *italic* /
            // ***bold-italic*** / `code` / ~~strike~~ inline markdown
            // markup and applies the matching Unicode pseudo-font style
            // span-by-span. Markup characters are dropped — output is
            // plain Unicode-styled text. Useful for Twitter / X,
            // Telegram bios, LinkedIn captions, Discord profiles,
            // anywhere markdown isn't rendered but emphasis matters.
            descriptor(
                id: "builtin.text.font_markdown",
                title: "**md** → 𝐦𝐝  Markdown styles → Unicode",
                engine: .unicodeStyle,
                params: ["style": UnicodeFontStyle.markdownAware.rawValue],
                types: [.text, .markdown]
            ),
            // Reverse pass — strip any styled Unicode back to plain ASCII.
            descriptor(
                id: "builtin.text.font_plain",
                title: "𝒜 → ABC  Plain ASCII",
                engine: .unicodeStyle,
                params: ["style": UnicodeFontStyle.plain.rawValue],
                types: [.text]
            ),

            // MARK: text — transliteration
            descriptor(
                id: "builtin.text.cyrillic_to_latin",
                title: "Ћ → Ć  Cyrillic translit",
                engine: .cyrillicToLatin,
                params: [:],
                types: [.text],
                requiredTraits: ["containsCyrillic"]
            ),
            descriptor(
                id: "builtin.text.latin_to_cyrillic",
                title: "Ć → Ћ  Latin translit",
                engine: .latinToCyrillic,
                // "auto": pick the target from characteristic letters, then
                // locale, then Russian. Users create explicit per-language
                // actions when they want a fixed target.
                params: ["target": "auto"],
                types: [.text],
                // Latin → Cyrillic only makes sense on pure-Latin text — see
                // #A77 (locale-aware default is a separate, later refinement).
                requiredTraits: ["containsLatin"],
                forbiddenTraits: ["containsCyrillic"]
            ),

            // MARK: code — Pretty Code Local
            descriptor(
                id: "builtin.code.pretty_local",
                title: "Pretty Code (local)",
                engine: .prettyCodeLocal,
                params: [:],
                types: [.code, .json, .text]
            ),

            // MARK: text — fun / Internet slang
            descriptor(
                id: "builtin.text.leetspeak",
                title: "Leetspeak / 1337",
                engine: .leetspeak,
                params: ["aggressive": "false"],
                types: [.text, .code]
            ),
            descriptor(
                id: "builtin.text.uwu_speak",
                title: "UwU speech",
                engine: .uwuSpeak,
                params: ["faces": "true"],
                types: [.text, .markdown]
            ),
            descriptor(
                id: "builtin.text.zalgo",
                title: "Zalgo corruption",
                engine: .zalgo,
                params: ["intensity": "medium"],
                types: [.text]
            ),

            // MARK: html — strip / escape / unescape (operate on HTML markup;
            //         content_kind = `html` per convention v2).
            descriptor(id: "builtin.html.strip_tags",
                       title: "Strip HTML tags",
                       engine: .htmlStripTags,
                       params: [:],
                       types: [.text, .richText, .code]),
            descriptor(id: "builtin.html.escape",
                       title: "Escape HTML",
                       engine: .htmlEscape,
                       params: [:],
                       types: [.text, .code]),
            descriptor(id: "builtin.html.unescape",
                       title: "Unescape HTML",
                       engine: .htmlUnescape,
                       params: [:],
                       types: [.text, .code]),
            descriptor(id: "builtin.json.validate",
                       title: "Validate JSON",
                       engine: .jsonValidate,
                       params: [:],
                       types: [.json, .text]),
            descriptor(id: "builtin.text.normalize_spaces",
                       title: "Normalize spaces",
                       engine: .normalizeSpaces,
                       params: [:],
                       types: [.text, .markdown, .code],
                       requiredTraits: ["messySpacing"]),
            descriptor(id: "builtin.text.collapse_blank_lines",
                       title: "Collapse blank lines",
                       engine: .collapseBlankLines,
                       params: [:],
                       types: [.text, .markdown, .code]),
            descriptor(id: "builtin.text.extract_emails",
                       title: "Extract emails",
                       engine: .extractEmails,
                       params: [:],
                       types: [.text, .markdown, .richText, .code],
                       requiredTraits: ["containsEmails"]),
            descriptor(id: "builtin.text.extract_links",
                       title: "Extract links",
                       engine: .extractLinks,
                       params: [:],
                       types: [.text, .markdown, .richText, .code],
                       requiredTraits: ["containsURLs"])
        ]
    }

    private static func unicodeFontDescriptor(_ id: String,
                                              _ style: UnicodeFontStyle,
                                              prefix: String) -> CustomTransformationDescriptor {
        descriptor(
            id: id,
            title: "\(prefix)  \(style.displayName)",
            engine: .unicodeStyle,
            params: ["style": style.rawValue],
            types: [.text]
        )
    }

    // MARK: - Helpers

    private static func descriptor(id: String,
                                   title: String,
                                   engine: TransformationEngine,
                                   params: [String: String],
                                   types: [SemanticKind],
                                   requiredTraits: [String] = [],
                                   forbiddenTraits: [String] = []) -> CustomTransformationDescriptor {
        CustomTransformationDescriptor(
            id: id,
            title: title,
            engineID: engine.rawValue,
            parameters: params,
            applicableTypes: types.map(\.rawValue),
            enabled: true,
            requiredTraits: requiredTraits,
            forbiddenTraits: forbiddenTraits
        )
    }
}
