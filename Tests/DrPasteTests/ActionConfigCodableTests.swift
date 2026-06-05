//
//  ActionConfigCodableTests.swift
//  DrPasteTests
//
//  Backward-compatibility tests for config decoding defaults.
//

import XCTest
@testable import DrPaste

final class ActionConfigCodableTests: XCTestCase {

    func testCustomAIDescriptorDefaultsKindAndEnabledWhenMissing() throws {
        let json = """
        {
          "id": "user.test",
          "title": "Test",
          "promptTemplate": "Do it",
          "providerID": "",
          "applicableTypes": ["text"]
        }
        """

        let descriptor = try JSONDecoder().decode(CustomAIDescriptor.self, from: Data(json.utf8))

        XCTAssertEqual(descriptor.kind, .text)
        XCTAssertTrue(descriptor.enabled)
    }

    func testActionConfigDecodesMissingNewFieldsToSafeDefaults() throws {
        let json = """
        {
          "version": 1,
          "enabledFlags": {
            "builtin.identity": true
          },
          "customAI": [],
          "customTitles": {}
        }
        """

        let config = try JSONDecoder().decode(ActionConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.enabledFlags["builtin.identity"], true)
        XCTAssertTrue(config.actionOrder.isEmpty)
        XCTAssertTrue(config.customTransformations.isEmpty)
        XCTAssertTrue(config.actionHotkeys.isEmpty)
        XCTAssertEqual(config.seedAIVersion, 0)
        XCTAssertEqual(config.seedTransformationVersion, 0)
        XCTAssertTrue(config.actionTestSamples.isEmpty)
        XCTAssertTrue(config.actionTestImageBlobs.isEmpty)
        XCTAssertTrue(config.playgroundSamples.isEmpty)
        XCTAssertTrue(config.playgroundImageBlobs.isEmpty)
        XCTAssertEqual(config.preferences, ActionConfigPreferences())
    }

    func testPreferencesDecodeMissingFieldsToDefaults() throws {
        let prefs = try JSONDecoder().decode(ActionConfigPreferences.self, from: Data("{}".utf8))

        XCTAssertEqual(prefs.fontScale, 1.0)
        XCTAssertEqual(prefs.soundVolume, 0.6)
        XCTAssertTrue(prefs.soundsEnabled.isEmpty)
    }

    func testActionConfigRoundTripsAllCurrentFields() throws {
        var config = ActionConfig()
        config.enabledFlags = ["builtin.identity": true]
        config.customTitles = ["builtin.identity": "Paste Exactly"]
        config.actionOrder = ["text": ["builtin.identity", "builtin.text.uppercase"]]
        config.actionHotkeys = [
            "builtin.text.uppercase": ActionHotkey(keyCode: 15, modifiers: 0)
        ]
        config.actionTestSamples = ["builtin.text.uppercase": "hello"]
        config.actionTestImageBlobs = ["builtin.image.ocr": "sample.png"]
        config.playgroundSamples = ["text": "sample"]
        config.playgroundImageBlobs = ["image": "image.png"]
        config.preferences.fontScale = 1.2

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ActionConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }
}
