//
//  KeyboardLayoutRepairTests.swift
//  DrPasteTests
//
//  Wrong-keyboard-layout repair, both directions and multiple layouts
//  (Russian, Ukrainian). The repair only fires when the character-swapped
//  variant scores higher on the appropriate-language spellcheck.
//

import XCTest
@testable import DrPaste

final class KeyboardLayoutRepairTests: XCTestCase {

    private func repair(_ s: String) -> String { KeyboardLayoutRepair.repair(s) }
    private func wrong(_ s: String) -> Bool { KeyboardLayoutRepair.looksWrongLayout(s) }

    // MARK: swap primitive
    func testSwapEnglishToRussian() {
        XCTAssertEqual(KeyboardLayoutRepair.swap("hello"), "руддщ")
    }
    func testSwapIsInvolutive() {
        let original = "Hello, world"
        XCTAssertEqual(KeyboardLayoutRepair.swap(KeyboardLayoutRepair.swap(original)), original)
    }
    func testSwapPreservesUnknownCharacters() {
        XCTAssertTrue(KeyboardLayoutRepair.swap("abc 123!?").contains("123"))
    }

    // MARK: direction 1 — local text touch-typed on a US/QWERTY layout
    func testRussianSentenceTypedOnQwerty() {
        XCTAssertTrue(wrong("Rcnfnb ns pyftim xnj z nen gbie"))
        XCTAssertEqual(repair("Rcnfnb ns pyftim xnj z nen gbie"),
                       "Кстати ты знаешь что я тут пишу")
    }
    func testUkrainianTypedOnQwerty() {
        // "привіт світ" touch-typed on QWERTY → "ghbdsn cdsn"
        XCTAssertTrue(wrong("ghbdsn cdsn"))
        XCTAssertEqual(repair("ghbdsn cdsn"), "привіт світ")
    }

    // MARK: direction 2 — English touch-typed on a local layout
    func testEnglishTypedOnRussianLayout() {
        XCTAssertTrue(wrong("руддщ"))
        XCTAssertEqual(repair("руддщ"), "hello")
    }
    func testEnglishTypedOnUkrainianLayout() {
        // "this" on the Ukrainian layout uses the і key → "ерші"
        XCTAssertEqual(repair("ерші"), "this")
    }

    // MARK: genuine text must be left alone (no false positives)
    func testGenuineEnglishUnchanged() {
        let s = "The quick brown fox jumps over the lazy dog"
        XCTAssertEqual(repair(s), s)
        XCTAssertFalse(wrong("hello world this is fine"))
    }
    func testGenuineRussianUnchanged() {
        let s = "Съешь же ещё этих мягких французских булок"
        XCTAssertEqual(repair(s), s)
        XCTAssertFalse(wrong("Привет мир как дела сегодня"))
    }
    func testGenuineUkrainianUnchanged() {
        XCTAssertFalse(wrong("Привіт світ як твої справи"))
        let s = "Привіт світ як твої справи"
        XCTAssertEqual(repair(s), s)
    }

    func testShortInputNeverTriggers() {
        XCTAssertFalse(wrong("ab"))
    }

    /// Confidence guard: a single short token must not trigger just because its
    /// swap happens to land on a valid word.
    func testShortSingleTokenNoFalsePositive() {
        XCTAssertFalse(wrong("ds"))
        XCTAssertFalse(wrong("abc"))
    }
}
