//
//  ASCIIArtTests.swift
//  DrPasteTests
//
//  The ASCII-art renderer traces strong contours with directional glyphs
//  (Sobel edge detection) on top of a tonal ramp — that's what makes it read
//  as a drawing rather than dithered noise.
//

import XCTest
import AppKit
import CoreGraphics
@testable import DrPaste

final class ASCIIArtTests: XCTestCase {

    private func image(_ draw: (CGContext) -> Void, _ w: Int = 80, _ h: Int = 80) -> NSImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        let cg = ctx.makeImage()!
        let img = NSImage(size: NSSize(width: w, height: h))
        img.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return img
    }

    func testVerticalEdgeProducesPipeStrokes() {
        // Left half dark, right half light → strong vertical contour.
        let img = image { ctx in
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 40, y: 0, width: 40, height: 80))
        }
        let out = ImageToASCIIArtAction.render(image: img, outWidth: 40)
        XCTAssertTrue(out.contains("|"), "vertical edge should yield | strokes:\n\(out)")
    }

    func testHorizontalEdgeProducesDashStrokes() {
        // Top half dark, bottom half light → strong horizontal contour.
        let img = image { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 40, width: 80, height: 40))
        }
        let out = ImageToASCIIArtAction.render(image: img, outWidth: 40)
        XCTAssertTrue(out.contains("-"), "horizontal edge should yield - strokes:\n\(out)")
    }

    func testRendererHonoursRequestedWidth() {
        let img = image({ ctx in
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }, 80, 80)
        let out = ImageToASCIIArtAction.render(image: img, outWidth: 24)
        let maxLine = out.split(separator: "\n").map(\.count).max() ?? 0
        XCTAssertLessThanOrEqual(maxLine, 24)
    }

    func testASCIIArtSettingsRoundTripAndClamp() {
        let id = "test.ascii.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: "drpaste.image.asciiMaxWidth.\(id)")
        }

        XCTAssertEqual(ASCIIArtSettings.maxWidth(for: id, default: 40), 40)
        ASCIIArtSettings.setMaxWidth(88, for: id)
        XCTAssertEqual(ASCIIArtSettings.maxWidth(for: id), 88)
        ASCIIArtSettings.setMaxWidth(1, for: id)
        XCTAssertEqual(ASCIIArtSettings.maxWidth(for: id), ASCIIArtSettings.minWidth)
        ASCIIArtSettings.setMaxWidth(10_000, for: id)
        XCTAssertEqual(ASCIIArtSettings.maxWidth(for: id), ASCIIArtSettings.maxWidth)
    }
}
