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

    // MARK: - Load a rich clip's attributed string

    /// Loads the NSAttributedString for a rich clip from its stored
    /// representations, trying every rich format the app may have written.
    ///
    /// CRITICAL (#A78 / Codex #3): when a rich clip carries inline attachments
    /// (rich-OCR output, files-as-icons, the append accumulator), the app
    /// serialises it as **flat-RTFD** (`com.apple.flat-rtfd`), NOT `public.rtf`
    /// — RTF silently drops attachments. Rich → Markdown / HTML / Wiki / Unicode
    /// used to read only `public.rtf`, so on those clips they fell back to plain
    /// text and lost all formatting / attachments. Try RTFD first, then RTF,
    /// then HTML.
    static func loadAttributed(from item: ClipboardItem) -> NSAttributedString? {
        func data(_ key: String) -> Data? {
            guard let rel = item.representations[key] else { return nil }
            return try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel))
        }
        if let d = data("com.apple.flat-rtfd") ?? data("public.rtfd"),
           let attr = try? NSAttributedString(
               data: d, options: [.documentType: NSAttributedString.DocumentType.rtfd],
               documentAttributes: nil) {
            return attr
        }
        if let d = data("public.rtf"),
           let attr = try? NSAttributedString(
               data: d, options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil) {
            return attr
        }
        if let d = data("public.html"),
           let attr = try? NSAttributedString(
               data: d, options: [.documentType: NSAttributedString.DocumentType.html,
                                  .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil) {
            return attr
        }
        return nil
    }

    // MARK: - NSAttributedString → Markdown

    /// Coarse attributed → Markdown conversion. Covers bold, italic, monospace
    /// (inline code), headings inferred from font size, and links. Does not
    /// cover tables, blockquotes, or nested lists. Sufficient for round-tripping
    /// AI transformations through Markdown.
    /// `escapeLiterals` (#A78 / Codex #10): when true, literal markdown
    /// metacharacters in the TEXT content (`\ ` `` ` `` `* _ [ ]`) are
    /// backslash-escaped so a value like `5 * 3` or `my_var` doesn't render as
    /// emphasis. Used by the explicit Rich → Markdown EXPORT action. Left OFF
    /// for the AI round-trip path (it would add escaping the model has to
    /// preserve and reverse).
    static func attributedStringToMarkdown(_ attr: NSAttributedString,
                                           escapeLiterals: Bool = false) -> String? {
        guard attr.length > 0 else { return "" }
        var result = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            // Embedded image → a self-contained data-URI image, exactly like the
            // HTML export embeds base64. Most Markdown renderers (Obsidian,
            // Typora, VS Code preview, …) display these. Skip the U+FFFC
            // attachment placeholder char that would otherwise leak through.
            if let attachment = attrs[.attachment] as? NSTextAttachment {
                if let png = attachmentPNG(attachment) {
                    result += "![image](data:image/png;base64,\(png.base64EncodedString()))"
                }
                return
            }
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

            // Escape literal metachars in plain text runs (not inside a code
            // span — markdown doesn't interpret markup there).
            var segment = (escapeLiterals && !isMonospace) ? escapeMarkdownLiterals(substring) : substring
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
    /// `escapeLiterals` (Codex #10): when true, the wiki link / template
    /// metacharacters `[ ] |` in the TEXT content are replaced with HTML
    /// entities so literal brackets / pipes don't create spurious links or
    /// break table cells. Single quotes are left alone — only runs of 2+ `'`
    /// are wiki markup and apostrophes are far too common in prose to escape.
    static func attributedStringToWiki(_ attr: NSAttributedString,
                                       escapeLiterals: Bool = false) -> String {
        guard attr.length > 0 else { return "" }
        var result = ""
        var imageIndex = 0
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            // Embedded image → a `[[File:…]]` reference. MediaWiki cannot inline
            // binary image data (no data-URI support); images live as uploaded
            // files referenced by name. We can't upload, so emit a placeholder
            // reference the user can point at their uploaded file — better than
            // silently dropping the image. (Skips the U+FFFC placeholder char.)
            if attrs[.attachment] is NSTextAttachment {
                imageIndex += 1
                result += "[[File:embedded-image-\(imageIndex).png|thumb]]"
                return
            }
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

            var segment = (escapeLiterals && !isMonospace) ? escapeWikiLiterals(substring) : substring
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

    /// PNG bytes for an image text-attachment (re-encoded so any source format —
    /// the FileWrapper contents, `.image`, or `.contents` — becomes uniform PNG).
    private static func attachmentPNG(_ attachment: NSTextAttachment) -> Data? {
        let image: NSImage?
        if let data = attachment.fileWrapper?.regularFileContents {
            image = NSImage(data: data)
        } else if let img = attachment.image {
            image = img
        } else if let data = attachment.contents {
            image = NSImage(data: data)
        } else {
            image = nil
        }
        guard let image, let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        return bmp.representation(using: .png, properties: [:])
    }

    /// Backslash-escape literal markdown metacharacters in a text run.
    private static func escapeMarkdownLiterals(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if ch == "\\" || ch == "`" || ch == "*" || ch == "_" || ch == "[" || ch == "]" {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    /// Entity-escape wiki link / table metacharacters in a text run.
    private static func escapeWikiLiterals(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "&#91;")
         .replacingOccurrences(of: "]", with: "&#93;")
         .replacingOccurrences(of: "|", with: "&#124;")
    }

    // MARK: - NSAttributedString → HTML

    /// Uses the native NSAttributedString.data(documentAttributes: .html) API.
    static func attributedStringToHTML(_ attr: NSAttributedString) -> String? {
        guard let data = try? attr.data(from: NSRange(location: 0, length: attr.length),
                                        documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return htmlBodyFragment(from: str)
    }

    /// Reduces Cocoa's full-document HTML export to just the content fragment.
    ///
    /// `NSAttributedString`'s HTML writer emits a whole document — DOCTYPE,
    /// `<head>` with a `<meta generator="Cocoa HTML Writer">` and an
    /// autogenerated `<style>` block of `p.p1 { font: 13px 'Helvetica Neue' }`
    /// rules, then `<body>`. You almost never paste a whole document; you paste
    /// a snippet INTO existing HTML, so all that chrome is noise (and the
    /// hardcoded Helvetica sizes actively fight the host page's CSS).
    ///
    /// Return only the inner `<body>` content, and drop the autogenerated
    /// `class="p1"` / `class="s1"` attributes that referenced the now-removed
    /// `<style>`. The structural tags (`<p>`, `<b>`, `<i>`, `<a href>`) carry
    /// the meaning and survive.
    private static func htmlBodyFragment(from full: String) -> String {
        var s = full
        if let open = s.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]),
           let close = s.range(of: "</body>", options: [.caseInsensitive, .backwards]),
           open.upperBound <= close.lowerBound {
            s = String(s[open.upperBound..<close.lowerBound])
        }
        // Strip Cocoa's style-class refs (class="p1", class="s3", class="Apple…").
        s = s.replacingOccurrences(of: #"\s+class="(?:p|s|Apple)[^"]*""#,
                                   with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
