//
//  CustomTransformation.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Engine architecture for transformation actions. Originally introduced for
//  user-defined transformations; now also hosts the bundled built-ins seeded
//  via DefaultTransformationSeed (UPPERCASE, sort lines, base64, slugify,
//  json pretty, markdown extraction, etc.). The engine + descriptor pair lets
//  users rename, retitle, reorder, change parameters, or fully delete any
//  transformation — built-in or user-created — through a single edit surface.
//

import Foundation

// MARK: - Engine IDs

enum TransformationEngine: String, Codable, CaseIterable, Identifiable {
    case regexReplace      = "regex_replace"
    case findReplace       = "find_replace"
    case prepend           = "prepend"
    case append            = "append"
    case wrap              = "wrap"
    case lineFilter        = "line_filter"
    case caseChange        = "case_change"          // upper / lower / title / sentence
    case sortLines         = "sort_lines"           // asc / desc, case-insensitive flag
    case uniqueLines       = "unique_lines"
    case jsonFormat        = "json_format"          // pretty / minify / extractKeys / extractKeysRecursive
    case trim              = "trim"                 // strip each line + outer whitespace
    case camelCase         = "camel_case"
    case snakeCase         = "snake_case"
    case kebabCase         = "kebab_case"
    case base64Encode      = "base64_encode"
    case base64Decode      = "base64_decode"
    case urlPercentEncode  = "url_percent_encode"
    case urlPercentDecode  = "url_percent_decode"
    case slugify           = "slugify"
    case wordCount         = "word_count"
    case mdToPlain         = "md_to_plain"
    case mdExtractHeadings = "md_extract_headings"
    case mdExtractLinks    = "md_extract_links"
    case urlStripTracking  = "url_strip_tracking"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regexReplace:      return "Regex replace"
        case .findReplace:       return "Find and replace"
        case .prepend:           return "Prepend text"
        case .append:            return "Append text"
        case .wrap:              return "Wrap with prefix/suffix"
        case .lineFilter:        return "Filter lines"
        case .caseChange:        return "Change case"
        case .sortLines:         return "Sort lines"
        case .uniqueLines:       return "Unique lines"
        case .jsonFormat:        return "Format JSON"
        case .trim:              return "Trim whitespace"
        case .camelCase:         return "camelCase"
        case .snakeCase:         return "snake_case"
        case .kebabCase:         return "kebab-case"
        case .base64Encode:      return "Base64 encode"
        case .base64Decode:      return "Base64 decode"
        case .urlPercentEncode:  return "URL percent-encode"
        case .urlPercentDecode:  return "URL percent-decode"
        case .slugify:           return "Slugify"
        case .wordCount:         return "Word / char count"
        case .mdToPlain:         return "Markdown → plain"
        case .mdExtractHeadings: return "Extract Markdown headings"
        case .mdExtractLinks:    return "Extract Markdown links"
        case .urlStripTracking:  return "Strip URL tracking params"
        }
    }

    var iconName: String {
        switch self {
        case .regexReplace:      return "function"
        case .findReplace:       return "magnifyingglass"
        case .prepend:           return "text.append"
        case .append:            return "text.insert"
        case .wrap:              return "text.quote"
        case .lineFilter:        return "line.horizontal.3.decrease"
        case .caseChange:        return "textformat"
        case .sortLines:         return "arrow.up.arrow.down"
        case .uniqueLines:       return "line.3.horizontal.decrease.circle"
        case .jsonFormat:        return "curlybraces"
        case .trim:              return "scissors"
        case .camelCase:         return "textformat.alt"
        case .snakeCase:         return "textformat.alt"
        case .kebabCase:         return "textformat.alt"
        case .base64Encode:      return "lock.shield"
        case .base64Decode:      return "lock.open"
        case .urlPercentEncode:  return "percent"
        case .urlPercentDecode:  return "percent"
        case .slugify:           return "link"
        case .wordCount:         return "number"
        case .mdToPlain:         return "doc.plaintext"
        case .mdExtractHeadings: return "list.bullet.indent"
        case .mdExtractLinks:    return "link"
        case .urlStripTracking:  return "shield.lefthalf.filled"
        }
    }

    var description: String {
        switch self {
        case .regexReplace:
            return "Replace text matching a regular expression pattern with a replacement string. Supports capture groups ($1, $2)."
        case .findReplace:
            return "Replace occurrences of a literal string with another. Case-sensitive by default."
        case .prepend:
            return "Add text at the beginning of the clipboard content."
        case .append:
            return "Add text at the end of the clipboard content."
        case .wrap:
            return "Surround the text with a prefix and suffix (e.g. quotes, brackets, code fences)."
        case .lineFilter:
            return "Keep or remove lines matching a pattern."
        case .caseChange:
            return "Change text case: upper, lower, Title Case, or Sentence case."
        case .sortLines:
            return "Sort lines alphabetically, ascending or descending. Optional case-insensitive."
        case .uniqueLines:
            return "Remove duplicate lines while preserving order."
        case .jsonFormat:
            return "Format JSON: pretty-print, minify, extract top-level keys, or extract every key recursively."
        case .trim:
            return "Strip whitespace from each line and from the start/end of the text."
        case .camelCase:
            return "Convert text to camelCase by joining word boundaries and lowercasing the first word."
        case .snakeCase:
            return "Convert text to snake_case by joining word boundaries with underscores."
        case .kebabCase:
            return "Convert text to kebab-case by joining word boundaries with hyphens."
        case .base64Encode:
            return "Encode the UTF-8 representation of the text as a Base64 string."
        case .base64Decode:
            return "Decode a Base64 string back to UTF-8 text."
        case .urlPercentEncode:
            return "Percent-encode characters that are not safe in URL paths."
        case .urlPercentDecode:
            return "Reverse percent-encoding in a URL or URL-encoded fragment."
        case .slugify:
            return "Produce a URL-safe slug: lowercase, ASCII transliteration, hyphen-separated words."
        case .wordCount:
            return "Replace the content with a short summary: N words, N characters, N lines."
        case .mdToPlain:
            return "Strip Markdown markers (headings, bold, italic, code, links) and produce plain text."
        case .mdExtractHeadings:
            return "Keep only lines that start with one or more #, in source order."
        case .mdExtractLinks:
            return "Extract every URL referenced by an inline Markdown link, one per line."
        case .urlStripTracking:
            return "Drop common tracking query parameters (utm_*, fbclid, gclid, igshid, ref, _ga, etc.)."
        }
    }

    var defaultParameters: [String: String] {
        switch self {
        case .regexReplace: return ["pattern": "", "replacement": "", "caseInsensitive": "false"]
        case .findReplace:  return ["find": "", "replace": "", "caseInsensitive": "false"]
        case .prepend:      return ["text": ""]
        case .append:       return ["text": ""]
        case .wrap:         return ["prefix": "", "suffix": ""]
        case .lineFilter:   return ["pattern": "", "mode": "keep"]
        case .caseChange:   return ["case": "upper"]
        case .sortLines:    return ["direction": "asc", "caseInsensitive": "false"]
        case .uniqueLines:  return [:]
        case .jsonFormat:   return ["operation": "pretty"]
        case .trim,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking:
            return [:]
        }
    }

    /// True if this engine is a useful composable building block when the user
    /// creates a brand-new custom transformation. False for parameter-less
    /// "recipe" engines that exist solely to back a specific bundled built-in
    /// (camelCase, slugify, Markdown extract, Strip URL tracking, etc.) — they
    /// already appear as ready-to-use actions in the Actions list, so showing
    /// them again in the engine picker would just clutter the menu.
    ///
    /// Note: engines flagged `false` still run normally and remain editable
    /// when the user opens an existing built-in for editing — only the engine
    /// **picker for new transformations** filters by this flag.
    var userPickable: Bool {
        switch self {
        case .regexReplace, .findReplace, .prepend, .append, .wrap, .lineFilter,
             .caseChange, .sortLines, .uniqueLines, .jsonFormat:
            return true
        case .trim,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking:
            return false
        }
    }
}

// MARK: - Descriptor

struct CustomTransformationDescriptor: Codable, Identifiable, Equatable {
    var id: String                           // "user.transform.<slug>"
    var title: String
    var engineID: String                     // TransformationEngine.rawValue
    var parameters: [String: String]
    var applicableTypes: [String]            // SemanticKind.rawValue list
    var enabled: Bool = true

    var engine: TransformationEngine? {
        TransformationEngine(rawValue: engineID)
    }
}

// MARK: - Runtime action

/// ClipboardAction wrapper for a CustomTransformationDescriptor.
/// Instantiated by ActionRegistry.rebuildCustomTransformations().
struct CustomTransformationAction: ClipboardAction {
    let id: String
    let title: String
    let isLocal: Bool = true
    let descriptor: CustomTransformationDescriptor
    let applicableSet: Set<SemanticKind>

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        applicableSet.contains(item.semantic) || context.contains(.plain)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let engine = descriptor.engine else {
            return .failed(original: item, reason: "Unknown engine: \(descriptor.engineID)", recovery: nil)
        }
        let input = item.previewText ?? ""
        do {
            let result = try TransformationRuntime.apply(engine: engine,
                                                          input: input,
                                                          params: descriptor.parameters)
            return .preview(makeTextItem(result, from: item))
        } catch let TransformationError.invalidRegex(msg) {
            return .failed(original: item, reason: "Invalid regex: \(msg)", recovery: nil)
        } catch {
            return .failed(original: item, reason: error.localizedDescription, recovery: nil)
        }
    }
}

// MARK: - Runtime

enum TransformationError: Error {
    case invalidRegex(String)
    case missingParameter(String)
}

enum TransformationRuntime {
    static func apply(engine: TransformationEngine,
                      input: String,
                      params: [String: String]) throws -> String {
        switch engine {
        case .regexReplace:      return try regexReplace(input, params: params)
        case .findReplace:       return findReplace(input, params: params)
        case .prepend:           return (params["text"] ?? "") + input
        case .append:            return input + (params["text"] ?? "")
        case .wrap:              return (params["prefix"] ?? "") + input + (params["suffix"] ?? "")
        case .lineFilter:        return try lineFilter(input, params: params)
        case .caseChange:        return caseChange(input, params: params)
        case .sortLines:         return sortLines(input, params: params)
        case .uniqueLines:       return uniqueLines(input)
        case .jsonFormat:        return jsonFormat(input, params: params)
        case .trim:              return trim(input)
        case .camelCase:         return camelCase(input)
        case .snakeCase:         return snakeCase(input)
        case .kebabCase:         return kebabCase(input)
        case .base64Encode:      return base64Encode(input)
        case .base64Decode:      return try base64Decode(input)
        case .urlPercentEncode:  return urlPercentEncode(input)
        case .urlPercentDecode:  return urlPercentDecode(input)
        case .slugify:           return slugify(input)
        case .wordCount:         return wordCount(input)
        case .mdToPlain:         return mdToPlain(input)
        case .mdExtractHeadings: return try mdExtractHeadings(input)
        case .mdExtractLinks:    return try mdExtractLinks(input)
        case .urlStripTracking:  return urlStripTracking(input)
        }
    }

    private static func caseChange(_ input: String, params: [String: String]) -> String {
        switch params["case"] ?? "upper" {
        case "upper": return input.uppercased()
        case "lower": return input.lowercased()
        case "title": return input.capitalized
        case "sentence":
            let lower = input.lowercased()
            guard let first = lower.first else { return lower }
            return first.uppercased() + lower.dropFirst()
        default: return input
        }
    }

    private static func sortLines(_ input: String, params: [String: String]) -> String {
        let direction = params["direction"] ?? "asc"
        let caseInsensitive = params["caseInsensitive"] == "true"
        let lines = input.components(separatedBy: "\n")
        let sorted = lines.sorted { a, b in
            let la = caseInsensitive ? a.lowercased() : a
            let lb = caseInsensitive ? b.lowercased() : b
            return direction == "desc" ? la > lb : la < lb
        }
        return sorted.joined(separator: "\n")
    }

    private static func uniqueLines(_ input: String) -> String {
        var seen = Set<String>()
        let lines = input.components(separatedBy: "\n")
        let unique = lines.filter { seen.insert($0).inserted }
        return unique.joined(separator: "\n")
    }

    private static func jsonFormat(_ input: String, params: [String: String]) -> String {
        let op = params["operation"] ?? "pretty"
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data,
                                                            options: [.allowFragments]) else {
            return input
        }
        switch op {
        case "minify":
            if let out = try? JSONSerialization.data(withJSONObject: json, options: []) {
                return String(data: out, encoding: .utf8) ?? input
            }
        case "extractKeys":
            if let dict = json as? [String: Any] {
                return dict.keys.sorted().joined(separator: "\n")
            }
            return ""
        case "extractKeysRecursive":
            var keys = Set<String>()
            collectJSONKeys(into: &keys, from: json)
            return keys.sorted().joined(separator: "\n")
        default: // pretty
            if let out = try? JSONSerialization.data(withJSONObject: json,
                                                      options: [.prettyPrinted, .sortedKeys]) {
                return String(data: out, encoding: .utf8) ?? input
            }
        }
        return input
    }

    /// Recursive walker used by jsonFormat operation = extractKeysRecursive.
    private static func collectJSONKeys(into keys: inout Set<String>, from obj: Any) {
        if let dict = obj as? [String: Any] {
            for (k, v) in dict { keys.insert(k); collectJSONKeys(into: &keys, from: v) }
        } else if let arr = obj as? [Any] {
            for v in arr { collectJSONKeys(into: &keys, from: v) }
        }
    }

    private static func regexReplace(_ input: String, params: [String: String]) throws -> String {
        let pattern = params["pattern"] ?? ""
        let replacement = params["replacement"] ?? ""
        guard !pattern.isEmpty else { return input }
        var options: NSRegularExpression.Options = []
        if params["caseInsensitive"] == "true" { options.insert(.caseInsensitive) }
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            let range = NSRange(input.startIndex..., in: input)
            return regex.stringByReplacingMatches(in: input, options: [],
                                                  range: range, withTemplate: replacement)
        } catch {
            throw TransformationError.invalidRegex(error.localizedDescription)
        }
    }

    private static func findReplace(_ input: String, params: [String: String]) -> String {
        let find = params["find"] ?? ""
        let replace = params["replace"] ?? ""
        guard !find.isEmpty else { return input }
        if params["caseInsensitive"] == "true" {
            return input.replacingOccurrences(of: find, with: replace,
                                              options: [.caseInsensitive])
        }
        return input.replacingOccurrences(of: find, with: replace)
    }

    private static func lineFilter(_ input: String, params: [String: String]) throws -> String {
        let pattern = params["pattern"] ?? ""
        let mode = params["mode"] ?? "keep"
        guard !pattern.isEmpty else { return input }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw TransformationError.invalidRegex(error.localizedDescription)
        }
        let lines = input.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.firstMatch(in: line, options: [], range: range) != nil
            return mode == "keep" ? matches : !matches
        }
        return filtered.joined(separator: "\n")
    }

    // MARK: - New parameter-less engines (seeded as builtin.* transformations)

    private static func trim(_ input: String) -> String {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func camelCase(_ input: String) -> String {
        let parts = input.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let first = parts.first?.lowercased() else { return "" }
        let rest = parts.dropFirst().map { $0.lowercased().capitalized }
        return first + rest.joined()
    }

    private static func snakeCase(_ input: String) -> String {
        input.split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
            .joined(separator: "_")
    }

    private static func kebabCase(_ input: String) -> String {
        input.split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
            .joined(separator: "-")
    }

    private static func base64Encode(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return input }
        return data.base64EncodedString()
    }

    private static func base64Decode(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed),
              let decoded = String(data: data, encoding: .utf8) else {
            throw TransformationError.missingParameter("input is not valid Base64")
        }
        return decoded
    }

    private static func urlPercentEncode(_ input: String) -> String {
        input.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input
    }

    private static func urlPercentDecode(_ input: String) -> String {
        input.removingPercentEncoding ?? input
    }

    private static func slugify(_ input: String) -> String {
        let lower = input.lowercased()
        let latin = lower.applyingTransform(.toLatin, reverse: false) ?? lower
        let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return stripped.split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
    }

    private static func wordCount(_ input: String) -> String {
        let words = input.split { $0.isWhitespace }.count
        let chars = input.count
        let lines = input.split(separator: "\n").count
        return "\(words) words, \(chars) characters, \(lines) lines"
    }

    private static func mdToPlain(_ input: String) -> String {
        var s = input
        let patterns: [(String, String)] = [
            (#"^#{1,6}\s+"#, ""),
            (#"\*\*(.+?)\*\*"#, "$1"),
            (#"\*(.+?)\*"#, "$1"),
            (#"`([^`]+)`"#, "$1"),
            (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),
            (#"^[-*+]\s+"#, "• ")
        ]
        for (pat, rep) in patterns {
            s = s.replacingOccurrences(of: pat, with: rep, options: .regularExpression)
        }
        return s
    }

    private static func mdExtractHeadings(_ input: String) throws -> String {
        let lines = input.split(separator: "\n").map(String.init)
        let headings = lines.filter { $0.hasPrefix("#") && $0.contains(" ") }
        if headings.isEmpty {
            throw TransformationError.missingParameter("no Markdown headings found")
        }
        return headings.joined(separator: "\n")
    }

    private static func mdExtractLinks(_ input: String) throws -> String {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        let urls = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 2), in: input) else { return nil }
            return String(input[r])
        }
        if urls.isEmpty {
            throw TransformationError.missingParameter("no Markdown links found")
        }
        return urls.joined(separator: "\n")
    }

    /// Tracking parameter list mirrors the legacy URLStripTrackingAction whitelist.
    private static let urlTrackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "yclid", "mc_cid", "mc_eid", "igshid",
        "_ga", "_gl", "ref", "ref_src", "ref_url", "spm", "wt_mc",
        "vero_conv", "vero_id"
    ]

    private static func urlStripTracking(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmed) else { return input }
        if let q = comps.queryItems {
            comps.queryItems = q.filter { !urlTrackingParams.contains($0.name.lowercased()) }
            if comps.queryItems?.isEmpty == true { comps.queryItems = nil }
        }
        return comps.string ?? input
    }
}
