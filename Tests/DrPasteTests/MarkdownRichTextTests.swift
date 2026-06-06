//
//  MarkdownRichTextTests.swift
//  DrPasteTests
//
//  Regression: Markdown → Rich text dropped bold / italic / inline-code
//  styling. The parser stores those as `inlinePresentationIntent` metadata,
//  not real fonts, so the rendered/RTF output looked plain. The helper must
//  translate the intents into concrete font traits.
//

import XCTest
import AppKit
@testable import DrPaste

final class MarkdownRichTextTests: XCTestCase {

    private func render(_ md: String) -> NSAttributedString {
        RichTextHelpers.markdownToAttributedString(md) ?? NSAttributedString(string: "")
    }

    private func font(_ attr: NSAttributedString, at substring: String) -> NSFont? {
        let ns = attr.string as NSString
        let r = ns.range(of: substring)
        guard r.location != NSNotFound else { return nil }
        return attr.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
    }

    func testBoldItalicCodeBecomeRealFontTraits() {
        let attr = render("A line with **bold**, *italic*, and `code`.")

        let boldTraits = font(attr, at: "bold")?.fontDescriptor.symbolicTraits
        XCTAssertEqual(boldTraits?.contains(.bold), true, "bold run lost its bold trait")

        let italicTraits = font(attr, at: "italic")?.fontDescriptor.symbolicTraits
        XCTAssertEqual(italicTraits?.contains(.italic), true, "italic run lost its italic trait")

        let codeTraits = font(attr, at: "code")?.fontDescriptor.symbolicTraits
        XCTAssertEqual(codeTraits?.contains(.monoSpace), true, "code run is not monospaced")
    }

    func testPlainTextHasNoBoldItalic() {
        let attr = render("Just normal words here.")
        let traits = font(attr, at: "normal")?.fontDescriptor.symbolicTraits
        XCTAssertEqual(traits?.contains(.bold), false)
        XCTAssertEqual(traits?.contains(.italic), false)
    }

    func testHeadingsRenderAsLargeBoldNotLiteral() {
        let attr = render("# Title\n\nSome body text here.")
        // The "#" marker must be gone (block rendered, not literal).
        XCTAssertFalse(attr.string.contains("#"), "heading marker left literal: \(attr.string)")
        let title = font(attr, at: "Title")
        XCTAssertEqual(title?.fontDescriptor.symbolicTraits.contains(.bold), true, "heading not bold")
        XCTAssertGreaterThan(title?.pointSize ?? 0, 16, "heading not enlarged")
        // Body stays at the base size.
        let body = font(attr, at: "body")
        XCTAssertEqual(body?.pointSize, 13)
    }

    func testFencedCodeBlockIsMonospacedNoFence() {
        let attr = render("text\n\n```swift\nlet x = 42\n```")
        XCTAssertFalse(attr.string.contains("```"), "code fence left literal: \(attr.string)")
        XCTAssertFalse(attr.string.contains("swift"), "language hint leaked into text: \(attr.string)")
        XCTAssertEqual(font(attr, at: "let x")?.fontDescriptor.symbolicTraits.contains(.monoSpace), true)
    }

    func testLinkSurvives() {
        let attr = render("Followed by a [linked phrase](https://example.com).")
        let ns = attr.string as NSString
        let r = ns.range(of: "linked phrase")
        XCTAssertNotEqual(r.location, NSNotFound)
        let link = attr.attribute(.link, at: r.location, effectiveRange: nil)
        XCTAssertNotNil(link, "markdown link did not produce a .link attribute")
    }
}
