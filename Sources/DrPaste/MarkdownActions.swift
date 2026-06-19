//
//  MarkdownActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Markdown actions migrated to DefaultTransformationSeed:
//    builtin.md_to_plain      → engine mdToPlain
//    builtin.md_headings      → engine mdExtractHeadings
//    builtin.md_links         → engine mdExtractLinks
//
//  Hardcoded actions that don't fit the engine model live here:
//    builtin.md_to_rich       — Markdown → rich-text NSAttributedString
//                                with bold/italic/links rendered.
//

import Foundation
import AppKit

// MARK: - Markdown → Rich Text

/// Parse plain-text Markdown into NSAttributedString and emit as a
/// rich-text clipboard item. The inverse of `mdToPlain` (which strips
/// markup and outputs plain text). Useful for users who keep their
/// notes in Markdown source and want to paste the rendered version into
/// Mail / Pages / Notes / Word — anywhere that understands RTF.
///
/// Rendering uses macOS 12+'s native `NSAttributedString(markdown:)` with
/// `.inlineOnlyPreservingWhitespace` so bold (`**…**`), italic (`*…*`),
/// inline code (`` `…` ``), and links (`[text](url)`) round-trip cleanly.
/// Block-level structure (headings, lists, blockquotes) is preserved as
/// whitespace + the bare line markers — the inline-only mode keeps the
/// transformation predictable and reversible without the Swift Markdown
/// library dependency that `.full` would require.
struct MarkdownToRichTextAction: ClipboardAction {
    let id = "builtin.md.to_rich"
    let title = "Markdown → Rich text"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Markdown-only: rendering Markdown source to rich text is meaningless
        // for plain text / code clips, where it would just clutter the HUD.
        item.semantic == .markdown
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let source = item.previewText ?? ""
        guard !source.isEmpty else {
            return .failed(original: item, reason: "Empty input", recovery: nil)
        }
        guard let attr = RichTextHelpers.markdownToAttributedString(source) else {
            return .failed(original: item,
                           reason: "Markdown parser couldn't read this input",
                           recovery: nil)
        }
        return .preview(makeRichTextItem(attr, from: item))
    }
}

// MARK: - Markdown → Wiki markup

/// Markdown counterpart of `Rich → Wiki markup`: converts Markdown source into
/// MediaWiki syntax (headings, lists, bold / italic / code / strikethrough /
/// links). Markdown-only.
struct MarkdownToWikiAction: ClipboardAction {
    let id = "builtin.md.to_wiki"
    let title = "Markdown → Wiki markup"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        item.semantic == .markdown
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let source = item.previewText ?? ""
        guard !source.isEmpty else {
            return .failed(original: item, reason: "Empty input", recovery: nil)
        }
        return .preview(makeTextItem(RichTextHelpers.markdownToWiki(source), from: item))
    }
}

enum MarkdownActionsPack {
    static var all: [ClipboardAction] { [MarkdownToRichTextAction(), MarkdownToWikiAction()] }
}
