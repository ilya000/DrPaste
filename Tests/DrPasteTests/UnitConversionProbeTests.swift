//
//  UnitConversionProbeTests.swift
//  DrPasteTests
//
//  Self-authored positive / negative / edge / confusable-unit coverage for
//  the inline measurement converter. Each expected substring is the value the
//  converter currently produces; assertions lock the behaviour against drift.
//

import XCTest
@testable import DrPaste

final class UnitConversionProbeTests: XCTestCase {

    private func c(_ s: String) -> String {
        UnitConversion.convert(s, direction: .auto, mode: .append)
    }
    private func has(_ input: String, _ expected: String,
                     file: StaticString = #file, line: UInt = #line) {
        let out = c(input)
        XCTAssertTrue(out.contains(expected), "\(input) → \(out) (wanted “\(expected)”)",
                      file: file, line: line)
    }
    private func unchanged(_ input: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(c(input), input, file: file, line: line)
    }

    // MARK: confusable units must not be mistaken for one another
    func testConfusableUnits() {
        unchanged("5 min walk")                 // min ≠ mi
        has("5 mi run", "8.0 km")
        has("5 m wide", "16.4 ft")
        has("5 mph car", "8.0 km/h")
        has("5 m² floor", "53.8 ft²")
        has("5 ft beam", "1.52 m")
        has("5 ft² panel", "0.5 m²")            // ft² ≠ ft
        has("5 ft³ box", "142 L")               // ft³ ≠ ft
        has("5 oz steak", "142 g")              // weight oz
        has("5 fl oz juice", "148 mL")          // fluid oz
        has("5 cc engine", "0.2 fl oz")
        has("5 ton load", "4535.9 kg")          // short ton
        has("5 tonne ship", "11023.1 lb")       // metric tonne
        has("5 st man", "31.8 kg")              // bare stone (with space)
        unchanged("5 t cargo")                  // bare metric-ton "t" not supported
    }

    // MARK: the °C / cup ambiguity, resolved by case
    func testCelsiusVsCup() {
        unchanged("1 c sugar")                  // lowercase c = cup → skip
        has("1 C room", "33.8°F")               // uppercase C = Celsius
        has("1 cup rice", "237 mL")             // explicit cup
    }

    // MARK: temperature edge cases
    func testTemperatures() {
        has("0°C", "32.0°F")
        has("212°F", "100.0°C")
        has("98.6°F", "37.0°C")
        has("-40°C", "-40.0°F")
        has("-40°F", "-40.0°C")
        has("minus 5°C", "23.0°F")
        has("5° F", "-15.0°C")                  // space before the letter
        unchanged("5°")                         // no scale → ambiguous, skip
    }

    // MARK: numbers, separators, leading zeros
    func testNumberForms() {
        has("007 km", "4.3 mi")
        has("3.14 m", "10.3 ft")
        has("1,000,000 m", "621.4 mi")          // multi-group comma thousands
        has("1 000 000 m", "621.4 mi")          // multi-group space thousands
        has("5km", "3.1 mi")                    // unit glued to number
        has("5,5 m", "18.0 ft")                 // EU decimal comma
        has("5.5 m", "18.0 ft")
    }

    // MARK: must NOT convert (false positives)
    func testNegatives() {
        unchanged("1st place")
        unchanged("2nd row")
        unchanged("31st of May")
        unchanged("v3.5.2 m")                   // version
        unchanged("10E3 m")                     // sci-notation tail
        unchanged("1e3 m")
        unchanged("$5 lb")                      // currency
        unchanged("5%")                         // percent
        unchanged("5:30 m")                     // time
        unchanged("9:00 lb")
        unchanged("16:9 ratio")
        unchanged("call 1-800-CALL")
        unchanged("km 5")                       // unit before number
        unchanged("lb 5")
        unchanged("5st glued")                  // no space before "st" → not stone
    }

    // MARK: model names / context that must be left alone while real values convert
    func testMixedWithNoise() {
        has("A4 sheet 5 cm", "5 cm (2.0 in)")
        XCTAssertFalse(c("A4 sheet 5 cm").contains("A4 ("))
        has("C4 is 2 lb", "907 g")
        has("in 2020 5 km", "5 km (3.1 mi)")
        has("width: 5 cm", "2.0 in")            // colon with a space still converts
        has("at 5:30 he ran 5 km", "5 km (3.1 mi)")
        has("5 km and 10 lb and 32°F", "32°F (0.0°C)")
    }

    // MARK: output modes
    func testModes() {
        XCTAssertEqual(UnitConversion.convert("It is 5 km away", mode: .append),
                       "It is 5 km (3.1 mi) away")
        XCTAssertEqual(UnitConversion.convert("It is 5 km away", mode: .replace),
                       "It is 3.1 mi away")
    }
}
