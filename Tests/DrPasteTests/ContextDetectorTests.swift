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
}
