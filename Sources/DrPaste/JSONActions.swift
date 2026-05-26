//
//  JSONActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//

import Foundation

struct JSONPrettyAction: ClipboardAction {
    let id = "builtin.json_pretty"; let title = "Pretty JSON"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.json)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let data = (item.previewText ?? "").data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                       options: [.prettyPrinted, .sortedKeys]) else {
            return .failed(original: item, reason: "Couldn't parse as JSON", recovery: nil)
        }
        return .preview(makeTextItem(String(data: pretty, encoding: .utf8) ?? "", from: item))
    }
}

struct JSONMinifyAction: ClipboardAction {
    let id = "builtin.json_minify"; let title = "Minify JSON"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.json)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let data = (item.previewText ?? "").data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]),
              let mini = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            return .failed(original: item, reason: "Couldn't parse as JSON", recovery: nil)
        }
        return .preview(makeTextItem(String(data: mini, encoding: .utf8) ?? "", from: item))
    }
}

struct JSONExtractKeysAction: ClipboardAction {
    let id = "builtin.json_keys"; let title = "Extract keys"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.json)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let data = (item.previewText ?? "").data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) else {
            return .failed(original: item, reason: "Couldn't parse as JSON", recovery: nil)
        }
        var keys = Set<String>()
        collect(keys: &keys, from: obj)
        let sorted = keys.sorted().joined(separator: "\n")
        return .preview(makeTextItem(sorted, from: item))
    }
    private func collect(keys: inout Set<String>, from obj: Any) {
        if let dict = obj as? [String: Any] {
            for (k, v) in dict { keys.insert(k); collect(keys: &keys, from: v) }
        } else if let arr = obj as? [Any] {
            for v in arr { collect(keys: &keys, from: v) }
        }
    }
}

struct JSONFlattenAction: ClipboardAction {
    let id = "builtin.json_flatten"; let title = "Flatten"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.json)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let data = (item.previewText ?? "").data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) else {
            return .failed(original: item, reason: "Couldn't parse as JSON", recovery: nil)
        }
        let flat = flatten(obj, prefix: "")
        let json = flat.map { "\"\($0.key)\": \(encodeValue($0.value))" }.sorted()
        let result = "{\n  " + json.joined(separator: ",\n  ") + "\n}"
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
    private func encodeValue(_ v: Any) -> String {
        if let s = v as? String { return "\"\(s)\"" }
        if v is NSNull { return "null" }
        return "\(v)"
    }
}

struct JSONRemoveNullsAction: ClipboardAction {
    let id = "builtin.json_remove_nulls"; let title = "Remove null values"; let isLocal = true
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
        [
            JSONPrettyAction(), JSONMinifyAction(),
            JSONExtractKeysAction(), JSONFlattenAction(), JSONRemoveNullsAction()
        ]
    }
}
