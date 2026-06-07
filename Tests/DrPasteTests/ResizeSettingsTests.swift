//
//  ResizeSettingsTests.swift
//  DrPasteTests
//
//  The resize longer-side target is user-configurable and persisted per action.
//

import XCTest
@testable import DrPaste

final class ResizeSettingsTests: XCTestCase {

    private func cleanup(_ id: String) {
        UserDefaults.standard.removeObject(forKey: "drpaste.image.resizeMaxLongSide.\(id)")
    }

    func testUnsetReturnsDefault() {
        let id = "test.resize.\(UUID().uuidString)"
        XCTAssertEqual(ResizeSettings.maxLongSide(for: id, default: 1920), 1920)
        cleanup(id)
    }

    func testRoundTrip() {
        let id = "test.resize.\(UUID().uuidString)"
        ResizeSettings.setMaxLongSide(800, for: id)
        XCTAssertEqual(ResizeSettings.maxLongSide(for: id), 800)
        cleanup(id)
    }

    func testClampsToBounds() {
        let id = "test.resize.\(UUID().uuidString)"
        ResizeSettings.setMaxLongSide(10_000_000, for: id)
        XCTAssertEqual(ResizeSettings.maxLongSide(for: id), ResizeSettings.maxSide)
        ResizeSettings.setMaxLongSide(1, for: id)
        XCTAssertEqual(ResizeSettings.maxLongSide(for: id), ResizeSettings.minSide)
        cleanup(id)
    }

    // Regression: a small target like 10 px must be honoured, not snapped up to
    // a 16 px floor (the user could not make a tiny thumbnail before).
    func testSmallTargetIsHonoured() {
        let id = "test.resize.\(UUID().uuidString)"
        ResizeSettings.setMaxLongSide(10, for: id)
        XCTAssertEqual(ResizeSettings.maxLongSide(for: id), 10)
        cleanup(id)
    }
}
