//
//  ImageMetadataTests.swift
//  DrPasteTests
//
//  Strip-metadata must surface WHAT it removed (GPS / camera / date) so the
//  result is explainable instead of an image identical to the input.
//

import XCTest
import ImageIO
import CoreGraphics
@testable import DrPaste

final class ImageMetadataTests: XCTestCase {

    /// A 4×4 JPEG carrying EXIF + GPS + TIFF camera metadata.
    private func jpegWithMetadata() -> Data {
        let w = 4, h = 4
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let cg = ctx.makeImage()!
        let metadata: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 15 Pro"
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:06:01 14:23:07"
            ] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.8199,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4783,
                kCGImagePropertyGPSLongitudeRef: "W"
            ] as [CFString: Any]
        ]
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, metadata as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    private func plainPNG() -> Data {
        let w = 4, h = 4
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let cg = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testHighlightsReportGPSCameraAndDate() {
        let hl = ImageMetadata.privacyHighlights(of: jpegWithMetadata())
        XCTAssertTrue(hl.contains { $0.hasPrefix("GPS") }, "no GPS highlight: \(hl)")
        XCTAssertTrue(hl.contains { $0.contains("Apple iPhone 15 Pro") }, "no camera highlight: \(hl)")
        XCTAssertTrue(hl.contains { $0.contains("Date taken") }, "no date highlight: \(hl)")
    }

    func testHasAnyTrueForMetadataJPEG() {
        XCTAssertTrue(ImageMetadata.hasAny(jpegWithMetadata()))
    }

    func testPlainPNGHasNoPrivacyMetadata() {
        XCTAssertTrue(ImageMetadata.privacyHighlights(of: plainPNG()).isEmpty)
        XCTAssertFalse(ImageMetadata.hasAny(plainPNG()))
    }

    func testSummaryWordingByCase() {
        let removed = ImageStripMetadataAction.summary(
            highlights: ["GPS 37.8°N 122.5°W", "Camera Apple iPhone"], hadMetadata: true, kb: 12)
        XCTAssertTrue(removed.hasPrefix("Removed: "))

        let already = ImageStripMetadataAction.summary(highlights: [], hadMetadata: false, kb: 12)
        XCTAssertTrue(already.contains("already clean"))
    }
}
