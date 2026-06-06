//
//  ClipboardItemEmptyTests.swift
//  DrPasteTests
//
//  Regression: whitespace-only TEXT clips were leaking back into history as
//  noise rows. `isEffectivelyEmpty` used to treat any non-empty
//  `representations` map as "meaningful", but a plain-text clip carries a text
//  blob even when that blob holds nothing but whitespace. The guard must defer
//  text-only clips to their preview-text content while keeping non-text
//  payloads (image / files / RTF / HTML / URL) meaningful on their own.
//

import XCTest
@testable import DrPaste

final class ClipboardItemEmptyTests: XCTestCase {

    private func item(reps: [String: String],
                      text: String?,
                      previewImageRel: String? = nil,
                      semantic: SemanticKind = .text) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), semantic: semantic, createdAt: Date(),
            representations: reps, typesOrdered: Array(reps.keys),
            previewText: text, previewImageRel: previewImageRel,
            sourceBundleID: nil, sourceAppName: nil,
            sourceWindowTitle: nil, tags: []
        )
    }

    /// The exact reported shape: text reps present, preview text whitespace.
    func testWhitespaceTextWithTextRepsIsEmpty() {
        let it = item(reps: ["NSStringPboardType": "a", "public.utf8-plain-text": "b"],
                      text: "   \n\t ")
        XCTAssertTrue(it.isEffectivelyEmpty)
    }

    func testEmptyTextWithTextRepsIsEmpty() {
        let it = item(reps: ["public.utf8-plain-text": "a"], text: "")
        XCTAssertTrue(it.isEffectivelyEmpty)
    }

    func testNilTextWithOnlyTextRepsIsEmpty() {
        let it = item(reps: ["public.utf8-plain-text": "a"], text: nil)
        XCTAssertTrue(it.isEffectivelyEmpty)
    }

    func testRealTextIsNotEmpty() {
        let it = item(reps: ["public.utf8-plain-text": "a"], text: "hello")
        XCTAssertFalse(it.isEffectivelyEmpty)
    }

    /// URL clips carry their address as preview text → never dropped, even
    /// though their representations are text-family.
    func testURLClipIsNotEmpty() {
        let it = item(reps: ["public.utf8-plain-text": "a", "NSStringPboardType": "b"],
                      text: "https://www.dropbox.com/scl/fi/e7lq0de16rsc4utqeha")
        XCTAssertFalse(it.isEffectivelyEmpty)
    }

    /// A non-text representation (image / RTF / files / …) is meaningful on its
    /// own even with no preview text — must NOT be treated as empty.
    func testNonTextRepWithNoTextIsNotEmpty() {
        XCTAssertFalse(item(reps: ["public.png": "a"], text: nil).isEffectivelyEmpty)
        XCTAssertFalse(item(reps: ["public.rtf": "a"], text: "  ").isEffectivelyEmpty)
        XCTAssertFalse(item(reps: ["public.file-url": "a"], text: "").isEffectivelyEmpty)
    }

    func testPreviewImageIsNotEmpty() {
        let it = item(reps: [:], text: nil, previewImageRel: "img.png")
        XCTAssertFalse(it.isEffectivelyEmpty)
    }

    func testNoRepsNoTextIsEmpty() {
        XCTAssertTrue(item(reps: [:], text: nil).isEffectivelyEmpty)
        XCTAssertTrue(item(reps: [:], text: "   ").isEffectivelyEmpty)
    }
}
