//
//  ActionDescriptionOverrideTests.swift
//  DrPasteTests
//
//  The per-action description override (shown as the second line of the
//  action row in Settings, editable in the ActionEditor) must round-trip
//  through ActionConfig's Codable and through the registry helpers, and an
//  empty/blank value must clear the override rather than persist a blank.
//

import XCTest
@testable import DrPaste

final class ActionDescriptionOverrideTests: XCTestCase {

    func testConfigEncodesAndDecodesCustomDescriptions() throws {
        var cfg = ActionConfig()
        cfg.customDescriptions["builtin.text.uppercase"] = "Shout it."
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(ActionConfig.self, from: data)
        XCTAssertEqual(back.customDescriptions["builtin.text.uppercase"], "Shout it.")
    }

    func testDecodeMissingKeyDefaultsEmpty() throws {
        // Older actions.json with no customDescriptions key still decodes.
        let json = "{\"version\":4}".data(using: .utf8)!
        let cfg = try JSONDecoder().decode(ActionConfig.self, from: json)
        XCTAssertTrue(cfg.customDescriptions.isEmpty)
    }

    @MainActor
    func testRegistrySetAndClearOverride() {
        let reg = ActionRegistry()
        let saved = reg.config                 // snapshot — restore at the end
        defer { reg.config = saved }
        let id = "builtin.text.uppercase"

        reg.setCustomDescription("My custom blurb", forActionID: id)
        XCTAssertEqual(reg.customDescription(forActionID: id), "My custom blurb")

        // Blank / whitespace clears the override.
        reg.setCustomDescription("   ", forActionID: id)
        XCTAssertNil(reg.customDescription(forActionID: id))

        reg.setCustomDescription("again", forActionID: id)
        reg.setCustomDescription(nil, forActionID: id)
        XCTAssertNil(reg.customDescription(forActionID: id))
    }
}
