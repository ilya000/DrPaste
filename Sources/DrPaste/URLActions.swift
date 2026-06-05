//
//  URLActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//

import Foundation
import AppKit

// URLStripTrackingAction migrated to DefaultTransformationSeed as
// `builtin.url_strip_tracking` using the urlStripTracking engine — the
// tracking-parameter allowlist now lives in TransformationRuntime.

struct URLJustDomainAction: ClipboardAction {
    let id = "builtin.url.extract_domain"
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
    let id = "builtin.url.to_md_link"
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
    let id = "builtin.url.to_html_link"
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

// MARK: - URL preview card (#A22)

/// Fetch a URL's head section, extract Open Graph / `<title>` metadata,
/// and emit a rich-text card with title (bold) + description + URL +
/// optional og:image. Uses AIHTTP.session timeouts so a slow or
/// unreachable host fails in 20 s instead of the URLSession default
/// 60 s. No JS execution — single GET, regex over the head.
///
/// Domain-specific enhancements (Twitter, GitHub, YouTube) deferred —
/// the og:image / og:description fallback chain handles 90% of the
/// modern web well enough for the "I want to see what I just copied"
/// case. Slack / Notion paste-target compatibility is best-effort —
/// the rich-text representation degrades gracefully to the URL text.
struct URLPreviewCardAction: ClipboardAction {
    let id = "builtin.url.preview_card"
    let title = "Preview card"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // .url and .text both qualify — a text clip that happens to be
        // a single URL is a common shape (paste from address bar with
        // surrounding whitespace).
        context.contains(.url)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let raw = (item.previewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .failed(original: item,
                           reason: "Preview card: not a http(s) URL.",
                           recovery: nil)
        }
        // Fetch HEAD section — most servers ignore the Range header and
        // send the full document, which is fine; we only parse the head.
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("DrPaste/" + AppBrand.version + " (+macOS preview card)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, */*", forHTTPHeaderField: "Accept")
        let session = AIHTTP.session
        let bytes: Data
        do {
            let (data, response) = try await session.data(for: request)
            // Reject non-2xx — error pages don't have useful OG.
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failed(original: item,
                               reason: "Preview card: HTTP \(http.statusCode).",
                               recovery: nil)
            }
            bytes = data
        } catch {
            return .failed(original: item,
                           reason: "Preview card: \(error.localizedDescription)",
                           recovery: nil)
        }
        guard let html = String(data: bytes, encoding: .utf8)
                      ?? String(data: bytes, encoding: .isoLatin1) else {
            return .failed(original: item,
                           reason: "Preview card: couldn't decode response.",
                           recovery: nil)
        }
        let meta = URLPreviewParser.parse(html: html)
        let title = meta.title ?? URL(string: raw)?.host ?? raw
        let description = meta.description
        let card = buildCard(title: title,
                             description: description,
                             url: raw,
                             ogImageURL: meta.image)
        return .preview(makeRichTextItem(card, from: item))
    }

    /// Build the NSAttributedString card. Title bold, description
    /// regular, URL as a link. No image attachment in v1 — image
    /// fetch + embedding doubles failure surface and slows the
    /// action; deferred until user feedback asks for it.
    private func buildCard(title: String,
                           description: String?,
                           url: String,
                           ogImageURL: String?) -> NSAttributedString {
        let body = NSMutableAttributedString()
        let titleAttr = NSAttributedString(string: title + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ])
        body.append(titleAttr)
        if let desc = description, !desc.isEmpty {
            let trimmed = desc.count > 200
                ? String(desc.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                : desc
            body.append(NSAttributedString(string: trimmed + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        body.append(NSAttributedString(string: url, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .link: url
        ]))
        // og:image url survives as a trailing line so downstream consumers
        // (export, archive, future image-embed flow) can find it without
        // re-fetching the source page.
        if let img = ogImageURL, !img.isEmpty {
            body.append(NSAttributedString(string: "\n\(img)", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]))
        }
        return body
    }
}

/// Tiny regex-based head-section parser. NSXMLParser is overkill for
/// malformed real-world HTML; the head section is short and we only
/// need a fixed list of tags. Returns nil for any field we couldn't
/// find — caller falls back to host / URL as the title.
enum URLPreviewParser {

    struct Metadata {
        var title: String?
        var description: String?
        var image: String?
    }

    static func parse(html: String) -> Metadata {
        // Only scan the head section to bound the work — many marketing
        // pages drop the same string content into the body that they
        // duplicated in OG tags, and grepping the body produces
        // misleading false-positive matches.
        let scope: String = {
            if let end = html.range(of: "</head>", options: .caseInsensitive) {
                return String(html[..<end.upperBound])
            }
            // Big head sections do exist (e.g. Google sites embed entire
            // analytics blobs); cap at 200 KB to keep regex bounded.
            return String(html.prefix(200_000))
        }()
        var meta = Metadata()
        meta.title = firstMatch(in: scope,
                                pattern: "<title[^>]*>([^<]+)</title>")
        // og: tags first; fall back to standard meta description.
        meta.title = ogContent(in: scope, name: "og:title") ?? meta.title
        meta.description = ogContent(in: scope, name: "og:description")
                        ?? metaContent(in: scope, name: "description")
        meta.image = ogContent(in: scope, name: "og:image")
        // HTML-entity decode the title / description so a page that
        // ships "AT&amp;T" doesn't paste as literal "AT&amp;T".
        meta.title = meta.title.map(decodeEntities)
        meta.description = meta.description.map(decodeEntities)
        return meta
    }

    /// First regex capture group, or nil. Trims whitespace.
    private static func firstMatch(in source: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: source,
                                    range: NSRange(location: 0, length: source.utf16.count)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: source) else { return nil }
        return String(source[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Look up `<meta property="og:NAME" content="VALUE">`. Handles
    /// double or single quotes, attribute order swap, and incidental
    /// whitespace.
    private static func ogContent(in source: String, name: String) -> String? {
        // Two forms: property-first, content-first.
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let p1 = "<meta[^>]+property=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']*)[\"']"
        let p2 = "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]*property=[\"']\(escaped)[\"']"
        return firstMatch(in: source, pattern: p1)
            ?? firstMatch(in: source, pattern: p2)
    }

    /// Look up `<meta name="description" content="…">` — the legacy
    /// non-OG description tag still common on older sites.
    private static func metaContent(in source: String, name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let p = "<meta[^>]+name=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']*)[\"']"
        return firstMatch(in: source, pattern: p)
    }

    /// Cheap HTML-entity decoder for the common entities we'll actually
    /// encounter in og: content (`&amp; &lt; &gt; &quot; &apos; &#NNN;`).
    /// Full HTML5 entity table is overkill for a preview card.
    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let pairs: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&hellip;", "…"), ("&laquo;", "«"), ("&raquo;", "»")
        ]
        for (k, v) in pairs { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }
}

enum URLActionsPack {
    static var all: [ClipboardAction] {
        [
            URLJustDomainAction(),
            URLMarkdownLinkAction(), URLHTMLLinkAction(),
            URLPreviewCardAction()                            // #A22
        ]
    }
}
