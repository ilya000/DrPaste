//
//  UnitConversionTests.swift
//  DrPasteTests
//
//  Regression coverage for the inline measurement converter.
//

import XCTest
@testable import DrPaste

final class UnitConversionTests: XCTestCase {

    private func conv(_ s: String) -> String {
        UnitConversion.convert(s, direction: .auto, mode: .append)
    }

    /// The reported bug: "6 feet 2 inches" produced "6 feet 2 in (…)ches" —
    /// the inch alternation matched the short "in" first and left "ches"
    /// dangling. The whole word must be consumed.
    func testCompoundFeetInchesDoesNotTruncateWord() {
        let out = conv("My height is 6 feet 2 inches tall")
        // The bug produced "…6 feet 2 in (1.9 m)ches…" — a dangling "ches"
        // right after the parenthetical. The whole word must stay intact.
        XCTAssertFalse(out.contains(")ches"), "inch word was truncated: \(out)")
        XCTAssertTrue(out.contains("6 feet 2 inches ("), "original phrase not preserved: \(out)")
        // 6 ft 2 in = 1.8796 m → "1.88 m" (metres at 2 decimals).
        XCTAssertTrue(out.contains("1.88 m"), "expected 1.88 m, got: \(out)")
    }

    /// Metres render with 2 decimals, km with 1 — metric reading convention.
    func testMetricPrecisionConvention() {
        XCTAssertTrue(conv("6 feet 2 inches").contains("1.88 m"))
        XCTAssertTrue(conv("5 miles to go").contains("8.0 km"))
    }

    /// Regression: spelled-out "meters" (not just "m") must convert. The venue
    /// example "5 meters wide" was left untouched because the regex only had a
    /// bare `m\b`, which "meters" never matched.
    func testSpelledOutMetersConvert() {
        let out = conv("The venue is 5 meters wide")
        XCTAssertTrue(out.contains("5 meters ("), "meters not recognised: \(out)")
        XCTAssertTrue(out.contains("ft"), "expected an imperial equivalent: \(out)")
    }

    func testSpelledOutKilometersConvert() {
        XCTAssertTrue(conv("a 2 kilometers walk").contains("2 kilometers ("))
    }

    func testFahrenheitToCelsius() {
        XCTAssertTrue(conv("It's 75°F outside").contains("75°F (23.9°C)"))
    }

    func testFluidOunces() {
        // 16 fl oz ≈ 473 mL (mL whole numbers).
        let out = conv("the bottle holds 16 fl oz")
        XCTAssertTrue(out.contains("16 fl oz (473 mL)"), out)
    }

    func testPoundsToKilograms() {
        XCTAssertTrue(conv("I weigh 180 lb").contains("180 lb (81.6 kg)"))
    }

    /// Plain "in" as a standalone inch unit still converts (word boundary
    /// keeps it from matching inside other words).
    func testStandaloneInchStillWorks() {
        let out = conv("a 12 in ruler")
        XCTAssertTrue(out.contains("12 in ("), out)
    }

    // Metric → imperial picks the conventional unit by magnitude.
    func testShortMetricDistanceToInchesNotFeet() {
        let out = conv("it is 50 cm long")
        XCTAssertTrue(out.contains(" in)"), "expected inches, got: \(out)")
        XCTAssertFalse(out.contains(" ft)"), "should not use feet under 3 ft: \(out)")
    }

    func testMediumMetricDistanceToFeet() {
        XCTAssertTrue(conv("about 2 m tall").contains(" ft)"))
    }

    func testMillilitersToFluidOuncesNotGallons() {
        let out = conv("a 500 mL bottle")
        XCTAssertTrue(out.contains("fl oz)"), "expected fl oz, got: \(out)")
        XCTAssertFalse(out.contains("gal)"), "should not use gallons for mL: \(out)")
    }

    func testLitersToQuartsThenGallons() {
        XCTAssertTrue(conv("a 2 L jug").contains(" qt)"))
        XCTAssertTrue(conv("a 5 L jug").contains(" gal)"))
    }

    /// Reported bug: a thousands comma ("1,760 yards") was read as a decimal
    /// point → 1.76 yd → "1.61 m". It must be 1760 yd = 1609 m → "1.6 km".
    func testThousandsCommaNotTreatedAsDecimal() {
        let out = conv("the mile (1,760 yards)")
        XCTAssertTrue(out.contains("1.6 km"), "thousands comma misparsed: \(out)")
        XCTAssertFalse(out.contains("1.61 m"), "still reading 1,760 as 1.76: \(out)")
    }

    /// European decimal comma ("5,5 kg" = 5.5 kg) must stay a decimal — only
    /// 3-digit groups are thousands separators.
    func testEuropeanDecimalCommaStillDecimal() {
        let out = conv("it weighs 5,5 kg")
        XCTAssertTrue(out.contains("12.1 lb"), "decimal comma broke: \(out)")
    }

    func testNoMeasurementLeavesTextUnchanged() {
        XCTAssertEqual(conv("just a sentence with no numbers"),
                       "just a sentence with no numbers")
    }
}
