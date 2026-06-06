//
//  MarkdownToWikiTests.swift
//  DrPasteTests
//
//  Markdown → MediaWiki conversion (the Markdown counterpart of Rich → Wiki).
//

import XCTest
@testable import DrPaste

final class MarkdownToWikiTests: XCTestCase {

    private func wiki(_ md: String) -> String { RichTextHelpers.markdownToWiki(md) }

    func testHeadings() {
        XCTAssertEqual(wiki("# Title"), "= Title =")
        XCTAssertEqual(wiki("## Sub"), "== Sub ==")
        XCTAssertEqual(wiki("### Deep"), "=== Deep ===")
    }

    func testInlineStyles() {
        XCTAssertEqual(wiki("**bold**"), "'''bold'''")
        XCTAssertEqual(wiki("*italic*"), "''italic''")
        XCTAssertEqual(wiki("***bi***"), "'''''bi'''''")
        XCTAssertEqual(wiki("`code`"), "<code>code</code>")
        XCTAssertEqual(wiki("~~gone~~"), "<s>gone</s>")
    }

    func testLinksAndLists() {
        XCTAssertEqual(wiki("[text](https://x.com)"), "[https://x.com text]")
        XCTAssertEqual(wiki("- item"), "* item")
        XCTAssertEqual(wiki("1. first"), "# first")
    }

    func testSnakeCaseNotMangled() {
        // Underscore italic is intentionally unsupported so identifiers survive.
        XCTAssertEqual(wiki("call foo_bar_baz here"), "call foo_bar_baz here")
    }

    func testMixedDocument() {
        let out = wiki("## Notes\nSome **bold** and a [link](https://x.com).\n- one\n- two")
        XCTAssertTrue(out.contains("== Notes =="))
        XCTAssertTrue(out.contains("'''bold'''"))
        XCTAssertTrue(out.contains("[https://x.com link]"))
        XCTAssertTrue(out.contains("* one"))
    }
}
