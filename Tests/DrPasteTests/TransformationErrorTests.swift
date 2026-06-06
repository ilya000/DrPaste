//
//  TransformationErrorTests.swift
//  DrPasteTests
//
//  Failed transforms should read as calm, human messages — not the raw Cocoa
//  fallback "The operation couldn't be completed. (DrPaste.TransformationError
//  error 1.)". Many transforms simply have nothing to do (Base64-decoding
//  ordinary text, extracting headings from prose) and must not look like a crash.
//

import XCTest
@testable import DrPaste

final class TransformationErrorTests: XCTestCase {

    func testErrorDescriptionIsFriendlyNotRawCocoa() {
        let err = TransformationError.missingParameter("This text isn’t valid Base64, so there’s nothing to decode.")
        let msg = err.localizedDescription
        XCTAssertFalse(msg.contains("couldn’t be completed"), "still showing raw Cocoa error: \(msg)")
        XCTAssertFalse(msg.contains("TransformationError error"), "still showing raw enum case: \(msg)")
        XCTAssertEqual(msg, "This text isn’t valid Base64, so there’s nothing to decode.")
    }

    func testInvalidRegexHasReadablePrefix() {
        XCTAssertEqual(TransformationError.invalidRegex("bad pattern").errorDescription,
                       "Invalid regular expression: bad pattern")
    }

    func testBase64DecodeOfPlainTextThrowsFriendlyMessage() {
        do {
            _ = try TransformationRuntime.apply(engine: .base64Decode,
                                                input: "# Title\nnot base64 at all",
                                                params: [:])
            XCTFail("expected base64 decode to fail on non-base64 input")
        } catch {
            let msg = error.localizedDescription
            XCTAssertTrue(msg.contains("Base64"), "unexpected message: \(msg)")
            XCTAssertFalse(msg.contains("error 1"), "leaked raw error code: \(msg)")
        }
    }
}
