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
    let id = "builtin.table_to_json"; let title = "CSV → JSON"; let isLocal = true
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
    let id = "builtin.table_to_md"; let title = "CSV → Markdown table"; let isLocal = true
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
    let id = "builtin.rich_to_md"; let title = "Rich → Markdown"; let isLocal = true
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
    let id = "builtin.rich_to_html"; let title = "Rich → HTML"; let isLocal = true
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
    let id = "builtin.rich_to_wiki"; let title = "Rich → Wiki markup"; let isLocal = true
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

struct PasteAsTextAction: ClipboardAction {
    let id = "builtin.paste_as_text"; let title = "Paste as text"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain) || context.contains(.richText)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Strip formatting by reading previewText (already plain, no RTF/HTML).
        let plain = item.previewText ?? ""
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return .preview(makeTextItem(trimmed, from: item))
    }
}

enum RichTextActionsPack {
    static var all: [ClipboardAction] {
        [RichTextToMarkdownAction(), RichTextToHTMLAction(), RichTextToWikiAction(), PasteAsTextAction()]
    }
}
