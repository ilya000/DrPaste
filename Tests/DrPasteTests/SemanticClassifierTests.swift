//
//  SemanticClassifierTests.swift
//  DrPasteTests
//
//  classifyText() covers the cheap string-pattern path; classify(types:)
//  needs a real NSPasteboard, which is awkward to mock — covered indirectly
//  by HUD-level integration in actual app runs.
//

import XCTest
@testable import DrPaste

final class SemanticClassifierTests: XCTestCase {

    func testEmptyStringIsText() {
        XCTAssertEqual(SemanticClassifier.classifyText(""), .text)
    }

    func testURLDetected() {
        XCTAssertEqual(SemanticClassifier.classifyText("https://example.com/path"), .url)
        XCTAssertEqual(SemanticClassifier.classifyText("http://example.org"), .url)
    }

    func testEmailDetected() {
        XCTAssertEqual(SemanticClassifier.classifyText("hello@example.com"), .email)
    }

    func testJSONObjectDetected() {
        XCTAssertEqual(SemanticClassifier.classifyText("{\"a\":1}"), .json)
    }

    func testJSONArrayDetected() {
        XCTAssertEqual(SemanticClassifier.classifyText("[1,2,3]"), .json)
    }

    func testMalformedJSONFallsThrough() {
        // Not parseable as JSON; falls through to other classifiers and ends as text.
        XCTAssertNotEqual(SemanticClassifier.classifyText("{not valid"), .json)
    }

    func testMarkdownDetected() {
        XCTAssertEqual(SemanticClassifier.classifyText("# Heading\nBody text\n## Sub"), .markdown)
        XCTAssertEqual(SemanticClassifier.classifyText("- item one\n- item two"), .markdown)
    }

    func testCodeDetected() {
        XCTAssertEqual(SemanticClassifier.classifyText("func greet() { return 42; }"), .code)
        XCTAssertEqual(SemanticClassifier.classifyText("const x = 1;\nlet y = 2;"), .code)
    }

    func testTableTSVDetected() {
        let tsv = "name\tage\tcity\nAnna\t30\tMadrid\nCarlos\t42\tBarcelona"
        XCTAssertEqual(SemanticClassifier.classifyText(tsv), .table)
    }

    func testTableCSVDetected() {
        let csv = "a,b,c\n1,2,3\n4,5,6"
        XCTAssertEqual(SemanticClassifier.classifyText(csv), .table)
    }

    func testPlainTextFallback() {
        XCTAssertEqual(SemanticClassifier.classifyText("Just a regular sentence."), .text)
    }
}
