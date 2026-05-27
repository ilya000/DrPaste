//
//  RichTextHelpers.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Конверторы между NSAttributedString и Markdown / Wiki markup (правки #9 + #10).
//  Используются для MD round-trip в AI rich-preserving actions и для Wiki export.
//

import Foundation
import AppKit

enum RichTextHelpers {

    // MARK: - NSAttributedString → Markdown

    /// Грубая конверсия attributed → markdown.
    /// Покрывает: bold, italic, monospace (inline code), headings по font-size, links.
    /// Не покрывает: tables, blockquotes, вложенные lists. Достаточно для round-trip
    /// AI transformations через MD.
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

            // Heading detection — крупный bold в начале line
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

    /// Использует native `NSAttributedString(markdown:)` (macOS 12+).
    /// Возвращает nil если parse failed.
    static func markdownToAttributedString(_ markdown: String) -> NSAttributedString? {
        // На macOS 12+ есть init(markdown:) для AttributedString — конвертируем в NSAttributedString.
        if let attr = try? NSAttributedString(markdown: markdown,
                                              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return nil
    }

    // MARK: - NSAttributedString → MediaWiki

    /// MediaWiki синтаксис (Wikipedia). Используется в engine.rich_to_wiki / preset
    /// Rich → Wiki markup.
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

    /// Используется native API NSAttributedString.data(documentAttributes: .html).
    static func attributedStringToHTML(_ attr: NSAttributedString) -> String? {
        guard let data = try? attr.data(from: NSRange(location: 0, length: attr.length),
                                        documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
}
