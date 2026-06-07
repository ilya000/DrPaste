//
//  ActionHotkeyHoldPreviewToggleTests.swift
//  DrPasteTests
//
//  The Settings checkbox that disables the per-action-hotkey hold-preview
//  (⌥⌘ + letter held → BigHUD) is stored INVERTED under a `disabled` flag
//  so the preview stays on for users who never touch it. Verify the
//  default (enabled) and that the key round-trips.
//

import XCTest
@testable import DrPaste

final class ActionHotkeyHoldPreviewToggleTests: XCTestCase {

    private let key = PreferenceKeys.actionHotkeyHoldPreviewDisabled

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testDefaultIsHoldPreviewEnabled() {
        UserDefaults.standard.removeObject(forKey: key)
        // Default false = NOT disabled = hold-preview ON.
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key),
                       "hold-preview should default to enabled")
    }

    func testDisableFlagPersists() {
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }

    func testKeyIsListedForFactoryReset() {
        XCTAssertTrue(PreferenceKeys.allDirectKeys.contains(key),
                      "key must be removable by Factory Reset")
    }
}
