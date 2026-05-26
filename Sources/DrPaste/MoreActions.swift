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

// MARK: - Code

struct WrapInCodeBlockAction: ClipboardAction {
    let id = "builtin.code_wrap"; let title = "Wrap in code block"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.code) || context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let s = item.previewText ?? ""
        let result = "```\n\(s)\n```"
        return .preview(makeTextItem(result, from: item))
    }
}

struct TabsToSpacesAction: ClipboardAction {
    let id = "builtin.tabs_to_spaces"; let title = "Tabs → 4 spaces"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        (context.contains(.code) || context.contains(.plain)) &&
        (item.previewText ?? "").contains("\t")
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let result = (item.previewText ?? "").replacingOccurrences(of: "\t", with: "    ")
        return .preview(makeTextItem(result, from: item))
    }
}

struct SpacesToTabsAction: ClipboardAction {
    let id = "builtin.spaces_to_tabs"; let title = "4 spaces → tabs"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        (context.contains(.code) || context.contains(.plain)) &&
        (item.previewText ?? "").contains("    ")
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let result = (item.previewText ?? "").replacingOccurrences(of: "    ", with: "\t")
        return .preview(makeTextItem(result, from: item))
    }
}

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

struct TableTransposeAction: ClipboardAction {
    let id = "builtin.table_transpose"; let title = "Transpose"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.table)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let lines = (item.previewText ?? "").split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return .preview(item) }
        let sep = lines[0].contains("\t") ? "\t" : ","
        let rows = lines.map { $0.components(separatedBy: sep) }
        let cols = rows.map(\.count).max() ?? 0
        var transposed: [[String]] = Array(repeating: [], count: cols)
        for row in rows {
            for col in 0..<cols {
                transposed[col].append(col < row.count ? row[col] : "")
            }
        }
        let result = transposed.map { $0.joined(separator: sep) }.joined(separator: "\n")
        return .preview(makeTextItem(result, from: item))
    }
}

// MARK: - Rich text

struct RichTextToMarkdownAction: ClipboardAction {
    let id = "builtin.rich_to_md"; let title = "Rich → Markdown"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.richText)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Минимальная conversion: RTF → AttributedString → emit markdown markers
        // (bold/italic only; полноценная conversion — отдельная правка с swift-markdown)
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
    static var all: [ClipboardAction] {
        [WrapInCodeBlockAction(), TabsToSpacesAction(), SpacesToTabsAction()]
    }
}

enum TableActionsPack {
    static var all: [ClipboardAction] {
        [TableToJSONAction(), TableToMarkdownAction(), TableTransposeAction()]
    }
}

enum RichTextActionsPack {
    static var all: [ClipboardAction] {
        [RichTextToMarkdownAction()]
    }
}
