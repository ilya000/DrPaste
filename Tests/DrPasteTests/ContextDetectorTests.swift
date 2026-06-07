//
//  ContextDetectorTests.swift
//  DrPasteTests
//
//  ContentContext flag composition. Tests build minimal ClipboardItem stubs
//  rather than going through ClipboardWatcher / NSPasteboard.
//

import XCTest
@testable import DrPaste

final class ContextDetectorTests: XCTestCase {

    /// Minimal item factory — semantic + preview text only, every other
    /// field defaults to something inert.
    private func item(_ semantic: SemanticKind, text: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            semantic: semantic,
            createdAt: Date(),
            representations: [:],
            typesOrdered: [],
            previewText: text,
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: nil,
            sourceWindowTitle: nil,
            tags: []
        )
    }

    func testPlainTextContext() {
        let ctx = ContextDetector.detect(item(.text, text: "hello"))
        XCTAssertTrue(ctx.contains(.plain))
        XCTAssertFalse(ctx.contains(.multiline))
        XCTAssertFalse(ctx.contains(.mixedScript))
    }

    func testRichTextHasPlainFlag() {
        // Rich text items also surface .plain so plain-text-style actions
        // (UPPERCASE etc.) can run against the underlying preview text.
        let ctx = ContextDetector.detect(item(.richText, text: "Hello"))
        XCTAssertTrue(ctx.contains(.richText))
        XCTAssertTrue(ctx.contains(.plain))
    }

    func testMultilineDetected() {
        let ctx = ContextDetector.detect(item(.text, text: "line one\nline two"))
        XCTAssertTrue(ctx.contains(.multiline))
    }

    func testMixedScriptDetected() {
        let ctx = ContextDetector.detect(item(.text, text: "Hello мир"))
        XCTAssertTrue(ctx.contains(.mixedScript))
    }

    func testNonMixedScript() {
        let ctx = ContextDetector.detect(item(.text, text: "hello world"))
        XCTAssertFalse(ctx.contains(.mixedScript))
    }

    func testQrEligibleShortText() {
        let ctx = ContextDetector.detect(item(.text, text: "https://example.com"))
        XCTAssertTrue(ctx.contains(.qrEligible))
    }

    func testQrIneligibleLongText() {
        let ctx = ContextDetector.detect(item(.text, text: String(repeating: "x", count: 3000)))
        XCTAssertFalse(ctx.contains(.qrEligible))
    }

    func testImageNoPlainFlag() {
        // Image items do NOT have .plain — actions that gate on plain text
        // must not surface for raw image clipboard entries.
        let ctx = ContextDetector.detect(item(.image))
        XCTAssertTrue(ctx.contains(.image))
        XCTAssertFalse(ctx.contains(.plain))
    }

    func testJSONFlag() {
        let ctx = ContextDetector.detect(item(.json, text: "{\"a\":1}"))
        XCTAssertTrue(ctx.contains(.json))
        XCTAssertTrue(ctx.contains(.plain))
    }

    func testFilesFlag() {
        let ctx = ContextDetector.detect(item(.files, text: "/tmp/a.txt"))
        XCTAssertTrue(ctx.contains(.files))
        XCTAssertFalse(ctx.contains(.plain))
    }

    // MARK: #A75 cheap content traits

    func testContainsEmails() {
        let yes = ContextDetector.detect(item(.text, text: "ping me at a.b+x@Example.co.uk please"))
        XCTAssertTrue(yes.contains(.containsEmails))
        let no = ContextDetector.detect(item(.text, text: "no address here, just a@ and @b"))
        XCTAssertFalse(no.contains(.containsEmails))
    }

    func testContainsURLs() {
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "see https://x.com/y now")).contains(.containsURLs))
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "go to www.x.com")).contains(.containsURLs))
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "no link here")).contains(.containsURLs))
    }

    func testContainsCyrillicAndLatin() {
        let cyr = ContextDetector.detect(item(.text, text: "привет"))
        XCTAssertTrue(cyr.contains(.containsCyrillic))
        XCTAssertFalse(cyr.contains(.containsLatin))
        let lat = ContextDetector.detect(item(.text, text: "hello"))
        XCTAssertTrue(lat.contains(.containsLatin))
        XCTAssertFalse(lat.contains(.containsCyrillic))
    }

    func testUppercaseHeavy() {
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "PLEASE STOP SHOUTING")).contains(.uppercaseHeavy))
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "Normal sentence case here")).contains(.uppercaseHeavy))
        // Short acronym must not trip it.
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "FBI")).contains(.uppercaseHeavy))
    }

    func testLowercaseHeavy() {
        // All-lowercase typing (no capitals at all) → flagged.
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "this is all lowercase text here")).contains(.lowercaseHeavy))
        // A single sentence-start capital clears it (normal prose).
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "This is normal sentence text")).contains(.lowercaseHeavy))
        // Too short to judge.
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "hi")).contains(.lowercaseHeavy))
    }

    func testMessySpacing() {
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "a\tb")).contains(.messySpacing))
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "a  b")).contains(.messySpacing))
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "a b c")).contains(.messySpacing))
    }

    func testWrappedLines() {
        let pdf = "The quick brown fox jumps over\nthe lazy dog and then keeps\nrunning down the road forever"
        XCTAssertTrue(ContextDetector.detect(item(.text, text: pdf)).contains(.wrappedLines))
        let prose = "First sentence.\nSecond sentence.\nThird sentence."
        XCTAssertFalse(ContextDetector.detect(item(.text, text: prose)).contains(.wrappedLines))
    }

    // S8 (Codex/review): the script scan must count only real letters — not
    // ASCII symbols `[ \ ] ^ _ \`` that share the old 0x41…0x7A range.
    func testContainsLatinIgnoresAsciiSymbols() {
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "___")).contains(.containsLatin))
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "[]^_`")).contains(.containsLatin))
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "a_b")).contains(.containsLatin)) // real letters present
        // Cyrillic + only-symbols must NOT be flagged mixedScript.
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "привет ___")).contains(.mixedScript))
    }

    func testContainsHTMLMarkup() {
        // Real HTML → flagged.
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "<p>hello</p>")).contains(.containsHTMLMarkup))
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "a <a href=\"x\">link</a> b")).contains(.containsHTMLMarkup))
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "line<br/>break")).contains(.containsHTMLMarkup))
        // Angle brackets that are NOT HTML → must NOT be flagged (so Strip HTML
        // tags never mangles math / generics).
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "5 < 10 and 20 > 15")).contains(.containsHTMLMarkup))
        XCTAssertFalse(ContextDetector.detect(item(.code, text: "List<String> items")).contains(.containsHTMLMarkup))
        XCTAssertFalse(ContextDetector.detect(item(.code, text: "vector<int> v;")).contains(.containsHTMLMarkup))
    }

    func testFromChatSource() {
        func src(_ app: String?, _ win: String? = nil) -> ClipboardItem {
            ClipboardItem(id: UUID(), semantic: .text, createdAt: Date(),
                          representations: [:], typesOrdered: [], previewText: "hi",
                          previewImageRel: nil, sourceBundleID: nil, sourceAppName: app,
                          sourceWindowTitle: win, tags: [])
        }
        XCTAssertTrue(ContextDetector.detect(src("Slack")).contains(.fromChat))
        XCTAssertTrue(ContextDetector.detect(src("Telegram")).contains(.fromChat))
        XCTAssertTrue(ContextDetector.detect(src("Safari", "WhatsApp")).contains(.fromChat))
        XCTAssertFalse(ContextDetector.detect(src("Xcode", "main.swift")).contains(.fromChat))
    }

    func testHasTrackingParams() {
        XCTAssertTrue(ContextDetector.detect(item(.url, text: "https://x.com/a?utm_source=nl&id=1")).contains(.hasTrackingParams))
        XCTAssertTrue(ContextDetector.detect(item(.url, text: "https://x.com/a?fbclid=abc")).contains(.hasTrackingParams))
        XCTAssertFalse(ContextDetector.detect(item(.url, text: "https://x.com/a?id=1&page=2")).contains(.hasTrackingParams))
    }

    func testEmptyAndWhitespaceText() {
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "")).contains(.qrEligible))
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "   \n  ")).contains(.multiline))
        // No crash, no spurious flags.
        let ctx = ContextDetector.detect(item(.text, text: ""))
        XCTAssertTrue(ctx.contains(.plain))
        XCTAssertFalse(ctx.contains(.containsLatin))
    }

    func testContainsEmailsCaseInsensitiveAndTLD() {
        XCTAssertTrue(ContextDetector.detect(item(.text, text: "WRITE TO ME@EXAMPLE.COM")).contains(.containsEmails))
        XCTAssertFalse(ContextDetector.detect(item(.text, text: "handle @user or a@b")).contains(.containsEmails))
    }
}
