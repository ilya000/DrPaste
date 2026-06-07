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

    // #A78 — regression: the removed "(X)" unwrap pass used to DROP the
    // character after any "(" not followed by a full "(letter)" (corrupting
    // `foo()` → `foo(`) and to unwrap legitimate "(a)" / "(1)" to "a" / "1".
    // Literal parentheses must now survive normalization untouched.
    func testNormalizePreservesLiteralParentheses() {
        for s in ["func foo() {", "a (b) c", "(1) (2) (3)", "call(x, y)", "()", "(a)"] {
            XCTAssertEqual(UnicodeStylizer.normalize(s), s, "parens corrupted in: \(s)")
            XCTAssertEqual(UnicodeStylizer.apply(to: s, style: .plain), s, "Plain ASCII corrupted: \(s)")
        }
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

    // MARK: #A33 — denormalize-then-restyle invariants

    /// Italic-on-bold previously returned the bold input untouched (the
    /// Italic table is keyed on a-z/A-Z and the bold glyphs aren't in
    /// those ranges). After #A33, every non-`.plain` style denormalizes
    /// the input first, so the output is genuinely italic.
    func testStylingAlreadyStyledTextDenormalizesFirst() {
        let bold = UnicodeStylizer.apply(to: "Hello", style: .bold)
        let italicFromBold = UnicodeStylizer.apply(to: bold, style: .italic)
        let italicFromPlain = UnicodeStylizer.apply(to: "Hello", style: .italic)
        XCTAssertEqual(italicFromBold, italicFromPlain)
    }

    /// Round-trip through several styles. Every staged style flips fully,
    /// no residue from earlier stages.
    func testStyleChainsAreIndependentOfPriorStyle() {
        let input = "Aa Zz 09"
        let stages: [UnicodeFontStyle] = [.bold, .italic, .script, .monospace, .smallCaps]
        var current = input
        for stage in stages {
            current = UnicodeStylizer.apply(to: current, style: stage)
            let fromPlain = UnicodeStylizer.apply(to: input, style: stage)
            XCTAssertEqual(current, fromPlain, "stage \(stage.rawValue) did not denormalize prior styling")
        }
    }

    /// Plain ASCII input must still flow through every styled table —
    /// the denormalize-first fast path can't drop or transform pure ASCII.
    func testStylingPlainInputUnchangedByDenormalizeFastPath() {
        XCTAssertEqual(
            UnicodeStylizer.apply(to: "Hello", style: .bold),
            "𝐇𝐞𝐥𝐥𝐨"
        )
        XCTAssertEqual(
            UnicodeStylizer.apply(to: "Hello", style: .italic),
            "𝐻𝑒𝑙𝑙𝑜"
        )
    }

    /// Upside-down should also rewind first: flipping bold text returns
    /// the flipped ASCII letters, not the original bold glyphs.
    func testUpsideDownDenormalizesBeforeFlip() {
        let bold = UnicodeStylizer.apply(to: "Hello", style: .bold)
        let flippedFromBold = UnicodeStylizer.apply(to: bold, style: .upsideDown)
        let flippedFromPlain = UnicodeStylizer.apply(to: "Hello", style: .upsideDown)
        XCTAssertEqual(flippedFromBold, flippedFromPlain)
    }
}
