//
//  PasteAsTextApplicabilityTests.swift
//  DrPasteTests
//
//  "Plain text" (builtin.rich.strip_formatting) is the single universal cleaner:
//  it applies to every text-bearing kind (incl. Markdown) and folds rich-text
//  formatting, Markdown markup, AND Unicode pseudo-font styling down to plain.
//

import XCTest
@testable import DrPaste

final class PasteAsTextApplicabilityTests: XCTestCase {

    private func item(_ kind: SemanticKind, _ text: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: kind, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: text,
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [])
    }

    func testAppliesToRichAndMarkdownAlways() {
        // #A78 — rich text & markdown always have something to strip.
        let action = PasteAsTextAction()
        for kind in [SemanticKind.richText, .markdown] {
            let i = item(kind, "some text")
            XCTAssertTrue(action.isApplicable(item: i, context: ContextDetector.detect(i)),
                          "Plain text should apply to \(kind)")
        }
    }

    func testGatedOnPlainTextWithoutStyling() {
        // #A78 — on ordinary plain text there's nothing to strip → no chip.
        let action = PasteAsTextAction()
        let plain = item(.text, "the meeting is tomorrow afternoon")
        XCTAssertFalse(action.isApplicable(item: plain, context: ContextDetector.detect(plain)),
                       "Plain text must NOT surface on already-plain prose")
    }

    func testAppliesToPlainTextCarryingStyledUnicode() {
        // … but DOES surface when there's fancy Unicode to fold.
        let action = PasteAsTextAction()
        let fancy = item(.text, "𝐇𝐞𝐥𝐥𝐨 there")
        XCTAssertTrue(action.isApplicable(item: fancy, context: ContextDetector.detect(fancy)),
                      "Plain text should surface on styled-Unicode plain text")
    }

    func testStripsMarkdownMarkupOnMarkdownClip() async {
        let action = PasteAsTextAction()
        let md = item(.markdown, "# Title\n\nSome **bold** and `code` here")
        let outcome = await action.apply(item: md, context: ContextDetector.detect(md))
        guard case .preview(let out) = outcome else { return XCTFail("expected preview") }
        let text = out.previewText ?? ""
        XCTAssertFalse(text.contains("**"), "markdown markup not stripped: \(text)")
        XCTAssertFalse(text.contains("# "), "heading marker not stripped: \(text)")
        XCTAssertTrue(text.contains("Title"))
        XCTAssertTrue(text.contains("bold"))
    }

    func testDenormalizesUnicodeFancyFont() async {
        let action = PasteAsTextAction()
        // "𝐇𝐞𝐥𝐥𝐨" (mathematical bold) → "Hello"
        let fancy = item(.text, "𝐇𝐞𝐥𝐥𝐨 𝟏𝟐𝟑")
        let outcome = await action.apply(item: fancy, context: ContextDetector.detect(fancy))
        guard case .preview(let out) = outcome else { return XCTFail("expected preview") }
        XCTAssertEqual(out.previewText, "Hello 123")
    }
}
