//
//  ImportReport.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Result-of-merge audit struct returned by `ActionRegistry.importJSON`
//  when called in `.merge` mode (#A41, 0.57.0). Lets the Settings →
//  Import… UI surface "what actually happened" instead of the previous
//  silent thumbs-up.
//
//  Background: the pre-0.57 merge handled exactly two of the thirteen
//  user-tunable `ActionConfig` fields (`enabledFlags` and `customAI`).
//  Everything else — custom transformations, titles, hotkeys, order,
//  test samples, image blobs, playground state, preferences — was
//  dropped silently. Users who exported their full config on machine
//  A and imported on machine B would find ~70 % of their settings
//  missing with no warning.
//
//  Per-field policy table (see ActionRegistry.importJSON for the
//  authoritative implementation):
//
//    +-------------------------+--------+-----------------------+
//    | Field                   | Mode   | Conflict resolution   |
//    +-------------------------+--------+-----------------------+
//    | version                 | skip   | runtime-derived       |
//    | enabledFlags            | merge  | incoming wins         |
//    | customAI                | merge  | current wins (skip)   |
//    | customTitles            | merge  | current wins (skip)   |
//    | actionOrder             | merge  | per-kind incoming     |
//    | customTransformations   | merge  | current wins (skip)   |
//    | actionHotkeys           | merge  | current wins (skip)   |
//    | seedAIVersion           | skip   | local-only counter    |
//    | seedTransformationVer.  | skip   | local-only counter    |
//    | actionTestSamples       | merge  | current wins (skip)   |
//    | actionTestImageBlobs    | merge  | current wins (skip)   |
//    | playgroundSamples       | merge  | current wins (skip)   |
//    | playgroundImageBlobs    | merge  | current wins (skip)   |
//    | preferences             | merge  | non-default incoming  |
//    +-------------------------+--------+-----------------------+
//
//  "current wins" is the import-day default for any field carrying
//  user intent (title rename, descriptor edit, hotkey binding) —
//  pre-existing local choices should not be silently overwritten by
//  a transfer. The follow-up Settings sheet surfaces every conflict
//  with a per-row Replace / Keep / Duplicate picker, so the policy
//  is the floor, not the ceiling.
//

import Foundation

/// Result of a single merge-mode import. Created empty and populated
/// in place by `ActionConfig.merging(_:)` as it walks each field. The
/// follow-up Settings sheet reads from these arrays to render the
/// "what changed" summary.
public struct ImportReport: Equatable {

    /// Per-action conflict. Captured for every field where current
    /// AND incoming carry a non-default value and the two disagree.
    /// `field` is the dotted path under `ActionConfig` (e.g.
    /// `customTitles`, `actionHotkeys`, `customTransformations.params`).
    public struct Conflict: Equatable {
        public let actionID: String
        public let field: String
        public let currentValue: String
        public let incomingValue: String
    }

    /// Per-hotkey reassignment from auto-steal during merge.
    public struct HotkeySteal: Equatable {
        public let actionID: String       // recipient of the chord
        public let fromActionID: String   // previous owner whose binding moved
        public let chord: String          // human-readable description
    }

    /// Per-hotkey rejection (chord conflicts with a system reservation
    /// or with DrPaste's own reserved hotkeys, e.g. ⌥⌘V).
    public struct HotkeySkip: Equatable {
        public let actionID: String
        public let chord: String
        public let reason: String
    }

    // MARK: Tallies — collected per merge pass.

    /// IDs newly added to `customAI` or `customTransformations`.
    public var addedActions: [String] = []
    /// Incoming items that collided with an existing ID — kept the
    /// current version.
    public var skippedDuplicates: [String] = []
    /// Incoming items that explicitly overwrote the current version.
    /// Currently empty in `.merge` mode (we don't auto-replace); the
    /// Settings sheet's per-row Replace decision feeds this list.
    public var replacedActions: [String] = []

    /// Hotkey bindings the incoming config stole from another local
    /// action (auto-resolves via `HotkeyPolicy`).
    public var hotkeysStolen: [HotkeySteal] = []
    /// Hotkey bindings rejected outright (reserved chord, etc.).
    public var hotkeysSkipped: [HotkeySkip] = []

    /// True when any field of `preferences` changed value during the
    /// merge.
    public var preferencesChanged: Bool = false

    /// Per-action test-sample updates (text Input field).
    public var samplesUpdated: Int = 0
    /// Per-action test-sample image-blob updates.
    public var imageBlobsCopied: Int = 0

    /// Conflicts that the user must resolve via the follow-up sheet.
    /// "current wins" is applied by default — these entries record
    /// what the user would need to look at to override that default.
    public var conflicts: [Conflict] = []

    public init() {}

    /// True iff the merge produced no observable change — used by
    /// the Settings UI to suppress the report sheet entirely (no
    /// point dragging the user through an empty summary).
    public var isEmpty: Bool {
        addedActions.isEmpty
            && skippedDuplicates.isEmpty
            && replacedActions.isEmpty
            && hotkeysStolen.isEmpty
            && hotkeysSkipped.isEmpty
            && preferencesChanged == false
            && samplesUpdated == 0
            && imageBlobsCopied == 0
            && conflicts.isEmpty
    }

    /// Single-line human summary suitable for the Settings sheet header.
    /// Example: "Imported 12 actions, skipped 2 duplicates, 1 hotkey
    /// reassigned, preferences kept."
    public var headline: String {
        var parts: [String] = []
        if !addedActions.isEmpty {
            parts.append("imported \(addedActions.count) action\(addedActions.count == 1 ? "" : "s")")
        }
        if !skippedDuplicates.isEmpty {
            parts.append("skipped \(skippedDuplicates.count) duplicate\(skippedDuplicates.count == 1 ? "" : "s")")
        }
        if !replacedActions.isEmpty {
            parts.append("replaced \(replacedActions.count) action\(replacedActions.count == 1 ? "" : "s")")
        }
        if !hotkeysStolen.isEmpty {
            parts.append("\(hotkeysStolen.count) hotkey\(hotkeysStolen.count == 1 ? "" : "s") reassigned")
        }
        if !hotkeysSkipped.isEmpty {
            parts.append("\(hotkeysSkipped.count) hotkey\(hotkeysSkipped.count == 1 ? "" : "s") skipped")
        }
        if samplesUpdated > 0 {
            parts.append("\(samplesUpdated) test sample\(samplesUpdated == 1 ? "" : "s") updated")
        }
        if imageBlobsCopied > 0 {
            parts.append("\(imageBlobsCopied) image\(imageBlobsCopied == 1 ? "" : "s") copied")
        }
        if preferencesChanged { parts.append("preferences merged") }
        if !conflicts.isEmpty {
            parts.append("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s") kept current")
        }
        if parts.isEmpty { return "No changes." }
        // Capitalise the first part for sentence presentation.
        let first = parts[0].prefix(1).capitalized + parts[0].dropFirst()
        if parts.count == 1 { return first + "." }
        return first + ", " + parts.dropFirst().joined(separator: ", ") + "."
    }
}

// MARK: - Merge implementation

extension ActionConfig {

    /// Per-field merge applying the policy table in `ImportReport`'s
    /// header. Returns the merged config plus the report. The original
    /// receiver is unchanged.
    ///
    /// Field policy refresher (full table in `ImportReport.swift`
    /// header):
    ///   - `version` / seed counters → skip (local lifecycle state).
    ///   - `enabledFlags` → incoming wins (least-surprise: imported
    ///     "I have this enabled" should take effect).
    ///   - everything else carrying user intent (titles, descriptors,
    ///     hotkeys, samples) → current wins on conflict, record the
    ///     conflict so the follow-up sheet can offer Replace.
    func merging(_ incoming: ActionConfig) -> (ActionConfig, ImportReport) {
        var merged = self
        var report = ImportReport()

        // enabledFlags — incoming wins.
        for (k, v) in incoming.enabledFlags {
            if let current = self.enabledFlags[k], current != v {
                report.conflicts.append(.init(
                    actionID: k,
                    field: "enabledFlags",
                    currentValue: String(current),
                    incomingValue: String(v)
                ))
            }
            merged.enabledFlags[k] = v
        }

        // customAI — append by ID. Current wins on duplicate.
        for desc in incoming.customAI {
            if merged.customAI.contains(where: { $0.id == desc.id }) {
                report.skippedDuplicates.append(desc.id)
                if let cur = merged.customAI.first(where: { $0.id == desc.id }),
                   cur.title != desc.title || cur.promptTemplate != desc.promptTemplate {
                    report.conflicts.append(.init(
                        actionID: desc.id,
                        field: "customAI",
                        currentValue: cur.title,
                        incomingValue: desc.title
                    ))
                }
            } else {
                merged.customAI.append(desc)
                report.addedActions.append(desc.id)
            }
        }

        // customTransformations — append by ID. Current wins on duplicate.
        for desc in incoming.customTransformations {
            if merged.customTransformations.contains(where: { $0.id == desc.id }) {
                report.skippedDuplicates.append(desc.id)
                if let cur = merged.customTransformations.first(where: { $0.id == desc.id }),
                   cur.title != desc.title {
                    report.conflicts.append(.init(
                        actionID: desc.id,
                        field: "customTransformations",
                        currentValue: cur.title,
                        incomingValue: desc.title
                    ))
                }
            } else {
                merged.customTransformations.append(desc)
                report.addedActions.append(desc.id)
            }
        }

        // customTitles — current wins. Record conflicts.
        for (k, v) in incoming.customTitles {
            if let current = merged.customTitles[k], current != v {
                report.conflicts.append(.init(
                    actionID: k,
                    field: "customTitles",
                    currentValue: current,
                    incomingValue: v
                ))
                // current wins → don't overwrite
            } else if merged.customTitles[k] == nil {
                merged.customTitles[k] = v
            }
        }

        // customDescriptions — current wins. Record conflicts (mirrors customTitles).
        for (k, v) in incoming.customDescriptions {
            if let current = merged.customDescriptions[k], current != v {
                report.conflicts.append(.init(
                    actionID: k,
                    field: "customDescriptions",
                    currentValue: current.text,
                    incomingValue: v.text
                ))
                // current wins → don't overwrite
            } else if merged.customDescriptions[k] == nil {
                merged.customDescriptions[k] = v
            }
        }

        // actionOrder — per-kind. Incoming list applied to ids that
        // weren't already ordered locally; new ids land at the end.
        for (kind, incomingOrder) in incoming.actionOrder {
            var currentOrder = merged.actionOrder[kind] ?? []
            let currentSet = Set(currentOrder)
            for id in incomingOrder where !currentSet.contains(id) {
                currentOrder.append(id)
            }
            if currentOrder != merged.actionOrder[kind] {
                merged.actionOrder[kind] = currentOrder
            }
        }

        // actionHotkeys — current wins on the recipient key; auto-
        // steal from a different recipient is recorded.
        for (incomingActionID, hk) in incoming.actionHotkeys {
            if let current = merged.actionHotkeys[incomingActionID] {
                if current != hk {
                    report.conflicts.append(.init(
                        actionID: incomingActionID,
                        field: "actionHotkeys",
                        currentValue: HotkeyDescription.describe(current),
                        incomingValue: HotkeyDescription.describe(hk)
                    ))
                }
                continue
            }
            // Does any other local action already own this chord?
            if let existingOwner = merged.actionHotkeys.first(where: { $0.value == hk })?.key {
                merged.actionHotkeys.removeValue(forKey: existingOwner)
                merged.actionHotkeys[incomingActionID] = hk
                report.hotkeysStolen.append(.init(
                    actionID: incomingActionID,
                    fromActionID: existingOwner,
                    chord: HotkeyDescription.describe(hk)
                ))
            } else {
                merged.actionHotkeys[incomingActionID] = hk
            }
        }

        // actionTestSamples — current wins, count net additions.
        for (k, v) in incoming.actionTestSamples {
            if merged.actionTestSamples[k] == nil {
                merged.actionTestSamples[k] = v
                report.samplesUpdated += 1
            } else if merged.actionTestSamples[k] != v {
                report.conflicts.append(.init(
                    actionID: k,
                    field: "actionTestSamples",
                    currentValue: merged.actionTestSamples[k] ?? "",
                    incomingValue: v
                ))
            }
        }

        // actionTestImageBlobs — copy filenames; current wins.
        for (k, v) in incoming.actionTestImageBlobs {
            if merged.actionTestImageBlobs[k] == nil {
                merged.actionTestImageBlobs[k] = v
                report.imageBlobsCopied += 1
            } else if merged.actionTestImageBlobs[k] != v {
                report.conflicts.append(.init(
                    actionID: k,
                    field: "actionTestImageBlobs",
                    currentValue: merged.actionTestImageBlobs[k] ?? "",
                    incomingValue: v
                ))
            }
        }

        // playgroundSamples — current wins.
        for (k, v) in incoming.playgroundSamples {
            if merged.playgroundSamples[k] == nil {
                merged.playgroundSamples[k] = v
            } else if merged.playgroundSamples[k] != v {
                report.conflicts.append(.init(
                    actionID: k,
                    field: "playgroundSamples",
                    currentValue: merged.playgroundSamples[k] ?? "",
                    incomingValue: v
                ))
            }
        }

        // playgroundImageBlobs — current wins.
        for (k, v) in incoming.playgroundImageBlobs {
            if merged.playgroundImageBlobs[k] == nil {
                merged.playgroundImageBlobs[k] = v
            } else if merged.playgroundImageBlobs[k] != v {
                report.conflicts.append(.init(
                    actionID: k,
                    field: "playgroundImageBlobs",
                    currentValue: merged.playgroundImageBlobs[k] ?? "",
                    incomingValue: v
                ))
            }
        }

        // preferences — per-field merge. Non-default incoming wins
        // over default local; conflicts kept current.
        let prefsBefore = merged.preferences
        let prefsDefault = ActionConfigPreferences()
        if incoming.preferences.fontScale != prefsDefault.fontScale,
           merged.preferences.fontScale == prefsDefault.fontScale {
            merged.preferences.fontScale = incoming.preferences.fontScale
        }
        if incoming.preferences.soundVolume != prefsDefault.soundVolume,
           merged.preferences.soundVolume == prefsDefault.soundVolume {
            merged.preferences.soundVolume = incoming.preferences.soundVolume
        }
        for (k, v) in incoming.preferences.soundsEnabled
        where merged.preferences.soundsEnabled[k] == nil {
            merged.preferences.soundsEnabled[k] = v
        }
        if merged.preferences != prefsBefore {
            report.preferencesChanged = true
        }

        // version / seed counters are intentionally NOT merged.

        return (merged, report)
    }
}

// MARK: - Hotkey chord description

/// Thin wrapper around `ActionHotkey.displayString` so the report
/// and the future Settings sheet print the same shape without
/// hand-rolling Carbon mask checks here.
enum HotkeyDescription {
    static func describe(_ hk: ActionHotkey) -> String {
        hk.displayString
    }
}
