//
//  URLActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//

import Foundation

// URLStripTrackingAction migrated to DefaultTransformationSeed as
// `builtin.url_strip_tracking` using the urlStripTracking engine — the
// tracking-parameter allowlist now lives in TransformationRuntime.

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

// URLQueryParamsAction (Query params as table) removed in 0.12.0 — debug-tool
// niche, no marketing weight.

enum URLActionsPack {
    static var all: [ClipboardAction] {
        [
            URLJustDomainAction(),
            URLMarkdownLinkAction(), URLHTMLLinkAction()
        ]
    }
}
