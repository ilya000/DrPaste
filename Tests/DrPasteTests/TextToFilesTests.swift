//
//  TextToFilesTests.swift
//  DrPasteTests
//
//  #A76 — Text → Files. A text clip whose lines are REAL existing paths can be
//  turned back into a files clip. Must never misfire on ordinary prose.
//

import XCTest
@testable import DrPaste

final class TextToFilesTests: XCTestCase {

    private func item(_ text: String, _ kind: SemanticKind = .text) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: kind, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: text,
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [])
    }

    func testExistingFileURLsParsesRealPaths() {
        let home = NSHomeDirectory()
        let urls = existingFileURLs(fromText: "\(home)\n/Applications")
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.map { $0.path }, [home, "/Applications"])
    }

    func testExistingFileURLsRejectsFakePaths() {
        XCTAssertTrue(existingFileURLs(fromText: "/no/such/path/xyzzy-1234").isEmpty)
        // Ordinary prose with a slash → no real path → nothing.
        XCTAssertTrue(existingFileURLs(fromText: "use a/b ratio of 50% here").isEmpty)
    }

    func testExistingFileURLsHandlesQuotesTildeAndFileURL() {
        let home = NSHomeDirectory()
        XCTAssertEqual(existingFileURLs(fromText: "'\(home)'").map { $0.path }, [home])
        XCTAssertEqual(existingFileURLs(fromText: "~").map { $0.path }, [home])
        XCTAssertEqual(existingFileURLs(fromText: "file://\(home)").map { $0.path }, [home])
    }

    func testIsApplicableOnlyWhenPathsExist() {
        let store = ClipboardStore()
        let a = TextToFilesAction(store: store)
        let real = item("\(NSHomeDirectory())\n/Applications")
        XCTAssertTrue(a.isApplicable(item: real, context: ContextDetector.detect(real)))
        let prose = item("just some text, nothing here")
        XCTAssertFalse(a.isApplicable(item: prose, context: ContextDetector.detect(prose)))
        // A real files clip must not re-offer the action.
        let files = item("/Applications", .files)
        XCTAssertFalse(a.isApplicable(item: files, context: ContextDetector.detect(files)))
    }

    func testRichIconsCarriesFileLinks() async throws {
        // "Files as rich icons" must hyperlink each entry to its file URL so the
        // references aren't lost when pasted into Mail / Notes / Pages.
        let store = ClipboardStore()
        let a = FilesRichRepresentationAction(store: store)
        let files = item("/Applications", .files)
        let outcome = await a.apply(item: files, context: ContextDetector.detect(files))
        guard case .preview(let out) = outcome else { return XCTFail("expected preview") }
        let attr = try XCTUnwrap(RichTextLoader.attributedString(from: out))
        var foundLink = false
        attr.enumerateAttribute(.link, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            let path = (value as? URL)?.path ?? (value as? String)
            if path?.contains("/Applications") == true { foundLink = true }
        }
        XCTAssertTrue(foundLink, "rich-icons output lost the file link")
    }

    func testApplyProducesFilesClip() async {
        let store = ClipboardStore()
        let a = TextToFilesAction(store: store)
        let src = item("\(NSHomeDirectory())\n/Applications")
        let outcome = await a.apply(item: src, context: ContextDetector.detect(src))
        guard case .preview(let out) = outcome else {
            return XCTFail("expected .preview, got \(outcome)")
        }
        XCTAssertEqual(out.semantic, .files)
        XCTAssertTrue(out.typesOrdered.contains("public.file-url"))
        XCTAssertTrue(out.typesOrdered.contains("NSFilenamesPboardType"))
        // Round-trip: the recovered URLs must match both real paths.
        let recovered = out.representations["NSFilenamesPboardType"].flatMap { rel -> [String]? in
            guard let data = try? Data(contentsOf: store.blobURL(rel)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            else { return nil }
            return plist as? [String]
        }
        XCTAssertEqual(recovered, [NSHomeDirectory(), "/Applications"])
    }
}
