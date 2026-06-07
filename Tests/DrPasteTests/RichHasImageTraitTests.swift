//
//  RichHasImageTraitTests.swift
//  DrPasteTests
//
//  A rich-text clip with an embedded image sets `.richHasImage`, and image
//  actions (Rotate, Grayscale, …) become applicable to it.
//

import XCTest
import AppKit
@testable import DrPaste

final class RichHasImageTraitTests: XCTestCase {

    @MainActor
    private func richImageItem() throws -> ClipboardItem {
        let img = NSImage(size: NSSize(width: 30, height: 30))
        img.lockFocus(); NSColor.systemOrange.setFill(); NSRect(x: 0, y: 0, width: 30, height: 30).fill(); img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let wr = FileWrapper(regularFileWithContents: png); wr.preferredFilename = "o.png"
        let att = NSTextAttachment(fileWrapper: wr)
        let m = NSMutableAttributedString(string: "see ")
        m.append(NSAttributedString(attachment: att))
        let rtfd = try m.data(from: NSRange(location: 0, length: m.length),
                              documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let rel = "richimg-\(UUID().uuidString).rtfd"
        try rtfd.write(to: AppStorage.blobsDir.appendingPathComponent(rel))
        return ClipboardItem(id: UUID(), semantic: .richText, createdAt: Date(),
            representations: ["com.apple.flat-rtfd": rel], typesOrdered: ["com.apple.flat-rtfd"],
            previewText: "see", previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
            sourceWindowTitle: nil, tags: [])
    }

    @MainActor
    func testRichWithImageSetsTraitAndEnablesImageActions() throws {
        let item = try richImageItem()
        let ctx = ContextDetector.detect(item)
        XCTAssertTrue(ctx.contains(.richHasImage), "richHasImage trait not set")

        // Image actions now apply to the rich clip.
        for action: ClipboardAction in [ImageRotateRightAction(), ImageRotateLeftAction(),
                                        ImageGrayscaleAction(), ImageOCRAction()] {
            XCTAssertTrue(action.isApplicable(item: item, context: ctx),
                          "\(action.id) should apply to rich text with an embedded image")
        }
    }

    @MainActor
    func testRotateRichIsInPlaceKeepingText() async throws {
        let item = try richImageItem()   // "see " + image
        let outcome = await ImageRotateRightAction().apply(item: item,
                                                           context: ContextDetector.detect(item))
        guard case .preview(let out) = outcome else { return XCTFail("expected preview, got \(outcome)") }
        // Result stays RICH (not flattened to a plain image), text preserved,
        // and the image attachment is still there (rotated in place).
        XCTAssertEqual(out.semantic, .richText)
        XCTAssertTrue((out.previewText ?? "").contains("see"), "surrounding text lost: \(out.previewText ?? "")")
        let attr = try XCTUnwrap(RichTextLoader.attributedString(from: out))
        var attachments = 0
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length)) { v, _, _ in if v != nil { attachments += 1 } }
        XCTAssertEqual(attachments, 1, "embedded image was dropped")
    }

    @MainActor
    func testImageInfoAndAsciiNotApplicableToRich() throws {
        let item = try richImageItem()
        let ctx = ContextDetector.detect(item)
        XCTAssertFalse(ImageInfoAction().isApplicable(item: item, context: ctx),
                       "Image Info must not apply to rich text")
        XCTAssertFalse(ImageToASCIIArtAction().isApplicable(item: item, context: ctx))
        XCTAssertFalse(ImageStripMetadataAction().isApplicable(item: item, context: ctx))
        XCTAssertFalse(ImageDecodeQRAction().isApplicable(item: item, context: ctx))
    }

    @MainActor
    func testPlainRichWithoutImageDoesNotSetTrait() {
        let item = ClipboardItem(id: UUID(), semantic: .richText, createdAt: Date(),
            representations: [:], typesOrdered: [], previewText: "just words",
            previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
            sourceWindowTitle: nil, tags: [])
        let ctx = ContextDetector.detect(item)
        XCTAssertFalse(ctx.contains(.richHasImage))
        XCTAssertFalse(ImageRotateRightAction().isApplicable(item: item, context: ctx))
    }
}
