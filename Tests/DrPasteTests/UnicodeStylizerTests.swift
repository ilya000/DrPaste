//
//  UnicodeStylizerTests.swift
//  DrPasteTests
//
//  Regression tests for pseudo-font styling and reverse normalization.
//

import XCTest
@testable import DrPaste

final class UnicodeStylizerTests: XCTestCase {

    func testPlainNormalizesMathBoldWithoutSecondPassCorruption() {
        let input = "𝐓𝐡𝐞 𝐪𝐮𝐢𝐜𝐤 𝐛𝐫𝐨𝐰𝐧 𝐟𝐨𝐱"
        let out = UnicodeStylizer.apply(to: input, style: .plain)
        XCTAssertEqual(out, "The quick brown fox")
    }

    func testPlainReversesFullwidthAndCircledForms() {
        XCTAssertEqual(UnicodeStylizer.apply(to: "Ｈｅｌｌｏ １２３", style: .plain), "Hello 123")
        XCTAssertEqual(UnicodeStylizer.apply(to: "Ⓗⓔⓛⓛⓞ", style: .plain), "Hello")
    }

    func testMarkdownAwareAppliesInlineStylesAndDropsMarkup() {
        let input = "**bold** *italic* `code` ~~strike~~"
        let out = UnicodeStylizer.applyMarkdown(to: input)

        XCTAssertTrue(out.contains("𝐛𝐨𝐥𝐝"), out)
        XCTAssertTrue(out.contains("𝑖𝑡𝑎𝑙𝑖𝑐"), out)
        XCTAssertTrue(out.contains("𝚌𝚘𝚍𝚎"), out)
        XCTAssertTrue(out.contains("s̶t̶r̶i̶k̶e̶"), out)
        XCTAssertFalse(out.contains("**"))
        XCTAssertFalse(out.contains("`"))
        XCTAssertFalse(out.contains("~~"))
    }

    func testMarkdownAwareTreatsUnclosedDelimiterAsLiteral() {
        XCTAssertEqual(UnicodeStylizer.applyMarkdown(to: "hello **world"), "hello **world")
    }

    func testEveryStyleHasNonEmptySample() {
        for style in UnicodeFontStyle.allCases {
            XCTAssertFalse(style.sample.isEmpty, "\(style.rawValue) sample is empty")
        }
    }
}
