//
//  ImageSampleTests.swift
//  DrPasteTests
//
//  OCR and Decode-QR actions need samples that actually exercise them — a card
//  of text and a real QR code — so the playground demonstrates the feature.
//

import XCTest
import CoreImage
@testable import DrPaste

@MainActor
final class ImageSampleTests: XCTestCase {

    func testOCRSampleIsImageWithPreview() {
        guard let item = ActionTestSamples.makeOCRSampleItem() else {
            return XCTFail("no OCR sample produced")
        }
        XCTAssertEqual(item.semantic, .image)
        XCTAssertNotNil(item.previewImageRel)
        XCTAssertFalse(item.representations.isEmpty)
    }

    func testQRSampleDecodesBackToTheJoke() {
        guard let item = ActionTestSamples.makeQRSampleItem(),
              let rel = item.previewImageRel,
              let ci = CIImage(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel)) else {
            return XCTFail("no QR sample produced")
        }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let messages = (detector?.features(in: ci) ?? [])
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .joined()
        XCTAssertTrue(messages.contains("dark mode"),
                      "QR did not decode to the IT joke, got: \(messages)")
    }

    func testDefaultImageSampleDispatch() {
        XCTAssertNotNil(ActionTestSamples.defaultImageSample(forActionID: "builtin.image.ocr"))
        XCTAssertNotNil(ActionTestSamples.defaultImageSample(forActionID: "builtin.image.decode_qr"))
    }
}
