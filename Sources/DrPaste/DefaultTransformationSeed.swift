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
    static let currentSeedVersion: Int = 7

    /// All bundled transformations. IDs match the legacy hardcoded action IDs
    /// so existing user customizations carry over without remapping.
    static func defaults() -> [CustomTransformationDescriptor] {
        [
            // Plain text — case.
            descriptor(id: "builtin.uppercase",      title: "UPPERCASE",       engine: .caseChange,   params: ["case": "upper"],     types: [.text, .markdown, .code]),
            descriptor(id: "builtin.lowercase",      title: "lowercase",       engine: .caseChange,   params: ["case": "lower"],     types: [.text, .markdown, .code]),
            descriptor(id: "builtin.title_case",     title: "Title Case",      engine: .caseChange,   params: ["case": "title"],     types: [.text, .markdown]),
            descriptor(id: "builtin.sentence_case",  title: "Sentence case",   engine: .caseChange,   params: ["case": "sentence"],  types: [.text, .markdown]),
            descriptor(id: "builtin.camel_case",     title: "camelCase",       engine: .camelCase,    params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.snake_case",     title: "snake_case",      engine: .snakeCase,    params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.kebab_case",     title: "kebab-case",      engine: .kebabCase,    params: [:],                   types: [.text, .code]),

            // Plain text — whitespace and lines.
            descriptor(id: "builtin.trim",           title: "Trim whitespace", engine: .trim,         params: [:],                   types: [.text, .markdown, .code]),
            descriptor(id: "builtin.sort_lines",    title: "Sort lines",      engine: .sortLines,    params: ["direction": "asc", "caseInsensitive": "false"], types: [.text, .markdown, .code]),
            descriptor(id: "builtin.unique_lines",  title: "Unique lines",    engine: .uniqueLines,  params: [:],                   types: [.text, .markdown, .code]),

            // Plain text — encoding.
            descriptor(id: "builtin.base64_encode", title: "Base64 encode",   engine: .base64Encode, params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.base64_decode", title: "Base64 decode",   engine: .base64Decode, params: [:],                   types: [.text, .code]),
            descriptor(id: "builtin.url_encode",    title: "URL encode",      engine: .urlPercentEncode, params: [:],               types: [.text, .url, .code]),
            descriptor(id: "builtin.url_decode",    title: "URL decode",      engine: .urlPercentDecode, params: [:],               types: [.text, .url, .code]),

            // Plain text — derived.
            descriptor(id: "builtin.slugify",       title: "Slugify",         engine: .slugify,      params: [:],                   types: [.text]),
            descriptor(id: "builtin.word_count",    title: "Word / char count", engine: .wordCount,  params: [:],                   types: [.text, .markdown, .code]),

            // JSON.
            descriptor(id: "builtin.json_pretty",   title: "Pretty JSON",     engine: .jsonFormat,   params: ["operation": "pretty"],  types: [.json]),
            descriptor(id: "builtin.json_minify",   title: "Minify JSON",     engine: .jsonFormat,   params: ["operation": "minify"],  types: [.json]),
            descriptor(id: "builtin.json_keys",     title: "Extract keys",    engine: .jsonFormat,   params: ["operation": "extractKeysRecursive"], types: [.json]),

            // Code.
            descriptor(id: "builtin.code_wrap",        title: "Wrap in code block", engine: .wrap,        params: ["prefix": "```\n", "suffix": "\n```"], types: [.text, .code, .markdown]),
            descriptor(id: "builtin.tabs_to_spaces",   title: "Tabs → 4 spaces",    engine: .findReplace, params: ["find": "\t", "replace": "    ", "caseInsensitive": "false"], types: [.text, .code]),
            descriptor(id: "builtin.spaces_to_tabs",   title: "4 spaces → tabs",    engine: .findReplace, params: ["find": "    ", "replace": "\t", "caseInsensitive": "false"], types: [.text, .code]),

            // Markdown.
            descriptor(id: "builtin.md_to_plain",        title: "Markdown → plain",   engine: .mdToPlain,         params: [:], types: [.markdown]),
            descriptor(id: "builtin.md_headings",        title: "Extract headings",   engine: .mdExtractHeadings, params: [:], types: [.markdown, .text, .richText]),
            descriptor(id: "builtin.md_links",           title: "Extract links",      engine: .mdExtractLinks,    params: [:], types: [.markdown, .text, .richText]),

            // URL.
            descriptor(id: "builtin.url_strip_tracking", title: "Clean URL",          engine: .urlStripTracking,  params: [:], types: [.url]),

            // Unicode pseudo-fonts ("Fancy text"). Each action shows a
            // stylized capital A as the title prefix so the user sees at a
            // glance what the output looks like, no separate "Font:" word
            // required. These are NOT real font changes — they're decorative
            // Unicode code points — so the prefix uses the actual styled
            // glyph as a self-demonstrating preview. All restricted to .text
            // only (decorative styling is inappropriate for code / URLs /
            // markdown which need exact glyphs preserved).
            unicodeFontDescriptor("builtin.font_bold",                  .bold,             prefix: "𝐀"),
            unicodeFontDescriptor("builtin.font_italic",                .italic,           prefix: "𝐴"),
            unicodeFontDescriptor("builtin.font_bold_italic",           .boldItalic,       prefix: "𝑨"),
            unicodeFontDescriptor("builtin.font_script",                .script,           prefix: "𝒜"),
            unicodeFontDescriptor("builtin.font_bold_script",           .boldScript,       prefix: "𝓐"),
            unicodeFontDescriptor("builtin.font_fraktur",               .fraktur,          prefix: "𝔄"),
            unicodeFontDescriptor("builtin.font_bold_fraktur",          .boldFraktur,      prefix: "𝕬"),
            unicodeFontDescriptor("builtin.font_double_struck",         .doubleStruck,     prefix: "𝔸"),
            unicodeFontDescriptor("builtin.font_sans",                  .sans,             prefix: "𝖠"),
            unicodeFontDescriptor("builtin.font_sans_bold",             .sansBold,         prefix: "𝗔"),
            unicodeFontDescriptor("builtin.font_sans_italic",           .sansItalic,       prefix: "𝘈"),
            unicodeFontDescriptor("builtin.font_sans_bold_italic",      .sansBoldItalic,   prefix: "𝘼"),
            unicodeFontDescriptor("builtin.font_monospace",             .monospace,        prefix: "𝙰"),
            unicodeFontDescriptor("builtin.font_fullwidth",             .fullwidth,        prefix: "Ａ"),
            unicodeFontDescriptor("builtin.font_small_caps",            .smallCaps,        prefix: "ᴀ"),
            unicodeFontDescriptor("builtin.font_circled",               .circled,          prefix: "Ⓐ"),
            unicodeFontDescriptor("builtin.font_filled_circled",        .filledCircled,    prefix: "🅐"),
            unicodeFontDescriptor("builtin.font_squared",               .squared,          prefix: "🄰"),
            unicodeFontDescriptor("builtin.font_filled_squared",        .filledSquared,    prefix: "🅰"),
            unicodeFontDescriptor("builtin.font_upside_down",           .upsideDown,       prefix: "∀"),
            // Markdown-aware stylization. Parses **bold** / *italic* /
            // ***bold-italic*** / `code` / ~~strike~~ inline markdown
            // markup and applies the matching Unicode pseudo-font style
            // span-by-span. Markup characters are dropped — output is
            // plain Unicode-styled text. Useful for Twitter / X,
            // Telegram bios, LinkedIn captions, Discord profiles,
            // anywhere markdown isn't rendered but emphasis matters.
            descriptor(
                id: "builtin.font_markdown",
                title: "**md** → 𝐦𝐝  Markdown styles → Unicode",
                engine: .unicodeStyle,
                params: ["style": UnicodeFontStyle.markdownAware.rawValue],
                types: [.text, .markdown]
            ),
            // Reverse pass — strip any styled Unicode back to plain ASCII.
            // Title visualises the direction: stylized A → plain ABC.
            descriptor(
                id: "builtin.font_plain",
                title: "𝒜 → ABC  Plain ASCII",
                engine: .unicodeStyle,
                params: ["style": UnicodeFontStyle.plain.rawValue],
                types: [.text]
            ),

            // Cyrillic → Latin transliteration. Auto-detects script variant
            // (Russian / Ukrainian / Belarusian / Bulgarian / Serbian /
            // Macedonian) by marker letters and applies the appropriate
            // scheme. Chains well into the fancy-font actions: paste a
            // Cyrillic name → transliterate → ⌥⌘Space → "𝐀 Bold".
            descriptor(
                id: "builtin.cyrillic_translit",
                title: "К → K  Cyrillic transliteration",
                engine: .cyrillicToLatin,
                params: [:],
                types: [.text]
            ),

            // Latin → Cyrillic (#A18). Reverse transliteration with target
            // language parameter. Russian default; the editor lets users
            // pick Ukrainian / Bulgarian / Serbian variants.
            descriptor(
                id: "builtin.latin_to_cyrillic",
                title: "K → К  Latin → Cyrillic",
                engine: .latinToCyrillic,
                params: ["target": "russian"],
                types: [.text]
            ),

            // Pretty Code Local (#A19). Auto-detects JSON / XML / HTML /
            // CSS by leading chars, falls back to generic whitespace
            // normalization. Offline, sub-50 ms. The AI counterpart
            // ("Pretty Code: AI") ships separately in 0.54.0.
            descriptor(
                id: "builtin.pretty_code_local",
                title: "Pretty Code (local)",
                engine: .prettyCodeLocal,
                params: [:],
                types: [.code, .json, .text]
            ),

            // Fun / Internet Slang group (#A70). Three local deterministic
            // novelties. The two AI counterparts (LOLspeak, Hacker
            // Terminal) ship in 0.54.0 with the rest of the AI pairs.
            descriptor(
                id: "builtin.leetspeak",
                title: "Leetspeak / 1337",
                engine: .leetspeak,
                params: ["aggressive": "false"],
                types: [.text, .code]
            ),
            descriptor(
                id: "builtin.uwu_speak",
                title: "UwU speech",
                engine: .uwuSpeak,
                params: ["faces": "true"],
                types: [.text, .markdown]
            ),
            descriptor(
                id: "builtin.zalgo",
                title: "Zalgo corruption",
                engine: .zalgo,
                params: ["intensity": "medium"],
                types: [.text]
            )
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
                                   types: [SemanticKind]) -> CustomTransformationDescriptor {
        CustomTransformationDescriptor(
            id: id,
            title: title,
            engineID: engine.rawValue,
            parameters: params,
            applicableTypes: types.map(\.rawValue),
            enabled: true
        )
    }
}
