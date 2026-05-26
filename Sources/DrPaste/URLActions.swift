//
//  URLActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//

import Foundation

struct URLStripTrackingAction: ClipboardAction {
    let id = "builtin.url_strip_tracking"
    let title = "Clean URL"
    let isLocal = true
    static let tracking: Set<String> = [
        "utm_source","utm_medium","utm_campaign","utm_term","utm_content",
        "fbclid","gclid","yclid","mc_cid","mc_eid","igshid",
        "_ga","_gl","ref","ref_src","ref_url","spm","wt_mc","vero_conv","vero_id"
    ]
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.url)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard var comps = URLComponents(string: (item.previewText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)) else { return .preview(item) }
        if let q = comps.queryItems {
            comps.queryItems = q.filter { !Self.tracking.contains($0.name.lowercased()) }
            if comps.queryItems?.isEmpty == true { comps.queryItems = nil }
        }
        return .preview(makeTextItem(comps.string ?? (item.previewText ?? ""), from: item))
    }
}

struct URLJustDomainAction: ClipboardAction {
    let id = "builtin.url_domain"
    let title = "Just domain"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.url)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let comps = URLComponents(string: (item.previewText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)), let host = comps.host else {
            return .preview(item)
        }
        return .preview(makeTextItem(host, from: item))
    }
}

struct URLMarkdownLinkAction: ClipboardAction {
    let id = "builtin.url_markdown_link"
    let title = "Markdown link"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.url)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let url = (item.previewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = URLComponents(string: url)?.host ?? url
        return .preview(makeTextItem("[\(label)](\(url))", from: item))
    }
}

struct URLHTMLLinkAction: ClipboardAction {
    let id = "builtin.url_html_link"
    let title = "HTML link"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.url)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let url = (item.previewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = URLComponents(string: url)?.host ?? url
        return .preview(makeTextItem("<a href=\"\(url)\">\(label)</a>", from: item))
    }
}

struct URLQueryParamsAction: ClipboardAction {
    let id = "builtin.url_query_params"
    let title = "Query params as table"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.url) && (item.previewText ?? "").contains("?")
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let comps = URLComponents(string: (item.previewText ?? "")),
              let queryItems = comps.queryItems else {
            return .failed(original: item, reason: "No query parameters", recovery: nil)
        }
        let lines = queryItems.map { "\($0.name)\t\($0.value ?? "")" }
        return .preview(makeTextItem(lines.joined(separator: "\n"), from: item))
    }
}

enum URLActionsPack {
    static var all: [ClipboardAction] {
        [
            URLStripTrackingAction(), URLJustDomainAction(),
            URLMarkdownLinkAction(), URLHTMLLinkAction(),
            URLQueryParamsAction()
        ]
    }
}
