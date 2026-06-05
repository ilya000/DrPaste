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
            let converted: String? = {
                switch direction {
                case .auto:
                    return convertMeasurement(match)
                case .toMetric:
                    return match.isMetric ? nil : convertMeasurement(match)
                case .toImperial:
                    return match.isMetric ? convertMeasurement(match) : nil
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
        let unit: Unit
        var isMetric: Bool { unit.isMetric }
    }

    enum Unit {
        // Length
        case mm, cm, m, km
        case inches, feet, yards, miles
        // Weight
        case grams, kilograms
        case ounces, pounds
        // Temperature
        case celsius, fahrenheit
        // Volume
        case milliliters, liters
        case fluidOunces, gallons, quarts, pints
        // Speed
        case kmh, mph
        // Area
        case squareMeters, squareFeet

        var isMetric: Bool {
            switch self {
            case .mm, .cm, .m, .km,
                 .grams, .kilograms,
                 .celsius,
                 .milliliters, .liters,
                 .kmh,
                 .squareMeters:
                return true
            default:
                return false
            }
        }
    }

    /// Regex over the input. Order matters: longer literals first
    /// so "feet" is matched before "ft" (the latter is a substring).
    private static let pattern: NSRegularExpression = {
        let units = [
            // compound foot+inch
            #"(\d+(?:[.,]\d+)?)\s*(?:ft|feet|')\s*(\d+(?:[.,]\d+)?)\s*(?:in|inch(?:es)?|")"#,
            #"(\d+(?:[.,]\d+)?)'(\d+(?:[.,]\d+)?)""#,
            // single value
            #"(-?\d+(?:[.,]\d+)?)\s*°?\s*(km/h|mph|°?C|°?F|kg|lb|lbs|oz|fl\s*oz|gal|qt|pt|m²|ft²|km|cm|mm|m\b|ft|feet|inches|inch|in\b|yd|yards|yard|mi|miles|mile|g|L|mL|ml)\b"#
        ]
        let combined = "(?:" + units.joined(separator: "|") + ")"
        return try! NSRegularExpression(pattern: combined,
                                        options: [.caseInsensitive])
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
        let lower = chunk.lowercased()
        // Compound foot+inch
        if let compound = parseCompoundFeetInches(lower) {
            return Match(range: range, value: compound, unit: .feet)
        }
        // Single value + unit
        // Extract leading number.
        let scalar = parseLeadingDouble(chunk)
        guard let value = scalar.value else { return nil }
        let rest = chunk
            .dropFirst(scalar.consumed)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "°", with: "")
        guard let unit = parseUnit(rest) else { return nil }
        return Match(range: range, value: value, unit: unit)
    }

    private static func parseCompoundFeetInches(_ s: String) -> Double? {
        // Patterns covered:
        //   "6 ft 7 in" / "6 feet 7 inches" / "6'7""
        let patterns = [
            #"^(\d+(?:[.,]\d+)?)\s*(?:ft|feet|')\s*(\d+(?:[.,]\d+)?)\s*(?:in|inch(?:es)?|"?)$"#,
            #"^(\d+(?:[.,]\d+)?)'(\d+(?:[.,]\d+)?)""?$"#
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

    private static func parseLeadingDouble(_ s: String) -> (value: Double?, consumed: Int) {
        var consumed = 0
        var buf = ""
        for ch in s {
            if ch.isWholeNumber || ch == "." || ch == "," || (ch == "-" && buf.isEmpty) {
                buf.append(ch == "," ? "." : ch)
                consumed += 1
            } else {
                break
            }
        }
        return (Double(buf), consumed)
    }

    private static func parseUnit(_ s: String) -> Unit? {
        // Normalize whitespace away
        let t = s.replacingOccurrences(of: " ", with: "")
        switch t {
        case "mm": return .mm
        case "cm": return .cm
        case "m":  return .m
        case "km": return .km
        case "in", "inch", "inches", "\"": return .inches
        case "ft", "feet", "foot", "'":    return .feet
        case "yd", "yard", "yards":        return .yards
        case "mi", "mile", "miles":        return .miles
        case "g":  return .grams
        case "kg": return .kilograms
        case "oz": return .ounces
        case "lb", "lbs": return .pounds
        case "c", "celsius": return .celsius
        case "f", "fahrenheit": return .fahrenheit
        case "ml": return .milliliters
        case "l":  return .liters
        case "floz", "fl oz", "fluidounces": return .fluidOunces
        case "gal", "gallon", "gallons": return .gallons
        case "qt", "quart", "quarts": return .quarts
        case "pt", "pint", "pints":   return .pints
        case "km/h", "kmh": return .kmh
        case "mph":         return .mph
        case "m²", "m2":    return .squareMeters
        case "ft²", "ft2":  return .squareFeet
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
        // Speed
        case .kmh: return String(format: "%.1f mph", m.value / 1.609344)
        case .mph: return String(format: "%.1f km/h", m.value * 1.609344)
        // Area: SI base = m²
        case .squareMeters: return String(format: "%.1f ft²", m.value * 10.7639)
        case .squareFeet:   return String(format: "%.1f m²", m.value * 0.092903)
        }
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
                // Choose mm / cm / m / km by magnitude.
                let absV = abs(siValue)
                if absV < 0.01 { return String(format: "%.1f mm", siValue * 1000) }
                if absV < 1    { return String(format: "%.1f cm", siValue * 100) }
                if absV < 1000 { return String(format: "%.1f m",  siValue) }
                return String(format: "%.1f km", siValue / 1000)
            } else {
                // m → imperial. Choose in / ft / mi by magnitude.
                let inches = siValue / 0.0254
                let absV = abs(siValue)
                if absV < 0.3 { return String(format: "%.1f in", inches) }
                if absV < 1000 { return String(format: "%.1f ft", inches / 12) }
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
                return String(format: "%.2f gal", siValue / 3.78541)
            }
        }
    }
}

// MARK: - ClipboardAction wrapper

struct UnitConversionAction: ClipboardAction {
    let id = "builtin.unit_conversion"
    let title = "Convert units"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard item.semantic == .text || item.semantic == .url
              || item.semantic == .code || item.semantic == .markdown else { return false }
        guard let text = item.previewText, !text.isEmpty else { return false }
        // Quick screen: must contain at least one digit + alpha sequence.
        return text.contains { $0.isWholeNumber }
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let text = item.previewText else {
            return .failed(original: item, reason: "Convert units: empty text.", recovery: nil)
        }
        let converted = await runOffMain {
            UnitConversion.convert(text, direction: .auto, mode: .append)
        }
        if converted == text {
            return .failed(original: item,
                           reason: "Convert units: no measurements found.",
                           recovery: nil)
        }
        return .preview(makeTextItem(converted, from: item))
    }
}
