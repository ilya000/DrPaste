//
//  MoreActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Code, Table, Rich text actions (Backlog #4).
//

import Foundation
import AppKit

// Code-related actions (WrapInCodeBlock, TabsToSpaces, SpacesToTabs) migrated
// to DefaultTransformationSeed:
//   builtin.code_wrap        → engine wrap
//   builtin.tabs_to_spaces   → engine findReplace
//   builtin.spaces_to_tabs   → engine findReplace

// MARK: - Table

struct TableToJSONAction: ClipboardAction {
    let id = "builtin.table.to_json"; let title = "CSV → JSON"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.table)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Codex sweep — robust parse (quoted fields with embedded delimiters /
        // newlines survive) via the single shared CSVParser.
        let source = item.previewText ?? ""
        let table = CSVParser.parse(source, delimiter: CSVParser.detectDelimiter(source))
        guard table.count >= 2, let headers = table.first else {
            return .failed(original: item, reason: "Need at least 2 rows", recovery: nil)
        }
        var rows: [[String: String]] = []
        for values in table.dropFirst() {
            var row: [String: String] = [:]
            for (i, h) in headers.enumerated() {
                row[h] = i < values.count ? values[i] : ""
            }
            rows.append(row)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return .failed(original: item, reason: "JSON encoding failed", recovery: nil)
        }
        return .preview(makeTextItem(str, from: item))
    }
}

struct TableToMarkdownAction: ClipboardAction {
    let id = "builtin.table.to_md"; let title = "CSV → Markdown table"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.table)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Codex sweep — shared robust parser (quoted fields survive).
        let source = item.previewText ?? ""
        let rows = CSVParser.parse(source, delimiter: CSVParser.detectDelimiter(source))
        guard rows.count >= 2 else {
            return .failed(original: item, reason: "Need at least 2 rows", recovery: nil)
        }
        let cols = rows[0].count
        // Markdown cells: escape the pipe so a value containing "|" doesn't
        // break the table layout.
        func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|") }
        let header = "| " + rows[0].map(cell).joined(separator: " | ") + " |"
        let divider = "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"
        let body = rows.dropFirst().map { "| " + $0.map(cell).joined(separator: " | ") + " |" }
        let result = ([header, divider] + body).joined(separator: "\n")
        return .preview(makeTextItem(result, from: item))
    }
}

// TableTransposeAction (Transpose) removed in 0.12.0 — table-specific niche,
// no marketing weight.

// MARK: - Rich text

struct RichTextToMarkdownAction: ClipboardAction {
    let id = "builtin.rich.to_md"; let title = "Rich → Markdown"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.richText)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Codex #3 — load via the shared loader (flat-RTFD aware), and use the
        // fuller RichTextHelpers converter (bold / italic / monospace / headings
        // / links) rather than the old bold+italic-only inline pass.
        guard let attr = RichTextHelpers.loadAttributed(from: item),
              let md = RichTextHelpers.attributedStringToMarkdown(attr, escapeLiterals: true) else {
            return .preview(makePlainText(item))
        }
        return .preview(makeTextItem(md, from: item))
    }
}

// MARK: - Packs

enum CodeActionsPack {
    static var all: [ClipboardAction] { [] }
}

enum TableActionsPack {
    static var all: [ClipboardAction] {
        [TableToJSONAction(), TableToMarkdownAction()]
    }
}

// MARK: - Rich → HTML

struct RichTextToHTMLAction: ClipboardAction {
    let id = "builtin.rich.to_html"; let title = "Rich → HTML"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.richText)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Codex #3 — flat-RTFD aware loader (clips with attachments are stored
        // as com.apple.flat-rtfd, not public.rtf).
        guard let attr = RichTextHelpers.loadAttributed(from: item),
              let html = RichTextHelpers.attributedStringToHTML(attr)
        else {
            return .failed(original: item, reason: "No rich-text representation found", recovery: nil)
        }
        return .preview(makeTextItem(html, from: item))
    }
}

// MARK: - Rich → Wiki markup

struct RichTextToWikiAction: ClipboardAction {
    let id = "builtin.rich.to_wiki"; let title = "Rich → Wiki markup"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.richText)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Codex #3 — flat-RTFD aware loader.
        let attr = RichTextHelpers.loadAttributed(from: item)
            ?? NSAttributedString(string: item.previewText ?? "")
        let wiki = RichTextHelpers.attributedStringToWiki(attr, escapeLiterals: true)
        return .preview(makeTextItem(wiki, from: item))
    }
}

// MARK: - Paste as text (combined clean + trim)

// #A74 — Merged with CleanFormattingAction (was builtin.clean_formatting +
// builtin.paste_as_text duplicate pair). Single ID under convention v2.
/// The single, universal "clean to plain text" action. Folds every kind of
/// styling down to plain characters:
///   • rich-text formatting (RTF / HTML) — `previewText` is already the
///     rendered plain string, so the styling is gone
///   • Markdown markup (`#`, `**`, `[]()`, …) for markdown / rich clips
///   • Unicode pseudo-font styling (𝐁𝐨𝐥𝐝, 𝓢𝓬𝓻𝓲𝓹𝓽, ⒶⒷⒸ, …) for every kind —
///     these decorative code points are just another form of markup
struct PasteAsTextAction: ClipboardAction {
    let id = "builtin.rich.strip_formatting"; let title = "Plain text"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // #A78 — only surface when there is actually something to strip:
        //   • rich text  → drop RTF/HTML styling
        //   • markdown   → drop #, **, [](), … markup
        //   • plain text / code carrying styled Unicode (𝐁𝐨𝐥𝐝 / Ⓐ / …) → fold it
        // On already-plain prose it's a no-op, so it no longer clutters the strip.
        if item.semantic == .richText || item.semantic == .markdown { return true }
        guard context.contains(.plain) else { return false }
        let text = item.previewText ?? ""
        // Bound the scan — huge plain clips rarely carry pseudo-font styling and
        // we don't want an O(n) fold on every applicability check.
        guard !text.isEmpty, text.count < 5000 else { return false }
        return UnicodeStylizer.normalize(text) != text
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        var text = item.previewText ?? ""
        // Markdown / rich clips: drop structural markup. (For rich text the
        // previewText is already rendered, so this is a no-op there; markdown
        // source gets its #, **, [](), … removed.) Plain text is left
        // structurally intact so incidental * / # in prose or math isn't
        // mangled.
        if item.semantic == .markdown || item.semantic == .richText {
            text = (try? TransformationRuntime.apply(engine: .mdToPlain, input: text, params: [:])) ?? text
        }
        // Unicode pseudo-font styling is decorative markup too — fold it back
        // to plain ASCII for every kind.
        text = UnicodeStylizer.apply(to: text, style: .plain)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return .preview(makeTextItem(text, from: item))
    }
}

// MARK: - Unicode Fancy (rich text → Unicode pseudo-font)

/// Walks the rich-text runs and renders each run in the corresponding
/// Unicode pseudo-font: bold runs become 𝐁𝐨𝐥𝐝, italic runs become 𝐼𝑡𝑎𝑙𝑖𝑐,
/// bold-italic runs become 𝑩𝒐𝒍𝒅 𝑰𝒕𝒂𝒍𝒊𝒄, monospace runs become 𝙼𝚘𝚗𝚘.
/// Output is plain text suitable for pasting into platforms that don't
/// support rich-text formatting (Twitter / X, Telegram bios, LinkedIn
/// captions, Discord profile descriptions, etc.). Letterforms outside
/// ASCII A-Z / a-z / 0-9 pass through unchanged.
struct RichTextToUnicodeStyledAction: ClipboardAction {
    let id = "builtin.rich.to_unicode_styled"
    let title = "Unicode Fancy"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Rich text OR Markdown — both carry bold/italic/code that map onto the
        // Unicode pseudo-fonts. Markdown source is parsed to an attributed
        // string first (`**bold**` → 𝐛𝐨𝐥𝐝). Gated to a chat / social context so
        // it doesn't clutter every rich/markdown clip.
        guard context.contains(.fromChat) else { return false }
        return context.contains(.richText) || item.semantic == .markdown
    }
    // Codex #9 — type-only membership (drops the fromChat gate) so the editor's
    // "Applies to" inference reports rich text / markdown instead of nothing.
    func appliesToContentType(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.richText) || item.semantic == .markdown
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let attr: NSAttributedString
        if item.semantic == .markdown {
            let src = item.previewText ?? ""
            attr = RichTextHelpers.markdownToAttributedString(src) ?? NSAttributedString(string: src)
        } else if let parsed = RichTextHelpers.loadAttributed(from: item) {
            attr = parsed   // Codex #3 — flat-RTFD aware
        } else {
            return .failed(original: item, reason: "No rich-text representation found", recovery: nil)
        }
        var result = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            let substring = attr.attributedSubstring(from: range).string
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)
            let isMono = traits.contains(.monoSpace)
            let style: UnicodeFontStyle
            if isMono              { style = .monospace }
            else if isBold && isItalic { style = .boldItalic }
            else if isBold         { style = .bold }
            else if isItalic       { style = .italic }
            else                   { style = .plain }
            // .plain runs go through normalize() which is essentially a no-op
            // for already-plain ASCII — keeps the body of the text legible.
            if style == .plain {
                result += substring
            } else {
                result += UnicodeStylizer.apply(to: substring, style: style)
            }
        }
        return .preview(makeTextItem(result, from: item))
    }
}

enum RichTextActionsPack {
    static var all: [ClipboardAction] {
        [RichTextToMarkdownAction(), RichTextToHTMLAction(), RichTextToWikiAction(),
         RichTextToUnicodeStyledAction(), PasteAsTextAction()]
    }
}
