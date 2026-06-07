//
//  UnitConversionFixesTests.swift
//  DrPasteTests
//
//  Comprehensive regression coverage from the QA corpora (both directions)
//  plus Codex-suggested edge cases. Each expected substring is the value the
//  converter currently produces and is asserted to stay correct.
//

import XCTest
@testable import DrPaste

final class UnitConversionFixesTests: XCTestCase {

    private func c(_ s: String) -> String {
        UnitConversion.convert(s, direction: .auto, mode: .append)
    }
    private func assertHas(_ input: String, _ expected: String,
                           file: StaticString = #file, line: UInt = #line) {
        let out = c(input)
        XCTAssertTrue(out.contains(expected), "\(input) → \(out) (wanted “\(expected)”)",
                      file: file, line: line)
    }

    // MARK: fractions
    func testFractions() {
        assertHas("5/32 in", "4 mm")
        assertHas("2-1/2 ft", "76.2 cm")        // hyphen-joined mixed fraction
        assertHas("2½-foot shelf", "76.2 cm")
        assertHas("2 3/4 inches", "7.0 cm")
        assertHas("1/3 lb burger", "151 g")
        assertHas("6½”", "16.5 cm")
        assertHas("11 3/4\"", "29.8 cm")
        assertHas(".0625\"", "2 mm")
    }

    // MARK: compound weights & lengths
    func testCompounds() {
        assertHas("9 st 8 lb", "60.8 kg")
        assertHas("13st2lb", "83.5 kg")
        assertHas("6 lb 4 oz", "2.8 kg")
        assertHas("6lb4oz", "2.8 kg")
        assertHas("5'11”", "1.80 m")
    }

    // MARK: spelled-out + hyphenated + new imperial units
    func testImperialUnits() {
        assertHas("16 ounces", "454 g")
        assertHas("14 pounds", "6.4 kg")
        assertHas("9-inch blade", "22.9 cm")
        assertHas("100-ton crane", "90718.5 kg")
        assertHas("850 sq ft", "79.0 m²")
        assertHas("200 sq yd", "167.2 m²")
        assertHas("5 sq mi", "12.95 km²")
        assertHas("2.5 acres", "1.01 ha")
        assertHas("1 cup", "237 mL")
    }

    // MARK: speed phrasing (both directions)
    func testSpeed() {
        assertHas("60 mph", "96.6 km/h")
        assertHas("65 mi/h", "104.6 km/h")
        assertHas("55 miles per hour", "88.5 km/h")
        assertHas("65-mile-per-hour limit", "104.6 km/h")
        assertHas("50 kph", "31.1 mph")
        assertHas("90 kilometers per hour", "55.9 mph")
        assertHas("5 m/s", "11.2 mph")
        assertHas("2 km/min", "74.6 mph")
        assertHas("30 cm/s", "0.7 mph")
    }

    // MARK: temperature
    func testTemperature() {
        assertHas("minus 4°F", "-20.0°C")
        assertHas("68 degrees F", "20.0°C")
        assertHas("22 C", "71.6°F")             // bare uppercase C = Celsius
        assertHas("5 degrees C", "41.0°F")
        assertHas("minus 5 degrees Celsius", "23.0°F")
    }

    // MARK: metric → imperial
    func testMetric() {
        assertHas("12 mm", "0.5 in")
        assertHas("3,5 cm", "1.4 in")           // EU decimal comma
        assertHas("1 200 m", "0.7 mi")          // space thousands
        assertHas("1,200 g", "2.6 lb")          // thousands comma
        assertHas("1.2 tonnes", "2645.5 lb")
        assertHas("1 m³", "35.3 ft³")
        assertHas("1 cubic meter", "35.3 ft³")
        assertHas("250 cc", "8.5 fl oz")
        assertHas("1 km²", "0.39 sq mi")
        assertHas("1 ha", "2.47 acres")
        assertHas("120-square-meter house", "1291.7 ft²")
    }

    // MARK: false positives that must stay untouched
    func testFalsePositives() {
        XCTAssertEqual(c("9 in 10 odds"), "9 in 10 odds")
        XCTAssertEqual(c("1 in 5 chance"), "1 in 5 chance")
        XCTAssertEqual(c("1st place"), "1st place")
        XCTAssertEqual(c("21st century"), "21st century")
        XCTAssertEqual(c("2x4 lumber"), "2x4 lumber")
        XCTAssertEqual(c("1 c rice"), "1 c rice")        // cup, not Celsius
        XCTAssertEqual(c("a ton of work"), "a ton of work")
    }

    // MARK: real inches still convert (the in-preposition fix must not over-block)
    func testRealInchesStillConvert() {
        assertHas("12 in ruler", "30.5 cm")
        assertHas("a 12 in cable", "30.5 cm")
    }

    // MARK: numeric ranges — both endpoints
    func testRanges() {
        assertHas("25–30°C", "77.0–86.0°F")        // en-dash
        assertHas("25-30°C", "77.0–86.0°F")        // hyphen
        assertHas("0–60 mph", "0.0–96.6 km/h")
        assertHas("5-10 lb", "2.3–4.5 kg")
        assertHas("10-20 cm", "3.9–7.9 in")
    }

    // MARK: feet + bare inches (no inch marker)
    func testFeetBareInches() {
        assertHas("5 ft 11", "1.80 m")
        assertHas("5'11", "1.80 m")
        assertHas("He is 5 ft 11 tall", "1.80 m")
        // 20 is out of inch range → "5 ft" converts, the 20 is left alone.
        let out = c("5 ft 20")
        XCTAssertTrue(out.contains("5 ft (1.52 m) 20"), out)
    }

    // MARK: output modes (append vs replace)
    func testOutputModes() {
        XCTAssertEqual(UnitConversion.convert("It is 5 km away", direction: .auto, mode: .append),
                       "It is 5 km (3.1 mi) away")
        XCTAssertEqual(UnitConversion.convert("It is 5 km away", direction: .auto, mode: .replace),
                       "It is 3.1 mi away")
    }

    // MARK: adversarial false-positives (Codex review) that must stay untouched
    func testAdversarialFalsePositives() {
        XCTAssertEqual(c("v3.5.2 m"), "v3.5.2 m")          // version string
        XCTAssertEqual(c("10E3 m"), "10E3 m")              // sci-notation tail
        XCTAssertEqual(c("$5 lb"), "$5 lb")                // currency
        XCTAssertEqual(c("9 in, 10 out"), "9 in, 10 out")  // in-preposition + comma
        let abc = c("5 ft 11abc")
        XCTAssertFalse(abc.contains("11 ("), abc)          // 11abc is not inches
    }

    // MARK: adversarial cases that SHOULD now convert
    func testAdversarialConversions() {
        assertHas("10 m^2", "107.6 ft²")                   // caret exponent → area
        assertHas("5 ft 0", "1.52 m")                      // 0 inches allowed
        assertHas("5'0", "1.52 m")
        assertHas("He is 5 ft 11.", "1.80 m")              // sentence period OK
        // real measurement next to currency still converts
        assertHas("price was $5 for 2 lb of apples", "907 g")
        // A4 model name not converted, but the cm measurement is
        let a4 = c("A4 paper is 21 cm")
        XCTAssertTrue(a4.contains("21 cm (8.3 in)") && !a4.contains("A4 ("), a4)
    }

    func testOutputModeSettingRoundTrips() {
        let id = "builtin.text.unit_conversion"
        let original = UnitConversionSettings.replaceMode(for: id)
        defer { UnitConversionSettings.setReplaceMode(original, for: id) }
        UnitConversionSettings.setReplaceMode(true, for: id)
        XCTAssertTrue(UnitConversionSettings.replaceMode(for: id))
        UnitConversionSettings.setReplaceMode(false, for: id)
        XCTAssertFalse(UnitConversionSettings.replaceMode(for: id))
    }
}
