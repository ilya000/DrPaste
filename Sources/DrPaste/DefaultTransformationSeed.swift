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
    static let currentSeedVersion: Int = 1

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
            descriptor(id: "builtin.md_headings",        title: "Extract headings",   engine: .mdExtractHeadings, params: [:], types: [.markdown]),
            descriptor(id: "builtin.md_links",           title: "Extract links",      engine: .mdExtractLinks,    params: [:], types: [.markdown]),

            // URL.
            descriptor(id: "builtin.url_strip_tracking", title: "Clean URL",          engine: .urlStripTracking,  params: [:], types: [.url])
        ]
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
