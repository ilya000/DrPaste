//
//  CodexSweepTests.swift
//  DrPasteTests
//
//  Regression coverage for the overnight Codex bug sweep.
//

import XCTest
import AppKit
@testable import DrPaste

final class CodexSweepTests: XCTestCase {

    private func item(_ kind: SemanticKind, _ text: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: kind, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: text,
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [])
    }

    private func preview(_ outcome: ApplyOutcome) -> ClipboardItem? {
        if case .preview(let p) = outcome { return p }
        return nil
    }

    // MARK: json.flatten escaping

    func testFlattenEscapesStrings() async throws {
        // A value containing a quote must produce VALID JSON, not the old
        // `"he said "hi""` garbage.
        let src = #"{"a":{"b":"he said \"hi\" today"},"c":"x\ny"}"#
        let out = preview(await JSONFlattenAction().apply(item: item(.json, src),
                                                          context: .json))
        let text = try XCTUnwrap(out?.previewText)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(parsed["a.b"] as? String, "he said \"hi\" today")
        XCTAssertEqual(parsed["c"] as? String, "x\ny")
    }

    func testFlattenKeepsBooleanAndNumberTypes() async throws {
        let src = #"{"a":{"flag":true,"n":42}}"#
        let out = preview(await JSONFlattenAction().apply(item: item(.json, src),
                                                          context: .json))
        let text = try XCTUnwrap(out?.previewText)
        // Booleans must serialise as true/false, not 1/0.
        XCTAssertTrue(text.contains("\"a.flag\" : true"), text)
        XCTAssertTrue(text.contains("\"a.n\" : 42"), text)
    }

    // MARK: CSV/TSV unified parser

    func testParserHandlesTabDelimiter() {
        let rows = CSVParser.parse("a\tb\nc\td", delimiter: "\t")
        XCTAssertEqual(rows, [["a", "b"], ["c", "d"]])
    }

    func testParserQuotedFieldWithEmbeddedDelimiterAndNewline() {
        // Comma inside quotes, and a newline inside quotes, must NOT split.
        let rows = CSVParser.parse("\"x,y\",b\n\"line1\nline2\",d")
        XCTAssertEqual(rows, [["x,y", "b"], ["line1\nline2", "d"]])
    }

    func testDetectDelimiter() {
        XCTAssertEqual(CSVParser.detectDelimiter("a\tb\nc\td"), "\t")
        XCTAssertEqual(CSVParser.detectDelimiter("a,b\nc,d"), ",")
    }

    func testLooksLikeCSVAcceptsTab() {
        // Codex pass 2 — TSV pasted as text must still expose the table actions.
        XCTAssertTrue(CSVParser.looksLikeCSV("name\tage\nAlice\t30"))
        XCTAssertTrue(CSVParser.looksLikeCSV("a,b\nc,d"))
        XCTAssertFalse(CSVParser.looksLikeCSV("just a sentence with no delimiters"))
    }

    func testTableToJSONHandlesTSVAndQuotes() async throws {
        let src = "name\tnote\nAlice\t\"a\tb\""   // quoted tab inside a TSV cell
        let out = preview(await TableToJSONAction().apply(item: item(.table, src),
                                                          context: .table))
        let text = try XCTUnwrap(out?.previewText)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(parsed.first?["name"] as? String, "Alice")
        XCTAssertEqual(parsed.first?["note"] as? String, "a\tb")
    }

    func testTableToMarkdownEscapesPipes() async throws {
        let src = "a,b\nx|y,z"
        let out = preview(await TableToMarkdownAction().apply(item: item(.table, src),
                                                              context: .table))
        let text = try XCTUnwrap(out?.previewText)
        XCTAssertTrue(text.contains("x\\|y"), "pipe not escaped: \(text)")
    }

    // MARK: flat-RTFD aware rich loader

    func testLoadAttributedReadsFlatRTFD() throws {
        let attr = NSAttributedString(string: "Hello rich",
                                      attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        let rtfd = try attr.data(from: NSRange(location: 0, length: attr.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let rel = "test-flatrtfd-\(UUID().uuidString).rtfd"
        try rtfd.write(to: AppStorage.blobsDir.appendingPathComponent(rel))
        var it = item(.richText, "Hello rich")
        it.representations = ["com.apple.flat-rtfd": rel]
        it.typesOrdered = ["com.apple.flat-rtfd"]
        let loaded = RichTextHelpers.loadAttributed(from: it)
        XCTAssertEqual(loaded?.string, "Hello rich")
    }

    // MARK: file-path list newline parsing (resize / extract consumers)

    func testFileToImageAcceptsNewlineSeparatedPaths() {
        // The shared previewText path parser must split on newlines, not just
        // commas (file clips join with "\n").
        let urls = existingFileURLs(fromText: "\(NSHomeDirectory())\n/Applications")
        XCTAssertEqual(urls.count, 2)
    }

    // MARK: clipFilePaths — prefer real file references over previewText

    func testClipFilePathsReadsNSFilenamesPboardType() throws {
        // A multi-file clip: the full list lives in the NSFilenamesPboardType
        // plist, NOT a single public.file-url. Paths with commas must survive.
        let paths = ["/tmp/a, b.txt", "/tmp/c.txt"]
        let plist = try PropertyListSerialization.data(fromPropertyList: paths, format: .xml, options: 0)
        let rel = "test-filenames-\(UUID().uuidString).bin"
        try plist.write(to: AppStorage.blobsDir.appendingPathComponent(rel))
        var it = item(.files, "ignored preview")
        it.representations = ["NSFilenamesPboardType": rel]
        XCTAssertEqual(clipFilePaths(it), paths)
    }

    func testClipFilePathsFallsBackToPreviewText() {
        let it = item(.files, "/tmp/x.txt\n/tmp/y.txt")
        XCTAssertEqual(clipFilePaths(it), ["/tmp/x.txt", "/tmp/y.txt"])
    }

    // MARK: #10 — Rich→Markdown/Wiki EXPORT escaping (AI path untouched)

    func testMarkdownExportEscapesLiterals() {
        let attr = NSAttributedString(string: "5 * 3 and my_var [x]")
        XCTAssertEqual(RichTextHelpers.attributedStringToMarkdown(attr, escapeLiterals: true),
                       "5 \\* 3 and my\\_var \\[x\\]")
        // Default (AI round-trip) leaves metachars untouched.
        XCTAssertEqual(RichTextHelpers.attributedStringToMarkdown(attr),
                       "5 * 3 and my_var [x]")
    }

    func testMarkdownAndWikiEmbedImages() {
        // Rich text "pic " + image. Markdown gets a self-contained data-URI;
        // Wiki gets a [[File:…]] reference (it can't inline binary).
        let img = NSImage(size: NSSize(width: 20, height: 20))
        img.lockFocus(); NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 20, height: 20).fill(); img.unlockFocus()
        let att = NSTextAttachment(); att.image = img
        let m = NSMutableAttributedString(string: "pic ")
        m.append(NSAttributedString(attachment: att))
        let md = RichTextHelpers.attributedStringToMarkdown(m, escapeLiterals: true) ?? ""
        XCTAssertTrue(md.contains("pic "), md)
        XCTAssertTrue(md.contains("![image](data:image/png;base64,"), "markdown didn't embed the image: \(md.prefix(60))")
        let wiki = RichTextHelpers.attributedStringToWiki(m, escapeLiterals: true)
        XCTAssertTrue(wiki.contains("[[File:embedded-image-1.png"), "wiki didn't reference the image: \(wiki)")
    }

    func testWikiExportEscapesBracketsAndPipe() {
        let attr = NSAttributedString(string: "a [b] | c")
        XCTAssertEqual(RichTextHelpers.attributedStringToWiki(attr, escapeLiterals: true),
                       "a &#91;b&#93; &#124; c")
        // Apostrophes (single quotes) are NOT escaped — too common in prose.
        let apos = NSAttributedString(string: "don't")
        XCTAssertEqual(RichTextHelpers.attributedStringToWiki(apos, escapeLiterals: true), "don't")
    }
}
