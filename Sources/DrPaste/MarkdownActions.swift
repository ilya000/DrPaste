//
//  MarkdownActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//

import Foundation

struct MarkdownToPlainAction: ClipboardAction {
    let id = "builtin.md_to_plain"; let title = "Markdown → plain"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.markdown)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        var s = item.previewText ?? ""
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
        return .preview(makeTextItem(s, from: item))
    }
}

struct MarkdownExtractHeadingsAction: ClipboardAction {
    let id = "builtin.md_headings"; let title = "Extract headings"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.markdown)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let lines = (item.previewText ?? "").split(separator: "\n").map(String.init)
        let headings = lines.filter { $0.hasPrefix("#") && $0.contains(" ") }
        guard !headings.isEmpty else {
            return .failed(original: item, reason: "No headings found", recovery: nil)
        }
        return .preview(makeTextItem(headings.joined(separator: "\n"), from: item))
    }
}

struct MarkdownExtractLinksAction: ClipboardAction {
    let id = "builtin.md_links"; let title = "Extract links"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.markdown)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let s = item.previewText ?? ""
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return .preview(item) }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        let matches = regex.matches(in: s, range: range)
        let urls = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 2), in: s) else { return nil }
            return String(s[r])
        }
        guard !urls.isEmpty else {
            return .failed(original: item, reason: "No links found", recovery: nil)
        }
        return .preview(makeTextItem(urls.joined(separator: "\n"), from: item))
    }
}

enum MarkdownActionsPack {
    static var all: [ClipboardAction] {
        [
            MarkdownToPlainAction(),
            MarkdownExtractHeadingsAction(),
            MarkdownExtractLinksAction()
        ]
    }
}
