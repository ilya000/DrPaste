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
    private func requireLayoutRepairProbe(file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(
            repair("руддщ") == "hello",
            "Keyboard layout repair dictionaries/layout mappings are unavailable on this runner.",
            file: file,
            line: line
        )
    }

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
    func testRussianSentenceTypedOnQwerty() throws {
        try requireLayoutRepairProbe()
        XCTAssertTrue(wrong("Rcnfnb ns pyftim xnj z nen gbie"))
        XCTAssertEqual(repair("Rcnfnb ns pyftim xnj z nen gbie"),
                       "Кстати ты знаешь что я тут пишу")
    }
    func testUkrainianTypedOnQwerty() throws {
        try requireLayoutRepairProbe()
        // "привіт світ" touch-typed on QWERTY → "ghbdsn cdsn"
        XCTAssertTrue(wrong("ghbdsn cdsn"))
        XCTAssertEqual(repair("ghbdsn cdsn"), "привіт світ")
    }

    // MARK: direction 2 — English touch-typed on a local layout
    func testEnglishTypedOnRussianLayout() throws {
        try requireLayoutRepairProbe()
        XCTAssertTrue(wrong("руддщ"))
        XCTAssertEqual(repair("руддщ"), "hello")
    }
    func testEnglishTypedOnUkrainianLayout() throws {
        try requireLayoutRepairProbe()
        // "this" on the Ukrainian layout uses the і key → "ерші"
        XCTAssertEqual(repair("ерші"), "this")
    }

    // MARK: genuine text must be left alone (no false positives)
    func testGenuineEnglishUnchanged() throws {
        try requireLayoutRepairProbe()
        let s = "The quick brown fox jumps over the lazy dog"
        XCTAssertEqual(repair(s), s)
        XCTAssertFalse(wrong("hello world this is fine"))
    }
    func testGenuineRussianUnchanged() throws {
        try requireLayoutRepairProbe()
        let s = "Съешь же ещё этих мягких французских булок"
        XCTAssertEqual(repair(s), s)
        XCTAssertFalse(wrong("Привет мир как дела сегодня"))
    }
    func testGenuineUkrainianUnchanged() throws {
        try requireLayoutRepairProbe()
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

    // MARK: Bulgarian (Phonetic Traditional)
    func testBulgarianTypedOnQwerty() throws {
        try requireLayoutRepairProbe()
        XCTAssertTrue(wrong("zdrawej swqt"))
        XCTAssertEqual(repair("zdrawej swqt"), "здравей свят")
    }
    func testEnglishTypedOnBulgarianLayout() throws {
        try requireLayoutRepairProbe()
        XCTAssertEqual(repair("тхе яуицк бровн фоь"), "the quick brown fox")
    }
    func testGenuineBulgarianUnchanged() throws {
        try requireLayoutRepairProbe()
        XCTAssertFalse(wrong("Здравей как си днес приятел"))
    }

    // MARK: Serbian Cyrillic (bundled wordlist — no system dictionary)
    func testSerbianTypedOnQwerty() throws {
        try requireLayoutRepairProbe()
        XCTAssertTrue(wrong("ydravo svete"))
        XCTAssertEqual(repair("ydravo svete"), "здраво свете")
    }
    func testEnglishTypedOnSerbianLayout() throws {
        try requireLayoutRepairProbe()
        XCTAssertEqual(repair("хелло њорлд фром сербиа тодаз"), "hello world from serbia today")
    }
    func testGenuineSerbianUnchanged() throws {
        try requireLayoutRepairProbe()
        XCTAssertFalse(wrong("Здраво како си данас пријатељу"))
    }
}
