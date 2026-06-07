//
//  JSONActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  JSON-specific actions that cannot be cleanly expressed as a single
//  parameterized engine.
//
//  Pretty / Minify / Extract keys migrated to DefaultTransformationSeed as
//  jsonFormat engine entries (`builtin.json_pretty`, `builtin.json_minify`,
//  `builtin.json_keys`). Flatten and Remove-nulls remain hardcoded — they
//  produce structurally rewritten JSON and would not benefit from a
//  generalized engine.
//

import Foundation

struct JSONFlattenAction: ClipboardAction {
    let id = "builtin.json.flatten"; let title = "Flatten"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.json)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let data = (item.previewText ?? "").data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) else {
            return .failed(original: item, reason: "Couldn't parse as JSON", recovery: nil)
        }
        // Codex sweep — build a real dictionary and let JSONSerialization do the
        // escaping. The old hand-rolled encoder did `"\(s)"` for strings and
        // `"\(v)"` for everything else, so any key/value containing a quote,
        // backslash or newline produced INVALID JSON, and booleans serialised as
        // 1/0 and arrays as Swift's `[1, 2]` description.
        var flatDict: [String: Any] = [:]
        for (k, v) in flatten(obj, prefix: "") { flatDict[k] = v }
        guard JSONSerialization.isValidJSONObject(flatDict),
              let out = try? JSONSerialization.data(withJSONObject: flatDict,
                                                    options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: out, encoding: .utf8) else {
            return .failed(original: item, reason: "Couldn't serialize flattened JSON", recovery: nil)
        }
        return .preview(makeTextItem(result, from: item))
    }
    private func flatten(_ obj: Any, prefix: String) -> [(key: String, value: Any)] {
        if let dict = obj as? [String: Any] {
            return dict.flatMap { k, v in
                flatten(v, prefix: prefix.isEmpty ? k : "\(prefix).\(k)")
            }
        }
        return [(prefix, obj)]
    }
}

struct JSONRemoveNullsAction: ClipboardAction {
    let id = "builtin.json.remove_nulls"; let title = "Remove null values"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.json)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let data = (item.previewText ?? "").data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) else {
            return .failed(original: item, reason: "Couldn't parse as JSON", recovery: nil)
        }
        let cleaned = removeNulls(obj)
        guard let pretty = try? JSONSerialization.data(withJSONObject: cleaned,
                                                       options: [.prettyPrinted, .sortedKeys]) else {
            return .preview(item)
        }
        return .preview(makeTextItem(String(data: pretty, encoding: .utf8) ?? "", from: item))
    }
    private func removeNulls(_ obj: Any) -> Any {
        if let dict = obj as? [String: Any] {
            return dict.compactMapValues { $0 is NSNull ? nil : removeNulls($0) }
        }
        if let arr = obj as? [Any] {
            return arr.compactMap { $0 is NSNull ? nil : removeNulls($0) }
        }
        return obj
    }
}

enum JSONActionsPack {
    static var all: [ClipboardAction] {
        [JSONFlattenAction(), JSONRemoveNullsAction()]
    }
}
