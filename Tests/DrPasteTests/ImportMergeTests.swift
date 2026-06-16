//
//  ImportMergeTests.swift
//  DrPasteTests
//
//  #A41 contract tests for `ActionConfig.merging(_:)`. Pre-0.57 the
//  merge silently dropped 11 of 13 user-tunable fields; these tests
//  pin every field's policy so regressions surface as a build failure
//  instead of a "what happened to my hotkeys" support ticket.
//

import XCTest
@testable import DrPaste

final class ImportMergeTests: XCTestCase {

    // MARK: enabledFlags

    func testEnabledFlagsIncomingWins() {
        var current = ActionConfig()
        current.enabledFlags = ["builtin.identity": true, "builtin.text.uppercase": false]
        var incoming = ActionConfig()
        incoming.enabledFlags = ["builtin.text.uppercase": true, "builtin.json.pretty": false]

        let (merged, report) = current.merging(incoming)

        XCTAssertEqual(merged.enabledFlags["builtin.identity"], true)       // current preserved
        XCTAssertEqual(merged.enabledFlags["builtin.text.uppercase"], true) // incoming wins
        XCTAssertEqual(merged.enabledFlags["builtin.json.pretty"], false)   // new from incoming
        XCTAssertEqual(report.conflicts.filter { $0.field == "enabledFlags" }.count, 1)
    }

    // MARK: customAI

    func testCustomAIDuplicatesSkippedCurrentWins() {
        var current = ActionConfig()
        current.customAI = [CustomAIDescriptor(
            id: "ai.text.translate",
            title: "Translate (Russian)",
            promptTemplate: "Translate to Russian.",
            providerID: "",
            applicableTypes: ["text"])]
        var incoming = ActionConfig()
        incoming.customAI = [CustomAIDescriptor(
            id: "ai.text.translate",
            title: "Translate (Spanish)",
            promptTemplate: "Translate to Spanish.",
            providerID: "",
            applicableTypes: ["text"])]

        let (merged, report) = current.merging(incoming)

        XCTAssertEqual(merged.customAI.count, 1)
        XCTAssertEqual(merged.customAI[0].title, "Translate (Russian)")
        XCTAssertTrue(report.skippedDuplicates.contains("ai.text.translate"))
        XCTAssertTrue(report.conflicts.contains(where: {
            $0.actionID == "ai.text.translate" && $0.field == "customAI"
        }))
    }

    func testCustomAINewEntriesAdded() {
        let current = ActionConfig()
        var incoming = ActionConfig()
        incoming.customAI = [CustomAIDescriptor(
            id: "ai.text.summarize",
            title: "Summarize",
            promptTemplate: "Summarize the input.",
            providerID: "",
            applicableTypes: ["text"])]

        let (merged, report) = current.merging(incoming)

        XCTAssertEqual(merged.customAI.count, 1)
        XCTAssertTrue(report.addedActions.contains("ai.text.summarize"))
        XCTAssertEqual(report.skippedDuplicates.count, 0)
    }

    // MARK: customTitles

    func testCustomTitlesCurrentWins() {
        var current = ActionConfig()
        current.customTitles = ["builtin.identity": "Paste It"]
        var incoming = ActionConfig()
        incoming.customTitles = ["builtin.identity": "Stamp", "builtin.text.trim": "Strip"]

        let (merged, report) = current.merging(incoming)

        XCTAssertEqual(merged.customTitles["builtin.identity"], "Paste It")  // current wins
        XCTAssertEqual(merged.customTitles["builtin.text.trim"], "Strip")    // new from incoming
        XCTAssertTrue(report.conflicts.contains(where: {
            $0.actionID == "builtin.identity" && $0.field == "customTitles"
        }))
    }

    // MARK: actionOrder

    func testActionOrderMergesNewIDsAtTail() {
        var current = ActionConfig()
        current.actionOrder = ["text": ["a", "b", "c"]]
        var incoming = ActionConfig()
        incoming.actionOrder = ["text": ["c", "d", "e"], "url": ["x", "y"]]

        let (merged, _) = current.merging(incoming)

        XCTAssertEqual(merged.actionOrder["text"], ["a", "b", "c", "d", "e"])
        XCTAssertEqual(merged.actionOrder["url"], ["x", "y"])
    }

    // MARK: actionHotkeys

    func testActionHotkeysCurrentRecipientWins() {
        var current = ActionConfig()
        current.actionHotkeys = ["builtin.identity": ActionHotkey(keyCode: 31, modifiers: 0)]
        var incoming = ActionConfig()
        incoming.actionHotkeys = ["builtin.identity": ActionHotkey(keyCode: 99, modifiers: 0)]

        let (merged, report) = current.merging(incoming)

        // Current binding for the same actionID stays
        XCTAssertEqual(merged.actionHotkeys["builtin.identity"]?.keyCode, 31)
        XCTAssertTrue(report.conflicts.contains(where: {
            $0.actionID == "builtin.identity" && $0.field == "actionHotkeys"
        }))
    }

    func testActionHotkeysStealRecordedWhenIncomingClaimsAnotherActionsChord() {
        let chord = ActionHotkey(keyCode: 31, modifiers: 0)
        var current = ActionConfig()
        current.actionHotkeys = ["builtin.text.uppercase": chord]
        var incoming = ActionConfig()
        incoming.actionHotkeys = ["builtin.text.lowercase": chord]

        let (merged, report) = current.merging(incoming)

        // Chord migrated from uppercase → lowercase
        XCTAssertNil(merged.actionHotkeys["builtin.text.uppercase"])
        XCTAssertEqual(merged.actionHotkeys["builtin.text.lowercase"], chord)
        XCTAssertEqual(report.hotkeysStolen.count, 1)
        XCTAssertEqual(report.hotkeysStolen[0].actionID, "builtin.text.lowercase")
        XCTAssertEqual(report.hotkeysStolen[0].fromActionID, "builtin.text.uppercase")
    }

    // MARK: actionTestSamples

    func testActionTestSamplesMergeCountsAdditions() {
        var current = ActionConfig()
        current.actionTestSamples = ["a": "old"]
        var incoming = ActionConfig()
        incoming.actionTestSamples = ["a": "new", "b": "incoming"]

        let (merged, report) = current.merging(incoming)

        XCTAssertEqual(merged.actionTestSamples["a"], "old")      // current wins
        XCTAssertEqual(merged.actionTestSamples["b"], "incoming") // new
        XCTAssertEqual(report.samplesUpdated, 1)
        XCTAssertTrue(report.conflicts.contains(where: { $0.actionID == "a" }))
    }

    // MARK: seed counters

    func testSeedCountersNotMerged() {
        var current = ActionConfig()
        current.seedTransformationVersion = 9
        current.seedAIVersion = 8
        var incoming = ActionConfig()
        incoming.seedTransformationVersion = 5
        incoming.seedAIVersion = 3

        let (merged, _) = current.merging(incoming)

        // Local counters are lifecycle state — never imported.
        XCTAssertEqual(merged.seedTransformationVersion, 9)
        XCTAssertEqual(merged.seedAIVersion, 8)
    }

    // MARK: preferences

    func testPreferencesNonDefaultIncomingWinsOverDefaultLocal() {
        let current = ActionConfig()
        XCTAssertEqual(current.preferences.fontScale, 1.0)
        var incoming = ActionConfig()
        incoming.preferences.fontScale = 1.4

        let (merged, report) = current.merging(incoming)

        XCTAssertEqual(merged.preferences.fontScale, 1.4)
        XCTAssertTrue(report.preferencesChanged)
    }

    func testPreferencesIncomingDoesNotOverwriteLocalCustomization() {
        var current = ActionConfig()
        current.preferences.fontScale = 1.2  // user already customised
        var incoming = ActionConfig()
        incoming.preferences.fontScale = 1.6

        let (merged, _) = current.merging(incoming)

        // Local non-default value wins.
        XCTAssertEqual(merged.preferences.fontScale, 1.2)
    }

    // MARK: ImportReport.isEmpty / headline

    func testEmptyMergeReportIsEmpty() {
        let current = ActionConfig()
        let (_, report) = current.merging(ActionConfig())
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.headline, "No changes.")
    }

    func testNonTrivialMergeProducesHeadline() {
        let current = ActionConfig()
        var incoming = ActionConfig()
        incoming.customAI = [CustomAIDescriptor(
            id: "ai.text.summarize", title: "Summarize",
            promptTemplate: "Summarize.", providerID: "",
            applicableTypes: ["text"])]
        incoming.customAI.append(CustomAIDescriptor(
            id: "ai.text.translate", title: "Translate",
            promptTemplate: "Translate.", providerID: "",
            applicableTypes: ["text"]))
        let (_, report) = current.merging(incoming)
        XCTAssertFalse(report.isEmpty)
        // headline capitalises the first clause for sentence presentation,
        // so it reads "Imported 2 actions." (capital I).
        XCTAssertTrue(report.headline.contains("Imported 2 actions"),
                      "unexpected headline: \(report.headline)")
    }
}
