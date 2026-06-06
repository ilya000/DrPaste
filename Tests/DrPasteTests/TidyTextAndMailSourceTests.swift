//
//  TidyTextAndMailSourceTests.swift
//  DrPasteTests
//
//  Covers the merged "Tidy text" cleanup engine and the mail-source heuristic
//  that lets email actions surface when a clip comes from a mail app.
//

import XCTest
@testable import DrPaste

final class TidyTextAndMailSourceTests: XCTestCase {

    private func tidy(_ s: String) -> String {
        (try? TransformationRuntime.apply(engine: .trim, input: s, params: [:])) ?? s
    }

    func testTrimsAndNormalisesWhitespace() {
        let out = tidy("  hello   world  \n\n\n\nfoo\tbar  ")
        XCTAssertFalse(out.contains("  "), "multi-spaces not collapsed: \(out)")
        XCTAssertFalse(out.hasPrefix(" "))
        XCTAssertFalse(out.hasSuffix(" "))
        XCTAssertFalse(out.contains("\n\n\n"), "blank-line runs not collapsed")
        XCTAssertTrue(out.contains("foo bar"))
    }

    func testReflowsPdfWrappedLines() {
        let input = """
        The quick brown fox jumps over the lazy dog and then it keeps
        running down the long road forever and ever without ever stopping.
        A new short line.
        """
        let out = tidy(input)
        XCTAssertTrue(out.contains("keeps running"), "wrapped lines not rejoined: \(out)")
        XCTAssertTrue(out.contains("A new short line."), "unrelated line lost: \(out)")
    }

    func testPreservesShortListLines() {
        let out = tidy("milk\neggs\nbread\nbutter")
        XCTAssertEqual(out, "milk\neggs\nbread\nbutter", "list items wrongly joined: \(out)")
    }

    // MARK: mail source

    private func item(app: String? = nil, window: String? = nil, bundle: String? = nil) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: .text, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: "some body text",
                      previewImageRel: nil, sourceBundleID: bundle, sourceAppName: app,
                      sourceWindowTitle: window, tags: [])
    }

    func testMailSourceByAppName() {
        XCTAssertTrue(ContextDetector.detect(item(app: "Mail")).contains(.fromMailApp))
        XCTAssertTrue(ContextDetector.detect(item(app: "Microsoft Outlook")).contains(.fromMailApp))
    }

    func testMailSourceByWindowTitle() {
        XCTAssertTrue(ContextDetector.detect(item(app: "Safari", window: "Inbox (3) - me@gmail.com - Gmail")).contains(.fromMailApp))
    }

    func testNonMailSourceIsNotFlagged() {
        XCTAssertFalse(ContextDetector.detect(item(app: "Xcode", window: "main.swift")).contains(.fromMailApp))
        XCTAssertFalse(ContextDetector.detect(item()).contains(.fromMailApp))
    }
}
