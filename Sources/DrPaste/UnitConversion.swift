//
//  UnitConversion.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Local unit conversion action (#A20). Parses inline measurements
//  from text, converts metric ↔ imperial (auto-detecting source
//  system), and inserts the converted value alongside or in place
//  of the original.
//
//  Categories supported in v1:
//    • Length  — m / cm / mm / km ↔ in / ft / yd / mi
//    • Weight  — g / kg ↔ oz / lb
//    • Temperature — °C ↔ °F (no Kelvin per user spec)
//    • Volume  — L / mL ↔ fl oz / gal / qt / pt
//    • Speed   — km/h ↔ mph
//    • Area    — m² ↔ ft²
//
//  Parser handles:
//    • Single value          "5 km"   "200kg"   "75°F"
//    • Compound length       "6 feet 7 in" / "5 ft 11" / "5'11""
//    • Decimal or comma sep  "5.5 kg" or "5,5 kg"
//
//  Output modes:
//    • `.append` (default) — original kept, converted appended in
//      parentheses: "It's 75°F (23.9°C) outside"
//    • `.replace` — original replaced: "It's 23.9°C outside"
//

import Foundation

enum UnitConversion {

    /// Direction for the conversion pass.
    enum Direction {
        /// Auto-detect: convert imperial → metric and metric → imperial.
        case auto
        /// Force everything imperial → metric.
        case toMetric
        /// Force everything metric → imperial.
        case toImperial
    }

    /// Output formatting mode.
    enum OutputMode {
        /// Original stays, converted appended in parentheses.
        case append
        /// Original replaced by converted.
        case replace
    }

    /// Walk the input string, find each measurement match, and replace
    /// or annotate as configured. Pure function; safe to call off-main.
    static func convert(_ input: String,
                        direction: Direction = .auto,
                        mode: OutputMode = .append) -> String {
        var result = ""
        var lastEnd = input.startIndex

        let matches = scan(input)

        for match in matches {
            // Append untouched text before this match.
            result += input[lastEnd..<match.range.lowerBound]
            // Decide whether this match should be converted given
            // `direction`.
            let convertOne: () -> String? = {
                if let v2 = match.value2 { return convertRange(match.value, v2, match.unit) }
                return convertMeasurement(match)
            }
            let converted: String? = {
                switch direction {
                case .auto:      return convertOne()
                case .toMetric:  return match.isMetric ? nil : convertOne()
                case .toImperial: return match.isMetric ? convertOne() : nil
                }
            }()
            switch mode {
            case .append:
                let original = String(input[match.range])
                if let c = converted {
                    result += "\(original) (\(c))"
                } else {
                    result += original
                }
            case .replace:
                let original = String(input[match.range])
                result += converted ?? original
            }
            lastEnd = match.range.upperBound
        }
        result += input[lastEnd...]
        return result
    }

    // MARK: parser

    /// One parsed measurement. `value` is in the unit identified by
    /// `unit`. Compound measurements (e.g. "6 ft 7 in") are merged
    /// into a single `Match` with `unit = .feet` and value = 6 + 7/12.
    struct Match {
        let range: Range<String.Index>
        let value: Double
        /// Second endpoint for a numeric range ("25–30 °C"). nil for a single
        /// measurement.
        var value2: Double? = nil
        let unit: Unit
        var isMetric: Bool { unit.isMetric }
    }

    enum Unit {
        // Length
        case mm, cm, m, km
        case inches, feet, yards, miles
        // Weight
        case grams, kilograms, tonne
        case ounces, pounds, stone, shortTon, longTon
        // Temperature
        case celsius, fahrenheit
        // Volume
        case milliliters, liters, cc, cubicMeters
        case fluidOunces, gallons, quarts, pints, cups, tablespoons, teaspoons
        // Speed
        case kmh, mph, metersPerSecond, kmPerMin, cmPerSecond
        // Area
        case squareMeters, squareFeet, acre
        case squareYards, squareMiles, squareKm, hectare

        var isMetric: Bool {
            switch self {
            case .mm, .cm, .m, .km,
                 .grams, .kilograms, .tonne,
                 .celsius,
                 .milliliters, .liters, .cc, .cubicMeters,
                 .kmh, .metersPerSecond, .kmPerMin, .cmPerSecond,
                 .squareMeters, .squareKm, .hectare:
                return true
            default:
                return false
            }
        }
    }

    /// Unicode vulgar fractions → decimal value.
    static let unicodeFractions: [Character: Double] = [
        "¼": 1.0/4, "½": 1.0/2, "¾": 3.0/4,
        "⅓": 1.0/3, "⅔": 2.0/3,
        "⅕": 1.0/5, "⅖": 2.0/5, "⅗": 3.0/5, "⅘": 4.0/5,
        "⅙": 1.0/6, "⅚": 5.0/6,
        "⅛": 1.0/8, "⅜": 3.0/8, "⅝": 5.0/8, "⅞": 7.0/8,
        "⅐": 1.0/7, "⅑": 1.0/9, "⅒": 1.0/10
    ]
    private static let fracClass = "¼½¾⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞⅐⅑⅒"

    /// One quantity token: mixed/simple fractions (ASCII or Unicode), a
    /// thousands-grouped or decimal number, or a bare ".75". Sign is `-`,
    /// the Unicode minus `−`, or the words "minus"/"negative" (handled in
    /// `parseChunk`). Ordered longest-first so "2 3/4" beats "3/4" beats "4".
    private static var qty: String {
        let f = fracClass
        return "(?:" + [
            #"\d+[\s\-]+\d+\s*[/⁄∕]\s*\d+"#,      // mixed ASCII: 2 3/4  or  2-1/2
            "\\d+\\s*[\(f)]",                        // mixed Unicode: 6½
            #"\d+\s*[/⁄∕]\s*\d+"#,                 // simple ASCII: 3/4
            "[\(f)]",                               // bare Unicode: ½
                        #"\d{1,3}(?:[ \x{00A0}\x{202F}]\d{3})+(?:[.,]\d+)?"#,  // space thousands: 1 200
            #"\d{1,3}(?:\.\d{3})+,\d+"#,           // EU mixed: 1.200,5
            #"\d{1,3}(?:,\d{3})+(?:\.\d+)?"#,      // 1,760  12,345.5
            #"\d+(?:[.,]\d+)?"#,                    // 5  5.5  5,5
            #"\.\d+"#                                // .75
        ].joined(separator: "|") + ")"
    }

    /// Regex over the input. Order matters in the unit list: speed and area
    /// units come before the length units whose abbreviations they share a
    /// prefix with ("mi/h" before "mi", "ft²" before "ft"), and spelled-out
    /// forms before abbreviations.
    private static let pattern: NSRegularExpression = {
        let q = qty
        let units = [
            // SPEED (before the length units mi / km / m / cm they share a prefix
            // with). Per-hour / per-second phrases allow hyphen joiners.
            #"km\s*/\s*h"#, "kmh", "kph", #"kilomet(?:er|re)s?[\s\-]+per[\s\-]+hour"#,
            "mph", #"mi\s*/\s*h"#, #"miles?[\s\-]+per[\s\-]+hour"#,
            #"m\s*/\s*s"#, #"met(?:er|re)s?[\s\-]+per[\s\-]+second"#,
            #"km\s*/\s*min"#, #"cm\s*/\s*s"#,
            // AREA (before length, because of the ² / m / ft prefixes)
            #"square[\s\-]*kilomet(?:er|re)s?"#, #"sq\.?\s*km"#, "km²", "km2", #"km\^2"#,
            #"square[\s\-]*f(?:ee|oo)t"#, #"sq\.?\s*ft"#, "sqft", "ft²", "ft2", #"ft\^2"#,
            #"square[\s\-]*met(?:er|re)s?"#, #"sq\.?\s*m"#, "m²", "m2", #"m\^2"#,
            #"square[\s\-]*yards?"#, #"sq\.?\s*yd"#, #"square[\s\-]*miles?"#, #"sq\.?\s*mi"#,
            "hectares?", "ha", "acres?",
            // VOLUME (cubic before the length units they share a prefix with)
            #"cubic[\s\-]*met(?:er|re)s?"#, "m³", #"m\^3"#, "cm³", "cc",
            #"fluid[\s\-]*ounces?"#, #"fl\s*oz"#, "gallons?", "gal", "quarts?", "qt", "pints?", "pt",
            "tablespoons?", "tbsp", "teaspoons?", "tsp", "cups?",
            #"millilit(?:er|re)s?"#, "ml", #"lit(?:er|re)s?"#, "l",
            // TEMPERATURE. Bare "C" is case-sensitive (uppercase only) so it does
            // not swallow "c" = cup; bare "f"/"F" stays case-insensitive.
            #"degrees?\s+fahrenheit"#, #"degrees?\s+celsius"#, #"degrees?\s+[cf]\b"#,
            "fahrenheit", "celsius", "°c", "°f", "(?-i:C)", "f",
            // WEIGHT
            "kilogrammes?", "kilograms?", "kg",
            #"(?:metric\s+)?tonnes?"#, #"metric\s+tons?"#, #"(?:short\s+|long\s+)?tons?"#,
            "pounds?", "lbs?", "ounces?", "oz", "stones?", "grams?", "g",
            // LENGTH
            #"kilomet(?:er|re)s?"#, "km", #"centimet(?:er|re)s?"#, "cm",
            #"millimet(?:er|re)s?"#, "mm", #"met(?:er|re)s?"#, "m",
            // Bare "in" must not fire when a number follows ("9 in 10 odds",
            // "1 in 5") — that's the preposition, not inches.
            "inch(?:es)?", #"in(?![\s,;:]*\d)"#, "feet", "foot", "ft", "yards?", "yd", "miles?", "mi",
            "['’′]", "[\"”″]"     // straight + typographic foot ′ / inch ″ marks
        ]
        let unitGroup = "(?:" + units.joined(separator: "|") + ")"
        let alternatives = [
            // compound foot+inch (longest-first inch alt so the word is consumed)
            #"(\d+(?:[.,]\d+)?)\s*(?:ft|feet|['’′])\s*(\d+(?:[.,]\d+)?)\s*(?:inch(?:es)?|in\b|["”″])"#,
            #"(\d+(?:[.,]\d+)?)['’′](\d+(?:[.,]\d+)?)["”″]"#,
            // feet + bare number (no inch marker): "5 ft 11" / "5'11" / "5 ft 0".
            // Trailing number gated to 0–11 (inches), and must not run into a
            // word/digit/decimal ("5 ft 11abc", "5 ft 11.5", "5 ft 110").
            #"(\d+(?:[.,]\d+)?)\s*(?:ft|feet|['’′])\s*(1[01]|[0-9])(?!\.\d)(?![\w/⁄∕])"#,
            // compound stone+pound: "11 st 4 lb" / "11 stone 4" / "11st4lb"
            #"\d+(?:[.,]\d+)?\s*(?:stones?|st)\s*\d+(?:[.,]\d+)?\s*(?:lbs?|pounds?)?"#,
            // compound pound+ounce: "6 lb 4 oz" / "6lb4oz"
            #"\d+(?:[.,]\d+)?\s*(?:lbs?|pounds?)\s*\d+(?:[.,]\d+)?\s*(?:oz|ounces?)"#,
            // numeric range: "25–30 °C" / "25-30°C" (two plain numbers, one
            // unit). Requires a real unit right after the second number, so
            // "2-1/2 ft" and "8-ounce" never match here.
            #"\d+(?:[.,]\d+)?\s*[–—-]\s*\d+(?:[.,]\d+)?\s*°?\s*"# + unitGroup + #"(?=[^A-Za-z]|$)"#,
            // single value + unit. Trailing lookahead replaces \b so units that
            // end in a non-word char (ft² / m²) still match fully.
            "(?:(?:minus|negative)\\s+)?[-−]?" + q + #"\s*°?\s*-?\s*"# + unitGroup + #"(?=[^A-Za-z]|$)"#
        ]
        // Leading boundary: a measurement must not start in the middle of a
        // larger token — blocks "v3.5.2 m" (→5.2 m), "10E3 m" (→3 m), "$5 lb",
        // "A4 m". Allows space, "(", a sign, or start-of-string before it.
        let combined = #"(?<![\w.,$£€#])(?:"# + alternatives.joined(separator: "|") + ")"
        return try! NSRegularExpression(pattern: combined, options: [.caseInsensitive])
    }()

    private static func scan(_ input: String) -> [Match] {
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = pattern.matches(in: input, options: [], range: nsRange)
        var results: [Match] = []
        for m in matches {
            guard let range = Range(m.range, in: input) else { continue }
            let chunk = String(input[range])
            if let parsed = parseChunk(chunk, range: range) {
                results.append(parsed)
            }
        }
        return results
    }

    /// Parse one regex-matched chunk into a `Match`.
    private static func parseChunk(_ chunk: String, range: Range<String.Index>) -> Match? {
        var lower = chunk.lowercased()
        // Leading sign word ("minus 4°F" → −4°F).
        var negate = false
        for word in ["minus ", "negative "] where lower.hasPrefix(word) {
            negate = true
            lower = String(lower.dropFirst(word.count))
            break
        }
        // Compound stone+pound ("11 st 4 lb") — try before feet+inch.
        if let st = parseCompoundStoneLb(lower) {
            return Match(range: range, value: negate ? -st : st, unit: .stone)
        }
        // Compound pound+ounce ("6 lb 4 oz" → pounds).
        if let lb = parseCompoundPoundOz(lower) {
            return Match(range: range, value: negate ? -lb : lb, unit: .pounds)
        }
        // Compound foot+inch.
        if let compound = parseCompoundFeetInches(lower) {
            return Match(range: range, value: negate ? -compound : compound, unit: .feet)
        }
        // Numeric range ("25–30 °C").
        if let (v1, v2, unit) = parseRange(lower) {
            return Match(range: range, value: negate ? -v1 : v1,
                         value2: negate ? -v2 : v2, unit: unit)
        }
        // Single value + unit. Extract the leading quantity (handles fractions).
        let q = parseLeadingQuantity(lower)
        guard var value = q.value else { return nil }
        if negate { value = -value }
        // Strip the gap between number and unit — spaces and an optional hyphen
        // ("14-inch" → "inch") — but KEEP the ° so parseUnit can tell "°C"
        // (valid) from "c" (a cup, deliberately not Celsius).
        let rest = String(lower.dropFirst(q.consumed))
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t-"))
        guard let unit = parseUnit(rest) else { return nil }
        return Match(range: range, value: value, unit: unit)
    }

    /// Compound "11 st 4 lb" / "11 stone 4" / "11st4lb" → value in stones.
    private static func parseCompoundStoneLb(_ s: String) -> Double? {
        let pat = #"^(\d+(?:[.,]\d+)?)\s*(?:stones?|st)\s*(\d+(?:[.,]\d+)?)\s*(?:lbs?|pounds?)?$"#
        guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { return nil }
        let nsr = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: nsr),
              m.numberOfRanges == 3,
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s) else { return nil }
        let st = Double(String(s[r1]).replacingOccurrences(of: ",", with: ".")) ?? 0
        let lb = Double(String(s[r2]).replacingOccurrences(of: ",", with: ".")) ?? 0
        return st + lb / 14.0     // 1 stone = 14 lb
    }

    /// Numeric range "25-30 °c" → (25, 30, .celsius). Both endpoints are plain
    /// numbers separated by a dash; a real unit must follow the second one.
    private static func parseRange(_ s: String) -> (Double, Double, Unit)? {
        let pat = #"^(\d+(?:[.,]\d+)?)\s*[–—-]\s*(\d+(?:[.,]\d+)?)\s*(.+)$"#
        guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { return nil }
        let nsr = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: nsr),
              m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s),
              let r3 = Range(m.range(at: 3), in: s),
              let v1 = normalizeNumber(String(s[r1])),
              let v2 = normalizeNumber(String(s[r2])) else { return nil }
        let rest = String(s[r3]).trimmingCharacters(in: CharacterSet(charactersIn: " \t-"))
        guard let unit = parseUnit(rest) else { return nil }
        return (v1, v2, unit)
    }

    /// Compound "6 lb 4 oz" / "6lb4oz" → value in pounds (1 lb = 16 oz).
    private static func parseCompoundPoundOz(_ s: String) -> Double? {
        let pat = #"^(\d+(?:[.,]\d+)?)\s*(?:lbs?|pounds?)\s*(\d+(?:[.,]\d+)?)\s*(?:oz|ounces?)$"#
        guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { return nil }
        let nsr = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: nsr),
              m.numberOfRanges == 3,
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s) else { return nil }
        let lb = Double(String(s[r1]).replacingOccurrences(of: ",", with: ".")) ?? 0
        let oz = Double(String(s[r2]).replacingOccurrences(of: ",", with: ".")) ?? 0
        return lb + oz / 16.0
    }

    /// Extract the leading quantity token and its consumed character count.
    private static func parseLeadingQuantity(_ s: String) -> (value: Double?, consumed: Int) {
        guard let re = try? NSRegularExpression(pattern: "^[-−]?" + qty,
                                                options: [.caseInsensitive]) else { return (nil, 0) }
        let nsr = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: nsr),
              let r = Range(m.range, in: s) else { return (nil, 0) }
        let token = String(s[r])
        let consumed = s.distance(from: s.startIndex, to: r.upperBound)
        return (parseQuantityValue(token), consumed)
    }

    /// Turn a quantity token ("2 3/4", "6½", "3/8", "½", "1,760", ".75")
    /// into a Double.
    static func parseQuantityValue(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var sign = 1.0
        if s.hasPrefix("-") || s.hasPrefix("−") { sign = -1; s.removeFirst() }
        // Unicode fraction, optionally with a leading whole number ("6½", "½").
        if let last = s.last, let fv = unicodeFractions[last] {
            let intPart = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
            let whole = intPart.isEmpty ? 0 : (normalizeNumber(intPart) ?? 0)
            return sign * (whole + fv)
        }
        // ASCII fraction, mixed ("2 3/4", "2-1/2") or simple ("3/4").
        if let slashIdx = s.firstIndex(where: { "/⁄∕".contains($0) }) {
            let denom = Double(String(s[s.index(after: slashIdx)...]).trimmingCharacters(in: .whitespaces))
            let left = String(s[..<slashIdx]).trimmingCharacters(in: .whitespaces)
            // Whole and numerator may be separated by a space OR a hyphen.
            let parts = left.split(whereSeparator: { $0 == " " || $0 == "-" })
            guard let d = denom, d != 0 else { return nil }
            if parts.count == 2, let whole = Double(parts[0]), let num = Double(parts[1]) {
                return sign * (whole + num / d)
            }
            if parts.count == 1, let num = Double(parts[0]) {
                return sign * (num / d)
            }
            return nil
        }
        // Plain number (thousands / decimal handled by normalizeNumber).
        guard let v = normalizeNumber(s) else { return nil }
        return sign * v
    }

    private static func parseCompoundFeetInches(_ s: String) -> Double? {
        // Patterns covered:
        //   "6 ft 7 in" / "6 feet 7 inches" / "6'7""
        let patterns = [
            #"^(\d+(?:[.,]\d+)?)\s*(?:ft|feet|['’′])\s*(\d+(?:[.,]\d+)?)\s*(?:inch(?:es)?|in|["”″]?)$"#,
            #"^(\d+(?:[.,]\d+)?)['’′](\d+(?:[.,]\d+)?)["”″]?$"#
        ]
        for pat in patterns {
            guard let re = try? NSRegularExpression(pattern: pat,
                                                    options: [.caseInsensitive]) else { continue }
            let nsr = NSRange(s.startIndex..<s.endIndex, in: s)
            if let m = re.firstMatch(in: s, options: [], range: nsr),
               m.numberOfRanges == 3,
               let r1 = Range(m.range(at: 1), in: s),
               let r2 = Range(m.range(at: 2), in: s) {
                let ft = Double(String(s[r1]).replacingOccurrences(of: ",", with: ".")) ?? 0
                let inches = Double(String(s[r2]).replacingOccurrences(of: ",", with: ".")) ?? 0
                return ft + inches / 12.0
            }
        }
        return nil
    }

    /// Turn a raw numeric token ("1,760", "5,5", "1,234.5", "3.5") into a
    /// Double, deciding whether each `.`/`,` is a thousands grouping or a
    /// decimal separator. Needed because a thousands comma ("1,760 yards")
    /// was previously read as a decimal point → 1.76 instead of 1760.
    private static func normalizeNumber(_ raw: String) -> Double? {
        var s = raw
        let negative = s.hasPrefix("-")
        if negative { s.removeFirst() }
        // A trailing `.`/`,` is sentence punctuation, not part of the number.
        while let last = s.last, last == "." || last == "," { s.removeLast() }
        guard !s.isEmpty else { return nil }

        // Space-grouped thousands ("1 200" / "1 200 000") → strip the spaces.
        if s.range(of: #"^\d{1,3}([ \x{00A0}\x{202F}]\d{3})+([.,]\d+)?$"#,
                   options: .regularExpression) != nil {
            s = s.replacingOccurrences(of: " ", with: "")
                 .replacingOccurrences(of: "\u{00A0}", with: "")
                 .replacingOccurrences(of: "\u{202F}", with: "")
        }

        let hasComma = s.contains(",")
        let hasDot = s.contains(".")
        let normalized: String
        if hasComma && hasDot {
            // Mixed: the LAST-occurring separator is the decimal point; the
            // other groups thousands. Handles "1,234.5" and "1.234,5".
            if s.lastIndex(of: ",")! > s.lastIndex(of: ".")! {
                normalized = s.replacingOccurrences(of: ".", with: "")
                              .replacingOccurrences(of: ",", with: ".")
            } else {
                normalized = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            // Comma only. Thousands grouping ("1,760", "12,345") vs European
            // decimal ("5,5", "12,75"). Grouping is exactly groups of 3 digits.
            if s.range(of: #"^\d{1,3}(,\d{3})+$"#, options: .regularExpression) != nil {
                normalized = s.replacingOccurrences(of: ",", with: "")    // thousands
            } else {
                normalized = s.replacingOccurrences(of: ",", with: ".")   // decimal
            }
        } else {
            // Dot only (or no separators). Treat dot as decimal — the common
            // case ("3.5"); English text rarely uses dot as a thousands mark.
            normalized = s
        }
        guard let v = Double(normalized) else { return nil }
        return negative ? -v : v
    }

    private static func parseUnit(_ s: String) -> Unit? {
        // Normalize away spaces, dots and hyphens ("fl oz" → "floz",
        // "sq. ft." → "sqft", "mile-per-hour" → "mileperhour", "11 in." → "in").
        // The degree sign is KEPT so "°c" stays distinct from "c" (a cup, which
        // we deliberately don't treat as Celsius).
        let t = s.replacingOccurrences(of: " ", with: "")
                 .replacingOccurrences(of: "\u{00A0}", with: "")   // NBSP
                 .replacingOccurrences(of: "\u{202F}", with: "")   // narrow NBSP
                 .replacingOccurrences(of: ".", with: "")
                 .replacingOccurrences(of: "-", with: "")
                 .replacingOccurrences(of: "^", with: "")          // "m^2" → "m2"
        switch t {
        case "mm", "millimeter", "millimeters", "millimetre", "millimetres": return .mm
        case "cm", "centimeter", "centimeters", "centimetre", "centimetres": return .cm
        case "m", "meter", "meters", "metre", "metres":  return .m
        case "km", "kilometer", "kilometers", "kilometre", "kilometres": return .km
        case "in", "inch", "inches", "\"", "”", "″": return .inches
        case "ft", "feet", "foot", "'", "’", "′":    return .feet
        case "yd", "yard", "yards":        return .yards
        case "mi", "mile", "miles":        return .miles
        case "g", "gram", "grams":  return .grams
        case "kg", "kilogram", "kilograms", "kilogramme", "kilogrammes": return .kilograms
        case "oz", "ounce", "ounces": return .ounces
        case "lb", "lbs", "pound", "pounds": return .pounds
        case "st", "stone", "stones": return .stone
        case "ton", "tons", "shortton", "shorttons": return .shortTon
        case "longton", "longtons": return .longTon
        case "tonne", "tonnes", "metricton", "metrictons", "metrictonne", "metrictonnes": return .tonne
        // Bare "c" only reaches here when the regex matched an UPPERCASE C
        // (case-sensitive) — lowercase "c" (cup) never gets this far.
        case "c", "°c", "celsius", "degreec", "degreesc", "degreecelsius", "degreescelsius": return .celsius
        case "°f", "f", "fahrenheit", "degreef", "degreesf", "degreefahrenheit", "degreesfahrenheit": return .fahrenheit
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": return .milliliters
        case "l", "liter", "liters", "litre", "litres":  return .liters
        case "floz", "fluidounce", "fluidounces": return .fluidOunces
        case "gal", "gallon", "gallons": return .gallons
        case "qt", "quart", "quarts": return .quarts
        case "pt", "pint", "pints":   return .pints
        case "cup", "cups":           return .cups
        case "tbsp", "tablespoon", "tablespoons": return .tablespoons
        case "tsp", "teaspoon", "teaspoons":      return .teaspoons
        case "cc", "cm³", "cm3":      return .cc
        case "m³", "m3", "cubicmeter", "cubicmeters", "cubicmetre", "cubicmetres": return .cubicMeters
        // Speed
        case "km/h", "kmh", "kph", "kilometerperhour", "kilometersperhour",
             "kilometreperhour", "kilometresperhour": return .kmh
        case "mph", "mi/h", "mileperhour", "milesperhour": return .mph
        case "m/s", "meterpersecond", "meterspersecond", "metrepersecond", "metrespersecond": return .metersPerSecond
        case "km/min": return .kmPerMin
        case "cm/s":   return .cmPerSecond
        // Area
        case "m²", "m2", "sqm", "squarem", "squaremeter", "squaremeters", "squaremetre", "squaremetres": return .squareMeters
        case "ft²", "ft2", "sqft", "squarefeet", "squarefoot": return .squareFeet
        case "km²", "km2", "sqkm", "squarekm", "squarekilometer", "squarekilometers", "squarekilometre", "squarekilometres": return .squareKm
        case "sqyd", "squareyard", "squareyards": return .squareYards
        case "sqmi", "squaremile", "squaremiles": return .squareMiles
        case "ha", "hectare", "hectares": return .hectare
        case "acre", "acres": return .acre
        default: return nil
        }
    }

    // MARK: conversion table

    /// Convert one match into a formatted string in the opposite
    /// system. Returns nil if no sensible conversion exists.
    private static func convertMeasurement(_ m: Match) -> String? {
        switch m.unit {
        // Length: SI base = meters
        case .mm:        return formatMetric(m.value / 1000, baseUnit: .meters, toMetric: false)
        case .cm:        return formatMetric(m.value / 100, baseUnit: .meters, toMetric: false)
        case .m:         return formatMetric(m.value, baseUnit: .meters, toMetric: false)
        case .km:        return formatMetric(m.value * 1000, baseUnit: .meters, toMetric: false)
        case .inches:    return formatMetric(m.value * 0.0254, baseUnit: .meters, toMetric: true)
        case .feet:      return formatMetric(m.value * 0.3048, baseUnit: .meters, toMetric: true)
        case .yards:     return formatMetric(m.value * 0.9144, baseUnit: .meters, toMetric: true)
        case .miles:     return formatMetric(m.value * 1609.344, baseUnit: .meters, toMetric: true)
        // Weight: SI base = kilograms
        case .grams:     return formatMetric(m.value / 1000, baseUnit: .kilograms, toMetric: false)
        case .kilograms: return formatMetric(m.value, baseUnit: .kilograms, toMetric: false)
        case .ounces:    return formatMetric(m.value * 0.0283495, baseUnit: .kilograms, toMetric: true)
        case .pounds:    return formatMetric(m.value * 0.453592, baseUnit: .kilograms, toMetric: true)
        case .stone:     return formatMetric(m.value * 6.35029, baseUnit: .kilograms, toMetric: true)
        case .shortTon:  return formatMetric(m.value * 907.18474, baseUnit: .kilograms, toMetric: true)
        case .longTon:   return formatMetric(m.value * 1016.0469, baseUnit: .kilograms, toMetric: true)
        case .tonne:     return formatMetric(m.value * 1000, baseUnit: .kilograms, toMetric: false)
        // Temperature
        case .celsius:    return String(format: "%.1f°F", m.value * 9.0/5.0 + 32)
        case .fahrenheit: return String(format: "%.1f°C", (m.value - 32) * 5.0/9.0)
        // Volume: SI base = liters
        case .milliliters: return formatMetric(m.value / 1000, baseUnit: .liters, toMetric: false)
        case .liters:      return formatMetric(m.value, baseUnit: .liters, toMetric: false)
        case .fluidOunces: return formatMetric(m.value * 0.02957, baseUnit: .liters, toMetric: true)
        case .gallons:     return formatMetric(m.value * 3.78541, baseUnit: .liters, toMetric: true)
        case .quarts:      return formatMetric(m.value * 0.94635, baseUnit: .liters, toMetric: true)
        case .pints:       return formatMetric(m.value * 0.47318, baseUnit: .liters, toMetric: true)
        case .cups:        return formatMetric(m.value * 0.236588, baseUnit: .liters, toMetric: true)
        case .tablespoons: return formatMetric(m.value * 0.0147868, baseUnit: .liters, toMetric: true)
        case .teaspoons:   return formatMetric(m.value * 0.00492892, baseUnit: .liters, toMetric: true)
        case .cc:          return formatMetric(m.value / 1000, baseUnit: .liters, toMetric: false)
        case .cubicMeters: return String(format: "%.1f ft³", m.value * 35.3147)
        // Speed
        case .kmh: return String(format: "%.1f mph", m.value / 1.609344)
        case .mph: return String(format: "%.1f km/h", m.value * 1.609344)
        case .metersPerSecond: return String(format: "%.1f mph", m.value * 2.236936)
        case .kmPerMin:        return String(format: "%.1f mph", m.value * 37.28227)
        case .cmPerSecond:     return String(format: "%.1f mph", m.value * 0.02236936)
        // Area: SI base = m²
        case .squareMeters: return String(format: "%.1f ft²", m.value * 10.7639)
        case .squareFeet:   return String(format: "%.1f m²", m.value * 0.092903)
        case .squareYards:  return String(format: "%.1f m²", m.value * 0.836127)
        case .squareMiles:  return String(format: "%.2f km²", m.value * 2.589988)
        case .squareKm:     return String(format: "%.2f sq mi", m.value * 0.386102)
        case .hectare:      return String(format: "%.2f acres", m.value * 2.47105)
        case .acre:
            // acre → m², promoting to hectares once it gets large.
            let m2 = m.value * 4046.8564
            return m2 >= 10000 ? String(format: "%.2f ha", m2 / 10000)
                               : String(format: "%.0f m²", m2)
        }
    }

    /// Convert a numeric range ("25–30 °C") by converting both endpoints and,
    /// when they share a unit suffix, merging to "A–B suffix" ("77.0–86.0°F").
    private static func convertRange(_ a: Double, _ b: Double, _ unit: Unit) -> String? {
        let z = "".startIndex
        guard let sa = convertMeasurement(Match(range: z..<z, value: a, unit: unit)),
              let sb = convertMeasurement(Match(range: z..<z, value: b, unit: unit)) else { return nil }
        let (na, ua) = splitNumberUnit(sa)
        let (nb, ub) = splitNumberUnit(sb)
        if !ua.isEmpty && ua == ub { return "\(na)–\(nb)\(ua)" }
        return "\(sa)–\(sb)"
    }

    /// Split "77.0°F" → ("77.0", "°F") and "1.6 km" → ("1.6", " km").
    private static func splitNumberUnit(_ s: String) -> (String, String) {
        var num = "", suffix = ""
        var inNumber = true
        for ch in s {
            if inNumber && (ch.isNumber || ch == "." || ch == "," || ch == "-") {
                num.append(ch)
            } else {
                inNumber = false
                suffix.append(ch)
            }
        }
        return (num, suffix)
    }

    private enum BaseUnit {
        case meters, kilograms, liters
    }

    /// Format a SI-base value in the opposite system. `toMetric=true`
    /// means the input was imperial — format the resulting metric
    /// value cleanly. `toMetric=false` means input was metric —
    /// format as imperial.
    private static func formatMetric(_ siValue: Double, baseUnit: BaseUnit, toMetric: Bool) -> String {
        switch baseUnit {
        case .meters:
            if toMetric {
                // Choose mm / cm / m / km by magnitude. Decimal places follow
                // metric reading convention: mm whole, cm 1, m 2, km 1.
                let absV = abs(siValue)
                if absV < 0.01 { return String(format: "%.0f mm", siValue * 1000) }
                if absV < 1    { return String(format: "%.1f cm", siValue * 100) }
                if absV < 1000 { return String(format: "%.2f m",  siValue) }
                return String(format: "%.1f km", siValue / 1000)
            } else {
                // m → imperial. Pick the unit the way people actually read it:
                // inches up to 3 ft, then feet up to ~0.1 mile, then miles.
                let inches = siValue / 0.0254
                let absV = abs(siValue)
                if absV < 0.9144   { return String(format: "%.1f in", inches) }     // < 3 ft
                if absV < 160.9344 { return String(format: "%.1f ft", inches / 12) } // < 0.1 mi
                return String(format: "%.1f mi", siValue / 1609.344)
            }
        case .kilograms:
            if toMetric {
                let absV = abs(siValue)
                if absV < 1 { return String(format: "%.0f g", siValue * 1000) }
                return String(format: "%.1f kg", siValue)
            } else {
                let lb = siValue / 0.453592
                if abs(lb) < 1 { return String(format: "%.1f oz", siValue / 0.0283495) }
                return String(format: "%.1f lb", lb)
            }
        case .liters:
            if toMetric {
                let absV = abs(siValue)
                if absV < 1 { return String(format: "%.0f mL", siValue * 1000) }
                return String(format: "%.2f L", siValue)
            } else {
                // L → imperial. Small volumes read in fluid ounces, then
                // quarts, then gallons — never tiny fractions of a gallon.
                let absV = abs(siValue)
                if absV < 0.946353 { return String(format: "%.1f fl oz", siValue / 0.0295735) }  // < 1 qt
                if absV < 3.785412 { return String(format: "%.2f qt", siValue / 0.946353) }       // < 1 gal
                return String(format: "%.2f gal", siValue / 3.78541)
            }
        }
    }
}

// MARK: - Per-action settings

/// User choice for how the converter renders its result: append the
/// conversion in parentheses (default) or replace the original measurement.
/// Stored per action ID so a duplicated action can differ.
enum UnitConversionSettings {
    private static func key(_ id: String) -> String { "drpaste.units.replaceMode.\(id)" }

    static func replaceMode(for id: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(id))   // default false = append
    }
    static func setReplaceMode(_ replace: Bool, for id: String) {
        UserDefaults.standard.set(replace, forKey: key(id))
    }
}

// MARK: - ClipboardAction wrapper

struct UnitConversionAction: ClipboardAction {
    let id = "builtin.text.unit_conversion"
    let title = "Convert units"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Prose only — measurements live in sentences (text / rich text /
        // Markdown). A "5 km" inside a URL, JSON value, code literal or table
        // cell is data, not a measurement to rewrite, so those are excluded.
        guard item.semantic == .text || item.semantic == .richText
              || item.semantic == .markdown else { return false }
        guard let text = item.previewText, !text.isEmpty else { return false }
        // Quick screen: must contain at least one digit + alpha sequence.
        return text.contains { $0.isWholeNumber }
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let text = item.previewText else {
            return .failed(original: item, reason: "Convert units: empty text.", recovery: nil)
        }
        let mode: UnitConversion.OutputMode =
            UnitConversionSettings.replaceMode(for: id) ? .replace : .append
        let converted = await runOffMain {
            UnitConversion.convert(text, direction: .auto, mode: mode)
        }
        if converted == text {
            return .failed(original: item,
                           reason: "Convert units: no measurements found.",
                           recovery: nil)
        }
        return .preview(makeTextItem(converted, from: item))
    }
}
