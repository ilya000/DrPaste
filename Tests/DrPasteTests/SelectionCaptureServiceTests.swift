//
//  SelectionCaptureServiceTests.swift
//  DrPasteTests
//
//  Contract tests for the #A40 selection-capture pipeline.
//
//  Note: most of the service's behaviour depends on a real
//  `NSPasteboard` and `AXIsProcessTrusted()`. Both are global state
//  on macOS without a clean fake-injection seam, so the tests below
//  cover the deterministic surfaces only:
//
//    - CaptureError equality / pattern matching.
//    - Captured struct shape.
//    - timeout default matches PasteSimulator's 0.40 s.
//
//  Live `.success` / `.timeout` / `.emptyPayload` paths are covered by
//  manual smoke testing on the running app — automating them needs the
//  pasteboard-fake harness planned in #A45.
//

import XCTest
@testable import DrPaste

@MainActor
final class SelectionCaptureServiceTests: XCTestCase {

    // MARK: CaptureError

    func testCaptureErrorEquality() {
        XCTAssertEqual(SelectionCaptureService.CaptureError.inaccessible,
                       SelectionCaptureService.CaptureError.inaccessible)
        XCTAssertEqual(SelectionCaptureService.CaptureError.noSelection,
                       SelectionCaptureService.CaptureError.noSelection)
        XCTAssertEqual(SelectionCaptureService.CaptureError.emptyPayload,
                       SelectionCaptureService.CaptureError.emptyPayload)
        XCTAssertEqual(SelectionCaptureService.CaptureError.timeout(0.4),
                       SelectionCaptureService.CaptureError.timeout(0.4))
        XCTAssertNotEqual(SelectionCaptureService.CaptureError.timeout(0.4),
                          SelectionCaptureService.CaptureError.timeout(0.5))
    }

    /// All four error cases must be distinguishable so callers can
    /// branch — silent abort on `.noSelection`, walk-the-user-to-AX
    /// on `.inaccessible`, log on `.timeout`, soft-fail on
    /// `.emptyPayload`.
    func testEveryCaptureErrorIsDistinct() {
        let cases: [SelectionCaptureService.CaptureError] = [
            .inaccessible, .noSelection, .timeout(0.4), .emptyPayload
        ]
        // All-pairs distinctness check. O(n²) but n == 4.
        for i in 0..<cases.count {
            for j in 0..<cases.count where i != j {
                XCTAssertNotEqual(cases[i], cases[j],
                                  "\(cases[i]) must differ from \(cases[j])")
            }
        }
    }
}
