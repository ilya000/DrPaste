//
//  OCRRichTextTests.swift
//  DrPasteTests
//
//  Extract text (OCR) on a rich-text clip with an embedded image: the image is
//  OCR'd IN PLACE — replaced by its recognized text — while the surrounding
//  rich text is preserved and the result stays a rich clip.
//

import XCTest
import AppKit
@testable import DrPaste

final class OCRRichTextTests: XCTestCase {

    /// Renders a single clear word into an image so Vision recognises it
    /// deterministically.
    @MainActor
    private func textImage(_ word: String) -> NSImage {
        let size = NSSize(width: 520, height: 160)
        let image = ImageRenderer.render(size: size, opaque: true, draw: { _ in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 72),
                .foregroundColor: NSColor.black
            ]
            (word as NSString).draw(at: NSPoint(x: 30, y: 40), withAttributes: attrs)
        })!
        return image
    }

    @MainActor
    func testOCROnRichTextWithEmbeddedImage() async throws {
        // Rich text: "Before " + <image of INVOICE> + " After".
        let attachment = NSTextAttachment()
        attachment.image = textImage("INVOICE")
        let attr = NSMutableAttributedString(string: "Before ")
        attr.append(NSAttributedString(attachment: attachment))
        attr.append(NSAttributedString(string: " After"))

        let rtfd = try attr.data(from: NSRange(location: 0, length: attr.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let rel = "test-ocr-rich-\(UUID().uuidString).rtfd"
        try rtfd.write(to: AppStorage.blobsDir.appendingPathComponent(rel))

        let item = ClipboardItem(
            id: UUID(), semantic: .richText, createdAt: Date(),
            representations: ["com.apple.flat-rtfd": rel],
            typesOrdered: ["com.apple.flat-rtfd"],
            previewText: "Before  After", previewImageRel: nil,
            sourceBundleID: nil, sourceAppName: nil, sourceWindowTitle: nil, tags: [])

        let action = ImageOCRAction()
        // The action must consider this applicable (rich + embedded image).
        XCTAssertTrue(action.isApplicable(item: item, context: ContextDetector.detect(item)))

        let outcome = await action.apply(item: item, context: ContextDetector.detect(item))
        guard case .preview(let out) = outcome else {
            return XCTFail("expected .preview, got \(outcome)")
        }
        // Result stays rich, surrounding text preserved, image → recognized text.
        XCTAssertEqual(out.semantic, .richText)
        let text = out.previewText ?? ""
        XCTAssertTrue(text.contains("Before"), "lost leading text: \(text)")
        XCTAssertTrue(text.contains("After"), "lost trailing text: \(text)")
        XCTAssertTrue(text.uppercased().contains("INVOICE"), "OCR text not spliced in: \(text)")
        XCTAssertTrue(out.tags.contains(ContextDetector.ocrProvenanceTag))
    }
}
