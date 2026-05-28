//
//  KeyboardLayoutRepairTests.swift
//  DrPasteTests
//
//  Repair logic for text typed in the wrong keyboard layout. The repair only
//  fires when the character-swapped variant scores higher on the dominant
//  language spellcheck, so the test inputs deliberately use real words.
//

import XCTest
@testable import DrPaste

final class KeyboardLayoutRepairTests: XCTestCase {

    func testSwapEnglishToRussian() {
        // "руддщ" is what "hello" becomes when typed on Russian layout.
        let swapped = KeyboardLayoutRepair.swap("hello")
        XCTAssertEqual(swapped, "руддщ")
    }

    func testSwapIsInvolutive() {
        // Swapping twice returns the original for any pure-letter input.
        let original = "Hello, world"
        let twice = KeyboardLayoutRepair.swap(KeyboardLayoutRepair.swap(original))
        XCTAssertEqual(twice, original)
    }

    func testSwapPreservesUnknownCharacters() {
        // Digits and special characters not in the map are passed through.
        let out = KeyboardLayoutRepair.swap("abc 123!?")
        XCTAssertTrue(out.contains("123"))
    }

    func testRepairLeavesEnglishAlone() {
        // Genuine English text should not be "repaired" to gibberish.
        let input = "The quick brown fox jumps over the lazy dog"
        let repaired = KeyboardLayoutRepair.repair(input)
        XCTAssertEqual(repaired, input)
    }

    func testRepairLeavesRussianAlone() {
        let input = "Съешь же ещё этих мягких французских булок"
        let repaired = KeyboardLayoutRepair.repair(input)
        XCTAssertEqual(repaired, input)
    }

    func testLooksWrongLayoutFalseOnShortInput() {
        // Threshold guards: under 3 chars never triggers.
        XCTAssertFalse(KeyboardLayoutRepair.looksWrongLayout("ab"))
    }

    func testLooksWrongLayoutFalseOnGenuineText() {
        XCTAssertFalse(KeyboardLayoutRepair.looksWrongLayout("hello world this is fine"))
    }
}
