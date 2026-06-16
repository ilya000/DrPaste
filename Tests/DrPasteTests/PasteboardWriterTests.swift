//
//  PasteboardWriterTests.swift
//  DrPasteTests
//
//  Contract tests for lossless pasteboard restoration without touching the
//  system pasteboard.
//

import XCTest
@testable import DrPaste

final class PasteboardWriterTests: XCTestCase {

    func testReadableRepresentationsKeepDeclaredOrderAndSkipMissingBlobs() {
        let store = ClipboardStore()
        let first = store.writeRawBlob(Data("rtf".utf8), type: "public.rtf")
        let last = store.writeRawBlob(Data("plain".utf8), type: "public.utf8-plain-text")
        let item = ClipboardItem(
            id: UUID(),
            semantic: .richText,
            createdAt: Date(),
            representations: [
                "public.rtf": first,
                "public.tiff": "missing-\(UUID().uuidString).bin",
                "public.utf8-plain-text": last
            ],
            typesOrdered: [
                "public.rtf",
                "public.tiff",
                "public.utf8-plain-text"
            ],
            previewText: "fallback",
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: nil,
            sourceWindowTitle: nil,
            tags: []
        )

        let result = PasteboardWriter.readableRepresentations(for: item, store: store)

        XCTAssertEqual(result.entries.map(\.type), [
            "public.rtf",
            "public.utf8-plain-text"
        ])
        XCTAssertEqual(result.entries.map { String(data: $0.data, encoding: .utf8) }, [
            "rtf",
            "plain"
        ])
        XCTAssertEqual(result.missingCount, 1)
    }
}
