//
//  RichTextHelpers.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Converters between NSAttributedString and Markdown / Wiki markup. Used for
//  Markdown round-trip in AI rich-preserving actions and for Wiki export.
//

import Foundation
import AppKit

enum RichTextHelpers {

    // MARK: - NSAttributedString → Markdown

    /// Coarse attributed → Markdown conversion. Covers bold, italic, monospace
    /// (inline code), headings inferred from font size, and links. Does not
    /// cover tables, blockquotes, or nested lists. Sufficient for round-tripping
    /// AI transformations through Markdown.
    static func attributedStringToMarkdown(_ attr: NSAttributedString) -> String? {
        guard attr.length > 0 else { return "" }
        var result = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            let substring = attr.attributedSubstring(from: range).string
            guard !substring.isEmpty else { return }

            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isMonospace = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            let size = font?.pointSize ?? 13
            let lineStart = result.hasSuffix("\n") || result.isEmpty

            // Heading detection — large bold text at line start.
            let isHeading1 = size >= 22 && lineStart
            let isHeading2 = size >= 17 && size < 22 && isBold && lineStart
            let isHeading3 = size >= 14 && size < 17 && isBold && lineStart

            var segment = substring
            if let link = attrs[.link] as? URL {
                segment = "[\(segment)](\(link.absoluteString))"
            } else if let linkStr = attrs[.link] as? String {
                segment = "[\(segment)](\(linkStr))"
            }
            if isMonospace { segment = "`\(segment)`" }
            if isBold && isItalic { segment = "***\(segment)***" }
            else if isBold && !isHeading1 && !isHeading2 && !isHeading3 { segment = "**\(segment)**" }
            else if isItalic { segment = "*\(segment)*" }

            if isHeading1 { segment = "# \(segment)" }
            else if isHeading2 { segment = "## \(segment)" }
            else if isHeading3 { segment = "### \(segment)" }

            result += segment
        }
        return result
    }

    // MARK: - Markdown → NSAttributedString

    /// Render Markdown to a fully-formatted NSAttributedString — block AND
    /// inline structure. Uses `.full` parsing so headings, lists and fenced
    /// code blocks are recognised (not left as literal `#` / `-` / ``` text),
    /// translates the parser's `inlinePresentationIntent` metadata into real
    /// bold / italic / monospace fonts (it sets none itself), sizes headings,
    /// and inserts the block separators the parser omits. Returns nil only on a
    /// hard parse failure.
    static func markdownToAttributedString(_ markdown: String) -> NSAttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
            languageCode: nil)
        guard var attr = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown,
                                      attributes: [.font: NSFont.systemFont(ofSize: 13)])
        }
        let base = NSFont.systemFont(ofSize: 13)
        attr.font = base

        // Inline emphasis → real font traits (the parser only records metadata).
        for run in attr.runs {
            guard let inline = run.inlinePresentationIntent else { continue }
            var font = inline.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : base
            var traits: NSFontDescriptor.SymbolicTraits = []
            if inline.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if inline.contains(.emphasized) { traits.insert(.italic) }
            if !traits.isEmpty,
               let f = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits),
                              size: font.pointSize) {
                font = f
            }
            attr[run.range].font = font
        }

        // Block styling — heading sizes + fenced-code-block monospace.
        for run in attr.runs {
            guard let intent = run.presentationIntent else { continue }
            for component in intent.components {
                switch component.kind {
                case .header(let level):
                    let size: CGFloat = level <= 1 ? 22 : (level == 2 ? 18 : (level == 3 ? 16 : 14))
                    attr[run.range].font = NSFont.boldSystemFont(ofSize: size)
                case .codeBlock:
                    attr[run.range].font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                default:
                    break
                }
            }
        }

        // The parser carries block structure only as metadata with no newlines —
        // rebuild inserting a separator at each block boundary.
        let result = NSMutableAttributedString()
        var isFirst = true
        var lastIntent: PresentationIntent?
        for run in attr.runs {
            let intent = run.presentationIntent
            if !isFirst, lastIntent != intent {
                let sep = (isListItemIntent(intent) && isListItemIntent(lastIntent)) ? "\n" : "\n\n"
                result.append(NSAttributedString(string: sep, attributes: [.font: base]))
            }
            result.append(NSAttributedString(AttributedString(attr[run.range])))
            lastIntent = intent
            isFirst = false
        }
        return result
    }

    private static func isListItemIntent(_ intent: PresentationIntent?) -> Bool {
        guard let intent else { return false }
        return intent.components.contains { component in
            if case .listItem = component.kind { return true }
            return false
        }
    }

    // MARK: - Markdown → MediaWiki

    /// Convert Markdown source directly to MediaWiki markup — the Markdown
    /// counterpart of `Rich → Wiki markup`. Block structure (headings, list
    /// items) is handled line-by-line; inline spans (bold / italic / code /
    /// strikethrough / links) via ordered regex passes.
    static func markdownToWiki(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
                            .components(separatedBy: "\n")
        var out: [String] = []
        for line in lines {
            if let r = line.range(of: "^(#{1,6})\\s+", options: .regularExpression) {
                let level = min(6, line[line.startIndex..<r.upperBound].filter { $0 == "#" }.count)
                let eq = String(repeating: "=", count: max(1, level))
                out.append("\(eq) \(inlineMarkdownToWiki(String(line[r.upperBound...]))) \(eq)")
            } else if let r = line.range(of: "^\\s*[-*+]\\s+", options: .regularExpression) {
                out.append("* " + inlineMarkdownToWiki(String(line[r.upperBound...])))
            } else if let r = line.range(of: "^\\s*\\d+[.)]\\s+", options: .regularExpression) {
                out.append("# " + inlineMarkdownToWiki(String(line[r.upperBound...])))
            } else {
                out.append(inlineMarkdownToWiki(line))
            }
        }
        return out.joined(separator: "\n")
    }

    private static func inlineMarkdownToWiki(_ s: String) -> String {
        var o = s
        func rx(_ pattern: String, _ template: String) {
            o = o.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        rx("\\*\\*\\*(.+?)\\*\\*\\*", "'''''$1'''''")   // bold-italic
        rx("___(.+?)___",            "'''''$1'''''")
        rx("\\*\\*(.+?)\\*\\*",      "'''$1'''")        // bold
        rx("__(.+?)__",              "'''$1'''")
        rx("\\*(.+?)\\*",            "''$1''")          // italic (underscore form skipped → no snake_case mangling)
        rx("~~(.+?)~~",              "<s>$1</s>")       // strikethrough
        rx("`(.+?)`",                "<code>$1</code>") // inline code
        rx("\\[(.+?)\\]\\((.+?)\\)", "[$2 $1]")         // links
        return o
    }

    // MARK: - NSAttributedString → MediaWiki

    /// MediaWiki syntax (Wikipedia). Used by engine.rich_to_wiki and the
    /// Rich → Wiki markup built-in action.
    static func attributedStringToWiki(_ attr: NSAttributedString) -> String {
        guard attr.length > 0 else { return "" }
        var result = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            let substring = attr.attributedSubstring(from: range).string
            guard !substring.isEmpty else { return }

            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isMonospace = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            let size = font?.pointSize ?? 13
            let lineStart = result.hasSuffix("\n") || result.isEmpty

            let isHeading1 = size >= 22 && lineStart
            let isHeading2 = size >= 17 && size < 22 && isBold && lineStart
            let isHeading3 = size >= 14 && size < 17 && isBold && lineStart

            var segment = substring
            if let link = attrs[.link] as? URL {
                segment = "[\(link.absoluteString) \(segment)]"
            }
            if isMonospace { segment = "<code>\(segment)</code>" }
            if isBold && isItalic { segment = "'''''\(segment)'''''" }
            else if isBold && !isHeading1 && !isHeading2 && !isHeading3 { segment = "'''\(segment)'''" }
            else if isItalic { segment = "''\(segment)''" }

            if isHeading1 { segment = "= \(segment) =" }
            else if isHeading2 { segment = "== \(segment) ==" }
            else if isHeading3 { segment = "=== \(segment) ===" }

            result += segment
        }
        return result
    }

    // MARK: - NSAttributedString → HTML

    /// Uses the native NSAttributedString.data(documentAttributes: .html) API.
    static func attributedStringToHTML(_ attr: NSAttributedString) -> String? {
        guard let data = try? attr.data(from: NSRange(location: 0, length: attr.length),
                                        documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
}
