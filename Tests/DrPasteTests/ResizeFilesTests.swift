//
//  ResizeFilesTests.swift
//  DrPasteTests
//
//  Resize Images on a files clip must actually resize and surface the result
//  as image content — not keep the original file references (which silently
//  pasted the un-resized files).
//

import XCTest
import AppKit
@testable import DrPaste

final class ResizeFilesTests: XCTestCase {

    private func writeTempImage(_ side: Int) throws -> URL {
        let img = NSImage(size: NSSize(width: side, height: side))
        img.lockFocus(); NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill(); img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resize-src-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    private func filesItem(_ paths: [String]) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: .files, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: paths.joined(separator: "\n"),
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [])
    }

    func testSingleImageFileBecomesResizedImageClip() async throws {
        let url = try writeTempImage(80)
        let action = ImageResizeAction()
        ResizeSettings.setMaxLongSide(20, for: action.id)
        defer { UserDefaults.standard.removeObject(forKey: "drpaste.image.resizeMaxLongSide.\(action.id)") }

        let item = filesItem([url.path])
        let outcome = await action.apply(item: item, context: ContextDetector.detect(item))
        guard case .preview(let out) = outcome else { return XCTFail("expected preview, got \(outcome)") }
        // A single image file → an IMAGE clip (shows in preview, pastes as image).
        XCTAssertEqual(out.semantic, .image)
        XCTAssertNotNil(out.previewImageRel, "no preview thumbnail")
        let key = out.typesOrdered.first ?? ""
        XCTAssertTrue(key == "public.png" || key == "public.jpeg", "not an image rep: \(out.typesOrdered)")
        // The stored bytes are actually resized (≤ 20 px longer side).
        if let rel = out.representations[key],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let resized = NSImage(data: data) {
            XCTAssertLessThanOrEqual(max(resized.size.width, resized.size.height), 20.5)
        } else {
            XCTFail("resized image bytes not stored")
        }
    }

    func testMultipleImageFilesStayFilesWithResizedRefs() async throws {
        let a = try writeTempImage(80), b = try writeTempImage(80)
        let action = ImageResizeAction()
        ResizeSettings.setMaxLongSide(20, for: action.id)
        defer { UserDefaults.standard.removeObject(forKey: "drpaste.image.resizeMaxLongSide.\(action.id)") }

        let item = filesItem([a.path, b.path])
        let outcome = await action.apply(item: item, context: ContextDetector.detect(item))
        guard case .preview(let out) = outcome else { return XCTFail("expected preview") }
        XCTAssertEqual(out.semantic, .files)
        // Representations point at the RESIZED files (paths contain "-resized").
        XCTAssertTrue((out.previewText ?? "").contains("-resized"), "didn't resize: \(out.previewText ?? "")")
        XCTAssertNotNil(out.representations["NSFilenamesPboardType"], "no file refs in resized clip")
    }
}
