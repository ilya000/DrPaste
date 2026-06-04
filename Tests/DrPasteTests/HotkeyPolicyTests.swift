//
//  HotkeyPolicyTests.swift
//  DrPasteTests
//
//  Contract tests for user-assignable hotkey policy.
//

import Carbon.HIToolbox
import XCTest
@testable import DrPaste

final class HotkeyPolicyTests: XCTestCase {

    private func optCmd(_ keyCode: Int) -> ActionHotkey {
        ActionHotkey(keyCode: UInt16(keyCode), modifiers: UInt32(optionKey) | UInt32(cmdKey))
    }

    private func ctrlShift(_ keyCode: Int) -> ActionHotkey {
        ActionHotkey(keyCode: UInt16(keyCode), modifiers: UInt32(controlKey) | UInt32(shiftKey))
    }

    func testDrPasteReservedHotkeysHaveSpecificFeatureNames() {
        XCTAssertEqual(optCmd(kVK_ANSI_V).drPasteReservedName, "Open BigHUD")
        XCTAssertEqual(optCmd(kVK_ANSI_C).drPasteReservedName, "Quick Copy")
        XCTAssertEqual(optCmd(kVK_ANSI_X).drPasteReservedName, "Cut & Replace")
        XCTAssertEqual(optCmd(kVK_ANSI_S).drPasteReservedName, "Append Copy")
        XCTAssertEqual(optCmd(kVK_Return).drPasteReservedName, "Paste & Keep HUD")
        XCTAssertEqual(optCmd(kVK_ANSI_KeypadEnter).drPasteReservedName, "Paste & Keep HUD")
    }

    func testReservedHotkeysOnlyApplyToPureOptionCommandChord() {
        XCTAssertTrue(optCmd(kVK_ANSI_V).conflictsWithMainHotkeys)
        XCTAssertFalse(ctrlShift(kVK_ANSI_V).conflictsWithMainHotkeys)
        XCTAssertNil(ctrlShift(kVK_ANSI_V).drPasteReservedName)
    }

    func testSystemHotkeyBlocksKnownMacOSChords() {
        XCTAssertEqual(optCmd(kVK_ANSI_Q).systemHotkeyName, "Force Quit")
        XCTAssertEqual(optCmd(kVK_ANSI_D).systemHotkeyName, "Show or Hide the Dock")
        XCTAssertEqual(optCmd(kVK_ANSI_M).systemHotkeyName, "Minimize All Windows")
        XCTAssertEqual(optCmd(kVK_ANSI_H).systemHotkeyName, "Hide Others")
        XCTAssertEqual(optCmd(kVK_Space).systemHotkeyName, "Show Finder Search Window")
    }

    func testRegularActionHotkeyRemainsAssignable() {
        let hotkey = optCmd(kVK_ANSI_R)
        XCTAssertNil(hotkey.drPasteReservedName)
        XCTAssertNil(hotkey.systemHotkeyName)
        XCTAssertTrue(hotkey.isOptCmdOnly)
        XCTAssertEqual(hotkey.keyDisplayName, "R")
        XCTAssertEqual(hotkey.displayString, "⌥⌘R")
    }

    func testNonOptionCommandHotkeyIsNotHoldPreviewEligible() {
        let hotkey = ctrlShift(kVK_ANSI_R)
        XCTAssertFalse(hotkey.isOptCmdOnly)
        XCTAssertEqual(hotkey.displayString, "⌃⇧R")
    }
}
