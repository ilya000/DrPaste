//
//  CSVTableActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  CSV → table conversions (#A15). Two parallel actions sharing a
//  parser:
//
//    • CSV → Wiki table: MediaWiki/DokuWiki table markup, plain-text
//      output. Pastes into wiki editors as actionable markup.
//    • CSV → Rich (RTFD) table: NSTextTable with cells, RTFD output.
//      Pastes into Mail / Notes / Pages / Word as a rendered table.
//      Slack / Notion fall back to the plain-text representation —
//      acceptable per design.
//
//  Both accept the same input: a text or `.table` clip whose
//  previewText is CSV. The parser handles:
//    – Quoted fields with embedded commas / newlines / quotes ("")
//    – Trailing commas
//    – CRLF / LF / CR line endings (normalised to LF)
//

import Foundation
import AppKit

// MARK: - Shared CSV parser

/// Tiny CSV parser sized for the typical clipboard payload. Returns rows
/// of fields. Standard RFC-4180-ish behaviour:
///   • Comma separator (no auto-detect — `.csv` is canonical).
///   • Double-quoted fields preserve commas, newlines, and `""` escapes.
///   • Unquoted fields stop at the next comma / newline.
///   • Empty trailing line is dropped.
enum CSVParser {

    static func parse(_ source: String) -> [[String]] {
        // Normalise line endings up-front so the state machine only
        // has to deal with `\n`.
        let normalised = source.replacingOccurrences(of: "\r\n", with: "\n")
                               .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(normalised)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    // Escaped quote inside a quoted field.
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.append(c)
                i += 1
                continue
            }
            switch c {
            case ",":
                current.append(field); field = ""
            case "\n":
                current.append(field); field = ""
                rows.append(current); current = []
            case "\"":
                if field.isEmpty {
                    inQuotes = true
                } else {
                    field.append(c)
                }
            default:
                field.append(c)
            }
            i += 1
        }
        // Flush trailing field / row when the source didn't end with \n.
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        // Drop a trailing fully-empty row (input ended with \n).
        if rows.last?.allSatisfy(\.isEmpty) == true { rows.removeLast() }
        return rows
    }

    /// True when source looks plausibly CSV-shaped: at least two rows
    /// and the first row has at least 2 comma-separated fields. Used
    /// by isApplicable to keep both actions out of the chip list for
    /// non-CSV text.
    static func looksLikeCSV(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let firstLine = trimmed.components(separatedBy: "\n").first ?? ""
        // Need at least one comma in the first line — a single column
        // without commas isn't really a CSV worth tabulating.
        return firstLine.contains(",")
    }
}

// MARK: - CSV → Wiki table

/// Convert CSV input to MediaWiki / DokuWiki table syntax. Header row
/// is the first parsed row; remaining rows are body rows. Cells are
/// pipe-escaped where needed (rare) and stripped of outer whitespace.
struct CSVToWikiTableAction: ClipboardAction {
    let id = "builtin.table.to_wiki"
    let title = "CSV → Wiki table"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        switch item.semantic {
        case .text, .table, .code, .markdown:
            return CSVParser.looksLikeCSV(item.previewText ?? "")
        default:
            return false
        }
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let source = item.previewText, !source.isEmpty else {
            return .failed(original: item,
                           reason: "CSV → Wiki: empty input.",
                           recovery: nil)
        }
        let rows = CSVParser.parse(source)
        guard rows.count >= 1, let header = rows.first else {
            return .failed(original: item,
                           reason: "CSV → Wiki: no rows parsed.",
                           recovery: nil)
        }
        var out = "{| class=\"wikitable\"\n"
        // Header row uses `!` separators.
        let headerCells = header.map { sanitizeCell($0) }
        out += "! " + headerCells.joined(separator: " !! ") + "\n"
        for row in rows.dropFirst() {
            out += "|-\n"
            let cells = row.map { sanitizeCell($0) }
            out += "| " + cells.joined(separator: " || ") + "\n"
        }
        out += "|}"
        return .preview(makeTextItem(out, from: item))
    }

    /// Strip outer whitespace and escape characters that would otherwise
    /// terminate a wiki-cell run (pipe `|` and bang `!`).
    private func sanitizeCell(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        v = v.replacingOccurrences(of: "|", with: "&#124;")
        v = v.replacingOccurrences(of: "!", with: "&#33;")
        // Collapse internal newlines to <br> so the table layout survives.
        v = v.replacingOccurrences(of: "\n", with: "<br>")
        return v
    }
}

// MARK: - CSV → Rich (RTFD) table

/// Convert CSV input to an NSTextTable-backed rich-text clip. The
/// resulting RTFD pastes as a rendered table into Mail / Notes / Pages /
/// Word / TextEdit. Slack and Notion don't honour RTFD tables and will
/// fall through to the plain-text representation — acceptable per the
/// product spec (user confirmed in design discussion).
struct CSVToRichTableAction: ClipboardAction {
    let id = "builtin.table.to_rich"
    let title = "CSV → Rich table"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        switch item.semantic {
        case .text, .table, .code, .markdown:
            return CSVParser.looksLikeCSV(item.previewText ?? "")
        default:
            return false
        }
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let source = item.previewText, !source.isEmpty else {
            return .failed(original: item,
                           reason: "CSV → Rich: empty input.",
                           recovery: nil)
        }
        let rows = CSVParser.parse(source)
        guard rows.count >= 1, let header = rows.first else {
            return .failed(original: item,
                           reason: "CSV → Rich: no rows parsed.",
                           recovery: nil)
        }
        // Normalize columns: pad short rows to the header width so the
        // NSTextTable layout doesn't get a ragged grid.
        let cols = max(header.count, rows.dropFirst().map(\.count).max() ?? header.count)
        let padded = rows.map { row -> [String] in
            var r = row
            while r.count < cols { r.append("") }
            return Array(r.prefix(cols))
        }
        let attributed = buildTable(rows: padded, columnCount: cols)
        return .preview(makeRichTextItem(attributed, from: item))
    }

    /// Construct an NSAttributedString whose paragraph styles embed an
    /// NSTextTable. Each cell is a separate paragraph with the table-
    /// block list. The string itself is just `cell\n` per cell, with the
    /// formatting carrying the table structure — RTFD round-trips this.
    private func buildTable(rows: [[String]], columnCount: Int) -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)
        let body = NSMutableAttributedString()
        for (rowIdx, row) in rows.enumerated() {
            for (colIdx, cellText) in row.enumerated() {
                let block = NSTextTableBlock(table: table,
                                             startingRow: rowIdx,
                                             rowSpan: 1,
                                             startingColumn: colIdx,
                                             columnSpan: 1)
                block.setBorderColor(.gridColor)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setWidth(4, type: .absoluteValueType, for: .padding)
                let para = NSMutableParagraphStyle()
                para.textBlocks = [block]
                // Header row gets bold + slight padding emphasis.
                let font: NSFont = rowIdx == 0
                    ? NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                    : NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let cellAttr = NSAttributedString(
                    string: cellText + "\n",
                    attributes: [
                        .paragraphStyle: para,
                        .font: font,
                        .foregroundColor: NSColor.textColor
                    ]
                )
                body.append(cellAttr)
            }
        }
        return body
    }
}

// MARK: - Registry pack

// #A74 (0.56.0) — CSV → HTML <table>. Clean output ready for CMS / email.
struct CSVToHTMLTableAction: ClipboardAction {
    let id = "builtin.table.to_html"
    let title = "CSV → HTML table"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        switch item.semantic {
        case .text, .table, .code, .markdown:
            return CSVParser.looksLikeCSV(item.previewText ?? "")
        default:
            return false
        }
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let source = item.previewText, !source.isEmpty else {
            return .failed(original: item,
                           reason: "CSV → HTML: empty input.",
                           recovery: nil)
        }
        let rows = CSVParser.parse(source)
        guard rows.count >= 1, let header = rows.first else {
            return .failed(original: item,
                           reason: "CSV → HTML: no rows parsed.",
                           recovery: nil)
        }
        var html = "<table>\n  <thead>\n    <tr>"
        for cell in header {
            html += "<th>\(escape(cell))</th>"
        }
        html += "</tr>\n  </thead>\n  <tbody>\n"
        for row in rows.dropFirst() {
            html += "    <tr>"
            for cell in row {
                html += "<td>\(escape(cell))</td>"
            }
            html += "</tr>\n"
        }
        html += "  </tbody>\n</table>"
        return .preview(makeTextItem(html, from: item))
    }

    private func escape(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespaces)
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        return out
    }
}

enum CSVTableActionsPack {
    static var all: [ClipboardAction] {
        [CSVToWikiTableAction(), CSVToRichTableAction(), CSVToHTMLTableAction()]
    }
}
