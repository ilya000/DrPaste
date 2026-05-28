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
}

enum ContextDetector {

    static func detect(_ item: ClipboardItem) -> ContentContext {
        var ctx = ContentContext()

        // Map SemanticKind to the primary flag.
        switch item.semantic {
        case .text:     ctx.insert(.plain)
        case .richText: ctx.insert(.richText); ctx.insert(.plain)
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

        // Mixed script
        var hasCyr = false, hasLat = false
        for ch in trimmed.unicodeScalars {
            if (0x0400...0x04FF).contains(ch.value) { hasCyr = true }
            if (0x0041...0x007A).contains(ch.value) { hasLat = true }
            if hasCyr && hasLat { break }
        }
        if hasCyr && hasLat { ctx.insert(.mixedScript) }

        // Wrong layout
        if KeyboardLayoutRepair.looksWrongLayout(trimmed) { ctx.insert(.layoutWrong) }

        return ctx
    }
}
