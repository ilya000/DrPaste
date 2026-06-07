//
//  UnitConversionCorpusTests.swift
//  DrPasteTests
//
//  Regression coverage from the user's QA corpus: fractions, spelled-out
//  weight/volume units, stone, °C-vs-cup, square units, speed phrasing,
//  the "minus" sign word, and typographic quotes.
//

import XCTest
@testable import DrPaste

final class UnitConversionCorpusTests: XCTestCase {

    private func conv(_ s: String) -> String {
        UnitConversion.convert(s, direction: .auto, mode: .append)
    }

    // Critical: fractions must not invert to the trailing integer.
    func testAsciiFractions() {
        XCTAssertFalse(conv("1/4 mile").contains("6.4 km"), conv("1/4 mile"))
        XCTAssertFalse(conv("3/8 in").contains("20.3 cm"), conv("3/8 in"))
        XCTAssertFalse(conv("1/2 gal").contains("7.57 L"), conv("1/2 gal"))
        XCTAssertTrue(conv("2 3/4 inches").contains("7.0 cm"), conv("2 3/4 inches"))
    }

    func testUnicodeFractions() {
        XCTAssertTrue(conv("6½”").contains("16.5 cm"), conv("6½”"))
        XCTAssertTrue(conv("½ lb").contains("227 g"), conv("½ lb"))
    }

    func testSpelledWeight() {
        XCTAssertTrue(conv("16 ounces").contains("454 g"), conv("16 ounces"))
        XCTAssertTrue(conv("14 pounds").contains("kg"), conv("14 pounds"))
    }

    func testStone() {
        XCTAssertTrue(conv("5 stone").contains("31.8 kg"), conv("5 stone"))
        XCTAssertTrue(conv("11 st 4 lb").contains("71.7 kg"), conv("11 st 4 lb"))
    }

    func testSpelledVolume() {
        XCTAssertTrue(conv("2 gallons").contains("7.57 L"), conv("2 gallons"))
    }

    func testSpeedPhrasing() {
        XCTAssertTrue(conv("65 mi/h").contains("104.6 km/h"), conv("65 mi/h"))
        XCTAssertTrue(conv("55 miles per hour").contains("88.5 km/h"), conv("55 miles per hour"))
        XCTAssertTrue(conv("60 mph").contains("96.6 km/h"), conv("60 mph"))
    }

    func testMinusSign() {
        XCTAssertTrue(conv("minus 4°F").contains("-20.0°C"), conv("minus 4°F"))
    }

    func testCupNotCelsius() {
        XCTAssertEqual(conv("1 c of sugar"), "1 c of sugar")
    }

    func testHyphenatedForms() {
        XCTAssertTrue(conv("14-inch laptop").contains("35.6 cm"), conv("14-inch laptop"))
        XCTAssertTrue(conv("45-pound plate").contains("20.4 kg"), conv("45-pound plate"))
        XCTAssertTrue(conv("5-gallon bucket").contains("18.93 L"), conv("5-gallon bucket"))
    }

    func testTonAcreCupTbspTsp() {
        XCTAssertTrue(conv("1 ton").contains("907.2 kg"), conv("1 ton"))
        XCTAssertTrue(conv("1 long ton").contains("1016.0 kg"), conv("1 long ton"))
        XCTAssertTrue(conv("2.5 acres").contains("1.01 ha"), conv("2.5 acres"))
        XCTAssertTrue(conv("1 cup").contains("237 mL"), conv("1 cup"))
        XCTAssertTrue(conv("1 tbsp").contains("15 mL"), conv("1 tbsp"))
        XCTAssertTrue(conv("1 tsp").contains("5 mL"), conv("1 tsp"))
    }

    /// "2x4 lumber" is a nominal size, not a measurement — must stay untouched.
    func testNominalLumberUntouched() {
        XCTAssertEqual(conv("2x4 lumber"), "2x4 lumber")
    }

    func testSquareUnits() {
        XCTAssertTrue(conv("100 ft²").contains("9.3 m²"), conv("100 ft²"))
        XCTAssertTrue(conv("100 sq ft").contains("9.3 m²"), conv("100 sq ft"))
        XCTAssertTrue(conv("100 square feet").contains("9.3 m²"), conv("100 square feet"))
        XCTAssertFalse(conv("100 ft²").contains("30.48 m"), conv("100 ft²"))
    }
}
