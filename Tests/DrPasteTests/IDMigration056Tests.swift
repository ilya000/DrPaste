//
//  IDMigration056Tests.swift
//  DrPasteTests
//
//  Contract tests for the pre-distribution action-ID consolidation.
//

import XCTest
@testable import DrPaste

final class IDMigration056Tests: XCTestCase {

    func testRemapsAllActionIDKeyedConfigFields() {
        var config = ActionConfig()
        let hotkey = ActionHotkey(keyCode: 31, modifiers: 1)
        config.enabledFlags = ["builtin.uppercase": true]
        config.customTitles = ["builtin.title_case": "Headline"]
        config.customDescriptions = [
            "builtin.url_strip_tracking": DescriptionOverride(text: "Clean it", baseDefaultHash: "old")
        ]
        config.actionHotkeys = ["builtin.image_ocr": hotkey]
        config.actionTestSamples = ["builtin.trim": "  sample  "]
        config.actionTestImageBlobs = ["builtin.image_ascii_art": "ascii.png"]

        _ = IDMigration056.apply(to: &config)

        XCTAssertEqual(config.enabledFlags["builtin.text.uppercase"], true)
        XCTAssertNil(config.enabledFlags["builtin.uppercase"])
        XCTAssertEqual(config.customTitles["builtin.text.title_case"], "Headline")
        XCTAssertEqual(config.customDescriptions["builtin.url.strip_tracking"]?.text, "Clean it")
        XCTAssertEqual(config.actionHotkeys["builtin.image.ocr"], hotkey)
        XCTAssertEqual(config.actionTestSamples["builtin.text.trim"], "  sample  ")
        XCTAssertEqual(config.actionTestImageBlobs["builtin.image.to_ascii_art"], "ascii.png")
    }

    func testMergedDuplicateIDsKeepSingleActionOrderEntry() {
        var config = ActionConfig()
        config.actionOrder = [
            "richText": [
                "builtin.paste_as_text",
                "builtin.clean_formatting",
                "builtin.rich_to_md"
            ]
        ]

        _ = IDMigration056.apply(to: &config)

        XCTAssertEqual(config.actionOrder["richText"], [
            "builtin.rich.strip_formatting",
            "builtin.rich.to_md"
        ])
    }

    func testDescriptorIDsAreRemappedInPlace() {
        var config = ActionConfig()
        config.customTransformations = [
            CustomTransformationDescriptor(
                id: "builtin.sort_lines",
                title: "Sort",
                engineID: "sort_lines",
                parameters: [:],
                applicableTypes: ["text"],
                enabled: true
            )
        ]
        config.customAI = [
            CustomAIDescriptor(
                id: "user.fix_grammar",
                title: "Fix grammar",
                promptTemplate: "Fix {input}",
                providerID: "",
                applicableTypes: ["text"],
                enabled: true,
                kind: .text
            )
        ]

        _ = IDMigration056.apply(to: &config)

        XCTAssertEqual(config.customTransformations.first?.id, "builtin.text.sort_lines")
        XCTAssertEqual(config.customAI.first?.id, "ai.text.fix_grammar")
    }

    func testApplyIsIdempotentAfterMigration() {
        var config = ActionConfig()
        config.enabledFlags = ["builtin.uppercase": true]

        _ = IDMigration056.apply(to: &config)
        let afterFirst = config
        let second = IDMigration056.apply(to: &config)

        XCTAssertEqual(second, 0)
        XCTAssertEqual(config, afterFirst)
    }
}
