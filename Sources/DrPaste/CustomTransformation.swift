//
//  CustomTransformation.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Engine architecture (light) — Правка #7 итерации 2.
//  Не ломаю built-ins (риск слишком велик) — добавляю отдельный механизм для
//  user-defined transformations. Пользователь может создать N инстансов
//  regex_replace / find_replace / prepend / append / wrap / line_filter —
//  каждая со своими параметрами.
//

import Foundation

// MARK: - Engine IDs

enum TransformationEngine: String, Codable, CaseIterable, Identifiable {
    case regexReplace = "regex_replace"
    case findReplace  = "find_replace"
    case prepend      = "prepend"
    case append       = "append"
    case wrap         = "wrap"
    case lineFilter   = "line_filter"
    case caseChange   = "case_change"      // upper / lower / title / sentence
    case sortLines    = "sort_lines"
    case uniqueLines  = "unique_lines"
    case jsonFormat   = "json_format"      // pretty / minify / extract keys

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regexReplace: return "Regex replace"
        case .findReplace:  return "Find and replace"
        case .prepend:      return "Prepend text"
        case .append:       return "Append text"
        case .wrap:         return "Wrap with prefix/suffix"
        case .lineFilter:   return "Filter lines"
        case .caseChange:   return "Change case"
        case .sortLines:    return "Sort lines"
        case .uniqueLines:  return "Unique lines"
        case .jsonFormat:   return "Format JSON"
        }
    }

    var iconName: String {
        switch self {
        case .regexReplace: return "function"
        case .findReplace:  return "magnifyingglass"
        case .prepend:      return "text.append"
        case .append:       return "text.insert"
        case .wrap:         return "text.quote"
        case .lineFilter:   return "line.horizontal.3.decrease"
        case .caseChange:   return "textformat"
        case .sortLines:    return "arrow.up.arrow.down"
        case .uniqueLines:  return "line.3.horizontal.decrease.circle"
        case .jsonFormat:   return "curlybraces"
        }
    }

    var description: String {
        switch self {
        case .regexReplace:
            return "Replace text matching a regular expression pattern with replacement string. Supports capture groups ($1, $2)."
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
            return "Format JSON: pretty-print, minify, or extract top-level keys as a list."
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

/// ClipboardAction wrapper для CustomTransformationDescriptor.
/// Создаётся в ActionRegistry.rebuildCustomTransformations().
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
        case .regexReplace:
            return try regexReplace(input, params: params)
        case .findReplace:
            return findReplace(input, params: params)
        case .prepend:
            return (params["text"] ?? "") + input
        case .append:
            return input + (params["text"] ?? "")
        case .wrap:
            return (params["prefix"] ?? "") + input + (params["suffix"] ?? "")
        case .lineFilter:
            return try lineFilter(input, params: params)
        case .caseChange:
            return caseChange(input, params: params)
        case .sortLines:
            return sortLines(input, params: params)
        case .uniqueLines:
            return uniqueLines(input)
        case .jsonFormat:
            return jsonFormat(input, params: params)
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
        default: // pretty
            if let out = try? JSONSerialization.data(withJSONObject: json,
                                                      options: [.prettyPrinted, .sortedKeys]) {
                return String(data: out, encoding: .utf8) ?? input
            }
        }
        return input
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
}
