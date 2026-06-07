//
//  IPALocalTests.swift
//  DrPasteTests
//
//  Offline English → IPA (CMUdict-backed) transcription: dictionary bundles
//  and loads, common words transcribe with stress marks, punctuation and
//  unknown words are preserved, and both output modes render correctly.
//

import XCTest
@testable import DrPaste

final class IPALocalTests: XCTestCase {

    // Load once for the whole case (the action loads on demand in production).
    private static let dict = IPALocal.loadDictionary()
    private var dict: [String: String] { Self.dict }

    func testDictionaryBundlesAndLoads() {
        XCTAssertTrue(IPALocal.isAvailable, "cmudict-ipa.txt resource missing")
        XCTAssertFalse(dict.isEmpty, "dictionary failed to load/parse")
    }

    func testCommonWordsWithStress() {
        let cases: [(String, String)] = [
            ("apple", "ˈæpəl"), ("hello", "həˈloʊ"), ("through", "ˈθɹu"),
            ("language", "ˈlæŋɡwədʒ"), ("english", "ˈɪŋɡlɪʃ"),
        ]
        for (w, ipa) in cases {
            XCTAssertEqual(IPALocal.transcribe(w, using: dict, mode: .replace).result, ipa, w)
        }
    }

    func testReplaceMode() {
        let (out, hits) = IPALocal.transcribe("The quick brown fox.", using: dict, mode: .replace)
        XCTAssertEqual(hits, 4)
        XCTAssertEqual(out, "ðə ˈkwɪk ˈbɹaʊn ˈfɑks.")
    }

    func testAnnotateMode() {
        let (out, hits) = IPALocal.transcribe("The quick fox.", using: dict, mode: .annotate)
        XCTAssertEqual(hits, 3)
        XCTAssertEqual(out, "The [ðə] quick [ˈkwɪk] fox [ˈfɑks].")
    }

    func testUnknownWordsPassThroughBothModes() {
        XCTAssertEqual(IPALocal.transcribe("hello zzqwx", using: dict, mode: .replace).result,
                       "həˈloʊ zzqwx")
        XCTAssertEqual(IPALocal.transcribe("hello zzqwx", using: dict, mode: .annotate).result,
                       "hello [həˈloʊ] zzqwx")
    }

    func testQuotedWordsTranscribe() {
        // Leading/trailing apostrophes (quotes) are peeled off for lookup and
        // re-attached; internal apostrophes (contractions) are kept.
        XCTAssertEqual(IPALocal.transcribe("'hello'", using: dict, mode: .replace).result,
                       "'həˈloʊ'")
        XCTAssertEqual(IPALocal.transcribe("'hello'", using: dict, mode: .annotate).result,
                       "'hello' [həˈloʊ]")
        XCTAssertGreaterThanOrEqual(IPALocal.transcribe("don't", using: dict, mode: .replace).hits, 1)
    }

    func testCaseInsensitiveAndCurlyApostrophe() {
        XCTAssertTrue(IPALocal.transcribe("Apple", using: dict, mode: .replace).result.contains("ˈæpəl"))
        XCTAssertGreaterThanOrEqual(IPALocal.transcribe("don\u{2019}t", using: dict, mode: .replace).hits, 1)
    }

    func testModeSettingRoundTrips() {
        let id = "builtin.text.ipa_local"
        let original = IPALocalSettings.replaceMode(for: id)
        defer { IPALocalSettings.setReplaceMode(original, for: id) }
        XCTAssertFalse(IPALocalSettings.replaceMode(for: id))   // default = annotate
        IPALocalSettings.setReplaceMode(true, for: id)
        XCTAssertTrue(IPALocalSettings.replaceMode(for: id))
    }

    func testActionTypeScoped() {
        let item = ClipboardItem(id: UUID(), semantic: .text, createdAt: Date(),
            representations: [:], typesOrdered: [], previewText: "hello",
            previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
            sourceWindowTitle: nil, tags: [])
        XCTAssertTrue(IPALocalAction().appliesToContentType(item: item, context: ContextDetector.detect(item)))
    }
}
