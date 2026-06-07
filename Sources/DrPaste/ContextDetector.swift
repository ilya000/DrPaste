//
//  ContextDetector.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Granular classification flag set used to filter applicable actions.
//  Complements SemanticKind (from ClipboardModel) with detection of special
//  cases: layoutWrong, mixedScript, multiline, and so on.
//

import Foundation

struct ContentContext: OptionSet, Hashable {
    let rawValue: Int

    static let plain        = ContentContext(rawValue: 1 << 0)
    static let richText     = ContentContext(rawValue: 1 << 1)
    static let url          = ContentContext(rawValue: 1 << 2)
    static let email        = ContentContext(rawValue: 1 << 3)
    static let json         = ContentContext(rawValue: 1 << 4)
    static let code         = ContentContext(rawValue: 1 << 5)
    static let markdown     = ContentContext(rawValue: 1 << 6)
    static let table        = ContentContext(rawValue: 1 << 7)
    static let multiline    = ContentContext(rawValue: 1 << 8)
    static let mixedScript  = ContentContext(rawValue: 1 << 9)
    static let layoutWrong  = ContentContext(rawValue: 1 << 10)
    static let image        = ContentContext(rawValue: 1 << 11)
    static let files        = ContentContext(rawValue: 1 << 12)
    static let pdf          = ContentContext(rawValue: 1 << 13)
    static let qrEligible   = ContentContext(rawValue: 1 << 14)  // text short enough to encode as QR

    // #A75 traits — cheap content signals computed eagerly, used to gate
    // action visibility ("Show this action when…"). All derived from
    // previewText; none require provenance or expensive detection.
    static let containsEmails   = ContentContext(rawValue: 1 << 15)  // ≥1 email address embedded
    static let containsURLs     = ContentContext(rawValue: 1 << 16)  // ≥1 http(s)/www link embedded
    static let containsCyrillic = ContentContext(rawValue: 1 << 17)  // any Cyrillic letter
    static let containsLatin    = ContentContext(rawValue: 1 << 18)  // any Latin letter
    static let uppercaseHeavy   = ContentContext(rawValue: 1 << 19)  // mostly UPPERCASE prose
    static let messySpacing     = ContentContext(rawValue: 1 << 20)  // tabs / NBSP / 2+ spaces
    static let wrappedLines     = ContentContext(rawValue: 1 << 21)  // hard-wrapped (PDF-style) lines
    static let fromOCR          = ContentContext(rawValue: 1 << 22)  // provenance: produced by OCR (stored tag)
    static let lowercaseHeavy   = ContentContext(rawValue: 1 << 23)  // no capitals at all (typed all-lowercase)
    static let fromMailApp      = ContentContext(rawValue: 1 << 24)  // copied from a mail app / webmail
    static let containsHTMLMarkup = ContentContext(rawValue: 1 << 25) // real HTML tags present
    static let fromChat         = ContentContext(rawValue: 1 << 26)  // copied from a chat / social app
    static let hasTrackingParams = ContentContext(rawValue: 1 << 27) // URL with utm_/fbclid/… params
    static let richHasImage     = ContentContext(rawValue: 1 << 28)  // rich text carrying ≥1 embedded image
}

extension ContentContext {
    /// Human-readable names of the flags currently set. DEBUG ONLY — used by
    /// the temporary HUD trait overlay so the detected signals are visible
    /// while testing trait gating. Not a user-facing API.
    var activeNames: [String] {
        let table: [(ContentContext, String)] = [
            (.plain, "plain"), (.richText, "rich"), (.url, "url"), (.email, "email"),
            (.json, "json"), (.code, "code"), (.markdown, "md"), (.table, "table"),
            (.image, "image"), (.files, "files"), (.pdf, "pdf"),
            (.multiline, "multiline"), (.mixedScript, "mixedScript"),
            (.layoutWrong, "layoutWrong"), (.qrEligible, "qrEligible"),
            (.containsEmails, "containsEmails"), (.containsURLs, "containsURLs"),
            (.containsCyrillic, "containsCyrillic"), (.containsLatin, "containsLatin"),
            (.uppercaseHeavy, "uppercaseHeavy"), (.lowercaseHeavy, "lowercaseHeavy"),
            (.messySpacing, "messySpacing"),
            (.wrappedLines, "wrappedLines"), (.fromOCR, "fromOCR"),
            (.fromMailApp, "fromMailApp"), (.containsHTMLMarkup, "containsHTMLMarkup"),
            (.fromChat, "fromChat"), (.hasTrackingParams, "hasTrackingParams"),
            (.richHasImage, "richHasImage")
        ]
        return table.compactMap { contains($0.0) ? $0.1 : nil }
    }
}

enum ContextDetector {

    /// Provenance tag stamped on clips produced by the OCR action, so a
    /// downstream "Clean OCR text" action can surface only for OCR output
    /// (#A75 kill-feature chain). Stored on the clip — cannot be recomputed.
    static let ocrProvenanceTag = "fromOCR"

    /// Heuristic: was this clip copied from an email context? Checks the
    /// capturing app's name / bundle id and the window title. Intentionally
    /// broad (per owner): any source whose name or window title merely contains
    /// "mail" counts, plus the common native + web clients. Lets email actions
    /// (Draft reply, Generate subject) surface on a copied email body even when
    /// no literal address is in the selection.
    static func looksLikeMailSource(_ item: ClipboardItem) -> Bool {
        let haystacks = [item.sourceAppName, item.sourceWindowTitle, item.sourceBundleID]
            .compactMap { $0?.lowercased() }
        guard !haystacks.isEmpty else { return false }
        // Substrings that strongly imply an email surface.
        let needles = [
            "mail", "outlook", "gmail", "inbox", "proton", "thunderbird",
            "fastmail", "spark", "airmail", "postbox", "hey.com", "missiveapp",
            "superhuman", "yahoo mail", "zoho mail", "tutanota"
        ]
        return haystacks.contains { hay in needles.contains { hay.contains($0) } }
    }

    /// Heuristic: was this clip copied from a chat / social-messaging app
    /// (native or web)? Used to surface playful styling (Unicode fancy fonts,
    /// UwU) only in a conversational context. Note: this is the *source* app —
    /// where the text was copied from, not where it will be pasted.
    static func looksLikeChatSource(_ item: ClipboardItem) -> Bool {
        let haystacks = [item.sourceAppName, item.sourceWindowTitle, item.sourceBundleID]
            .compactMap { $0?.lowercased() }
        guard !haystacks.isEmpty else { return false }
        // Apple Messages (generic word "messages" is risky, so match precisely).
        if haystacks.contains(where: { $0.contains("com.apple.mobilesms") || $0 == "messages" }) {
            return true
        }
        let needles = [
            "slack", "discord", "telegram", "whatsapp", "messenger", "instagram",
            "viber", "signal", "wechat", "microsoft teams", "skype", "facebook",
            "kakaotalk", "kakao", "threads", "mastodon", "matrix", "element"
        ]
        return haystacks.contains { hay in needles.contains { hay.contains($0) } }
    }

    static func detect(_ item: ClipboardItem) -> ContentContext {
        var ctx = ContentContext()

        // Provenance (stored, not derived from content).
        if item.tags.contains(ocrProvenanceTag) { ctx.insert(.fromOCR) }
        if looksLikeMailSource(item) { ctx.insert(.fromMailApp) }
        if looksLikeChatSource(item) { ctx.insert(.fromChat) }

        // Map SemanticKind to the primary flag.
        switch item.semantic {
        case .text:     ctx.insert(.plain)
        case .richText:
            ctx.insert(.richText); ctx.insert(.plain)
            // Rich text carrying ≥1 embedded image → image actions (Rotate,
            // Grayscale, OCR, …) operate on the embedded picture(s).
            if RichTextImageExtractor.hasEmbeddedImage(item) { ctx.insert(.richHasImage) }
        case .url:      ctx.insert(.url); ctx.insert(.plain)
        case .email:    ctx.insert(.email); ctx.insert(.plain)
        case .json:     ctx.insert(.json); ctx.insert(.plain)
        case .code:     ctx.insert(.code); ctx.insert(.plain)
        case .markdown: ctx.insert(.markdown); ctx.insert(.plain)
        case .table:    ctx.insert(.table); ctx.insert(.plain)
        case .image:    ctx.insert(.image)
        case .pdf:      ctx.insert(.pdf)
        case .files:    ctx.insert(.files)
        case .unknown:  break
        }

        // Text sub-flags
        guard ctx.contains(.plain), let s = item.previewText else { return ctx }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("\n") { ctx.insert(.multiline) }

        // QR eligible — text length up to ~2900 chars (rough alphanumeric limit for QR level M).
        if !trimmed.isEmpty && trimmed.count <= 2900 {
            ctx.insert(.qrEligible)
        }

        // Mixed script. Only actual letters count — the old `0x41…0x7A`
        // range also swept up `[ \ ] ^ _ \`` and flagged code like `a_b` /
        // `[]` as "Latin", so it's gated on `isLetter` and the precise
        // A–Z / a–z ranges.
        var hasCyr = false, hasLat = false
        for ch in trimmed where ch.isLetter {
            for sc in ch.unicodeScalars {
                if (0x0400...0x04FF).contains(sc.value) { hasCyr = true }
                if (0x0041...0x005A).contains(sc.value)
                    || (0x0061...0x007A).contains(sc.value) { hasLat = true }
            }
            if hasCyr && hasLat { break }
        }
        if hasCyr && hasLat { ctx.insert(.mixedScript) }
        if hasCyr { ctx.insert(.containsCyrillic) }
        if hasLat { ctx.insert(.containsLatin) }

        // Wrong layout
        if KeyboardLayoutRepair.looksWrongLayout(trimmed) { ctx.insert(.layoutWrong) }

        // #A75 cheap content traits.

        // Embedded email addresses / links (distinct from the whole-clip
        // .email / .url semantic kinds — these fire on text that merely
        // *contains* one).
        if trimmed.range(of: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
                         options: [.regularExpression, .caseInsensitive]) != nil {
            ctx.insert(.containsEmails)
        }
        if trimmed.range(of: #"(https?://|www\.)\S"#,
                         options: [.regularExpression, .caseInsensitive]) != nil {
            ctx.insert(.containsURLs)
        }
        // Real HTML markup — require a closing tag `</x>`, an attributed tag
        // `<x attr=…`, or a self-closing tag `<x/>`. Deliberately does NOT fire
        // on `5 < 10`, `List<String>`, `vector<int>` etc., so "Strip HTML tags"
        // never mangles math or generics.
        if trimmed.range(of: #"</[a-zA-Z][\w]*\s*>|<[a-zA-Z][\w]*\s+[\w:.\-]+\s*=|<[a-zA-Z][\w]*\s*/>"#,
                         options: .regularExpression) != nil {
            ctx.insert(.containsHTMLMarkup)
        }
        // Tracking parameters in a URL — utm_*, fbclid, gclid, igshid, …. Lets
        // "Clean URL" surface only when there's actually something to strip.
        if trimmed.range(of: #"[?&](utm_[a-z]+|fbclid|gclid|gad|gbraid|wbraid|igshid|mc_eid|mkt_tok|yclid|msclkid|_hsenc|_hsmi|ref_src|vero_id|oly_enc_id|spm)="#,
                         options: [.regularExpression, .caseInsensitive]) != nil {
            ctx.insert(.hasTrackingParams)
        }

        // Messy spacing — a tab, a non-breaking space, or a run of 2+ spaces.
        if trimmed.range(of: "[\\t\\u00A0]|  ", options: .regularExpression) != nil {
            ctx.insert(.messySpacing)
        }

        // Uppercase-heavy prose — ≥8 cased letters and ≥70% uppercase. The
        // floor avoids flagging short acronyms / single SHOUTED words.
        var upper = 0, cased = 0
        for ch in trimmed where ch.isLetter {
            cased += 1
            if ch.isUppercase { upper += 1 }
        }
        if cased >= 8 && Double(upper) / Double(cased) >= 0.7 {
            ctx.insert(.uppercaseHeavy)
        }
        // Mostly-lowercase — ≥8 cased letters and NO uppercase at all (the
        // signature of text typed entirely in lower case, e.g. chat / notes
        // with no capitalisation). A single sentence-start capital is enough to
        // clear it, so normal prose isn't flagged.
        if cased >= 8 && upper == 0 {
            ctx.insert(.lowercaseHeavy)
        }

        // Hard-wrapped lines — 3+ lines, a majority not ending in sentence
        // punctuation (the signature of text reflowed out of a PDF / email).
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count >= 3 {
            let terminal: Set<Character> = [".", "!", "?", ":", ";", "\"", ")"]
            let unterminated = lines.filter { line in
                guard let last = line.trimmingCharacters(in: .whitespaces).last else { return false }
                return !terminal.contains(last)
            }.count
            if Double(unterminated) / Double(lines.count) >= 0.6 {
                ctx.insert(.wrappedLines)
            }
        }

        return ctx
    }
}
