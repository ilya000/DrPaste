//
//  MarkdownActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Markdown actions migrated to DefaultTransformationSeed:
//    builtin.md_to_plain      → engine mdToPlain
//    builtin.md_headings      → engine mdExtractHeadings
//    builtin.md_links         → engine mdExtractLinks
//
//  Pack kept as an empty stub so existing pack-registration call sites in
//  main.swift continue to compile and so future markdown-specific actions
//  that don't fit the engine model have a home.
//

import Foundation

enum MarkdownActionsPack {
    static var all: [ClipboardAction] { [] }
}
