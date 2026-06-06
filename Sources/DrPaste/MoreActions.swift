//
//  MoreActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
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
        let lines = (item.previewText ?? "").split(separator: "\n").map(String.init)
        guard lines.count >= 2 else {
            return .failed(original: item, reason: "Need at least 2 rows", recovery: nil)
        }
        let sep = lines[0].contains("\t") ? "\t" : ","
        let headers = lines[0].components(separatedBy: sep)
        var rows: [[String: String]] = []
        for line in lines.dropFirst() {
            let values = line.components(separatedBy: sep)
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
        let lines = (item.previewText ?? "").split(separator: "\n").map(String.init)
        guard lines.count >= 2 else {
            return .failed(original: item, reason: "Need at least 2 rows", recovery: nil)
        }
        let sep = lines[0].contains("\t") ? "\t" : ","
        let rows = lines.map { $0.components(separatedBy: sep) }
        let cols = rows[0].count
        let header = "| " + rows[0].joined(separator: " | ") + " |"
        let divider = "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"
        let body = rows.dropFirst().map { "| " + $0.joined(separator: " | ") + " |" }
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
        // Minimal conversion: RTF → AttributedString → emit Markdown markers
        // (bold/italic only). A full converter would require swift-markdown.
        guard let rel = item.representations["public.rtf"],
              let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
              let attr = try? NSAttributedString(data: data,
                                                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                  documentAttributes: nil) else {
            return .preview(makePlainText(item))
        }
        var result = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            let substring = attr.attributedSubstring(from: range).string
            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            var part = substring
            if isBold { part = "**\(part)**" }
            if isItalic { part = "*\(part)*" }
            result += part
        }
        return .preview(makeTextItem(result, from: item))
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
        guard let rel = item.representations["public.rtf"],
              let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
              let attr = try? NSAttributedString(data: data,
                                                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                  documentAttributes: nil),
              let html = RichTextHelpers.attributedStringToHTML(attr)
        else {
            return .failed(original: item, reason: "No RTF representation found", recovery: nil)
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
        let attr: NSAttributedString
        if let rel = item.representations["public.rtf"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let parsed = try? NSAttributedString(data: data,
                                                options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                documentAttributes: nil) {
            attr = parsed
        } else {
            attr = NSAttributedString(string: item.previewText ?? "")
        }
        let wiki = RichTextHelpers.attributedStringToWiki(attr)
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
        context.contains(.plain) || context.contains(.richText)
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
        // string first (`**bold**` → 𝐛𝐨𝐥𝐝).
        context.contains(.richText) || item.semantic == .markdown
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let attr: NSAttributedString
        if item.semantic == .markdown {
            let src = item.previewText ?? ""
            attr = RichTextHelpers.markdownToAttributedString(src) ?? NSAttributedString(string: src)
        } else if let rel = item.representations["public.rtf"],
              let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
              let parsed = try? NSAttributedString(data: data,
                                                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                  documentAttributes: nil) {
            attr = parsed
        } else {
            return .failed(original: item, reason: "No RTF representation found", recovery: nil)
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
