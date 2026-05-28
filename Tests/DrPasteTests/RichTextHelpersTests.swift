//
//  RichTextHelpersTests.swift
//  DrPasteTests
//
//  Pure conversion paths between NSAttributedString and the text-output
//  formats (Markdown, Wiki, HTML). Focused on bold / italic / link / heading
//  emission and on the markdown-parse round trip.
//

import XCTest
import AppKit
@testable import DrPaste

final class RichTextHelpersTests: XCTestCase {

    // MARK: - Helpers

    private func bold(_ s: String) -> NSAttributedString {
        let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13),
                                                 toHaveTrait: .boldFontMask)
        return NSAttributedString(string: s, attributes: [.font: font])
    }

    private func italic(_ s: String) -> NSAttributedString {
        let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13),
                                                 toHaveTrait: .italicFontMask)
        return NSAttributedString(string: s, attributes: [.font: font])
    }

    private func plain(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13)])
    }

    private func link(_ s: String, to url: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .link: URL(string: url)!,
            .font: NSFont.systemFont(ofSize: 13)
        ])
    }

    // MARK: - attributedStringToMarkdown

    func testMarkdownBoldRoundTrip() {
        let attr = NSMutableAttributedString()
        attr.append(plain("hello "))
        attr.append(bold("world"))
        let md = RichTextHelpers.attributedStringToMarkdown(attr)
        XCTAssertEqual(md, "hello **world**")
    }

    func testMarkdownItalicRoundTrip() {
        let attr = NSMutableAttributedString()
        attr.append(plain("see "))
        attr.append(italic("italic"))
        let md = RichTextHelpers.attributedStringToMarkdown(attr)
        XCTAssertEqual(md, "see *italic*")
    }

    func testMarkdownLinkEmission() {
        let md = RichTextHelpers.attributedStringToMarkdown(link("here", to: "https://x.com"))
        XCTAssertEqual(md, "[here](https://x.com)")
    }

    func testMarkdownHandlesEmpty() {
        XCTAssertEqual(RichTextHelpers.attributedStringToMarkdown(NSAttributedString(string: "")), "")
    }

    func testMarkdownToAttributedNonNil() {
        // Parses successfully on macOS 12+. Resulting attributed string should be non-empty.
        let attr = RichTextHelpers.markdownToAttributedString("**hello** *world*")
        XCTAssertNotNil(attr)
        XCTAssertTrue((attr?.string.contains("hello")) ?? false)
        XCTAssertTrue((attr?.string.contains("world")) ?? false)
    }

    // MARK: - attributedStringToWiki

    func testWikiBold() {
        let attr = NSMutableAttributedString()
        attr.append(plain("see "))
        attr.append(bold("term"))
        let wiki = RichTextHelpers.attributedStringToWiki(attr)
        XCTAssertEqual(wiki, "see '''term'''")
    }

    func testWikiItalic() {
        let attr = NSMutableAttributedString()
        attr.append(plain("see "))
        attr.append(italic("term"))
        let wiki = RichTextHelpers.attributedStringToWiki(attr)
        XCTAssertEqual(wiki, "see ''term''")
    }

    func testWikiLink() {
        let wiki = RichTextHelpers.attributedStringToWiki(link("Example", to: "https://example.com"))
        XCTAssertEqual(wiki, "[https://example.com Example]")
    }

    func testWikiHandlesEmpty() {
        XCTAssertEqual(RichTextHelpers.attributedStringToWiki(NSAttributedString(string: "")), "")
    }

    // MARK: - attributedStringToHTML

    func testHTMLContainsBoldTag() {
        let attr = NSMutableAttributedString()
        attr.append(plain("see "))
        attr.append(bold("term"))
        guard let html = RichTextHelpers.attributedStringToHTML(attr) else {
            return XCTFail("HTML conversion returned nil")
        }
        XCTAssertTrue(html.contains("term"))
        // Most Apple HTML emission tags bold via inline styling or <b> / <strong>.
        XCTAssertTrue(html.lowercased().contains("bold")
                      || html.contains("<b>") || html.contains("<strong"),
                      "Expected the HTML to encode bold semantics, got:\n\(html)")
    }
}
