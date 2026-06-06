//
//  ActionTraits.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  #A75 trait gating. An action can declare "Show this action when…"
//  conditions — each a single cheap ContentContext flag computed live by
//  ContextDetector. The editor surfaces these as plain-language toggles
//  (Slice 3); here we define the curated human vocabulary and the
//  matching rule used by the action filter.
//
//  Visibility model (locked with owner): the Enabled/Disabled master
//  switch is unchanged. On top of it, an action shows only when its
//  conditions pass. No "always override" — to make a gated action always
//  appear, the user simply turns its condition off (clears requiredTraits).
//
//      visible = enabled
//                && kind matches
//                && ActionTrait.passes(required, forbidden, in: context)
//

import Foundation

/// One user-selectable "Show this action when…" condition. `key` is the
/// stable string persisted in descriptors; `label` is the plain-language
/// phrase shown in the editor; `flag` is the ContentContext bit it maps to.
struct ActionTrait: Identifiable, Equatable {
    let key: String
    let label: String
    let flag: ContentContext

    var id: String { key }

    /// The curated human-facing vocabulary (small by design — a person is
    /// overwhelmed by a long list). AI auto-config (#A82, deferred) may draw
    /// from a larger set later; this is the manual list.
    static let all: [ActionTrait] = [
        ActionTrait(key: "containsEmails",   label: "contains email addresses",          flag: .containsEmails),
        ActionTrait(key: "containsURLs",     label: "contains links / URLs",             flag: .containsURLs),
        ActionTrait(key: "containsCyrillic", label: "contains Cyrillic text",            flag: .containsCyrillic),
        ActionTrait(key: "containsLatin",    label: "contains Latin text",               flag: .containsLatin),
        ActionTrait(key: "uppercaseHeavy",   label: "is mostly UPPERCASE",               flag: .uppercaseHeavy),
        ActionTrait(key: "messySpacing",     label: "has messy spacing (tabs / runs)",   flag: .messySpacing),
        ActionTrait(key: "wrappedLines",     label: "has hard-wrapped lines (PDF-style)", flag: .wrappedLines),
        ActionTrait(key: "layoutWrong",      label: "looks typed in the wrong keyboard layout", flag: .layoutWrong),
        ActionTrait(key: "fromOCR",          label: "came from screenshot / OCR",        flag: .fromOCR)
        // NOTE: there is intentionally no "emailLike" trait — it mapped to the
        // whole-clip `.email` SemanticKind, which fires only on a bare address,
        // never on a pasted email *body*. Email actions gate on `containsEmails`
        // (text that contains an address) instead. See #A75 / Codex review S1.
    ]

    static func trait(forKey key: String) -> ActionTrait? {
        all.first { $0.key == key }
    }

    /// Resolve a list of persisted keys to their flags, silently dropping
    /// any unknown key (so a stale descriptor never hides an action by
    /// referencing a condition the build no longer knows).
    private static func flags(_ keys: [String]) -> [ContentContext] {
        keys.compactMap { trait(forKey: $0)?.flag }
    }

    /// The gating rule. `required` is OR — empty (or all-unknown) passes,
    /// otherwise at least one must be present. `forbidden` blocks when any
    /// is present.
    static func passes(required: [String],
                       forbidden: [String],
                       in ctx: ContentContext) -> Bool {
        let req = flags(required)
        if !req.isEmpty && !req.contains(where: { ctx.contains($0) }) {
            return false
        }
        for f in flags(forbidden) where ctx.contains(f) {
            return false
        }
        return true
    }
}
