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
}
