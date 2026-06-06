//
//  ApplicabilityScopingTests.swift
//  DrPasteTests
//
//  Actions appear only where they make sense: Convert units in prose only,
//  Pretty Code (local) in Code only, plus the new IPA action is seeded.
//

import XCTest
@testable import DrPaste

final class ApplicabilityScopingTests: XCTestCase {

    private func item(_ k: SemanticKind, _ text: String = "It is 5 km away") -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: k, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: text,
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [])
    }

    func testConvertUnitsProseOnly() {
        let a = UnitConversionAction()
        for k in [SemanticKind.text, .richText, .markdown] {
            let i = item(k)
            XCTAssertTrue(a.isApplicable(item: i, context: ContextDetector.detect(i)), "should apply to \(k)")
        }
        for k in [SemanticKind.url, .code, .json, .table] {
            let i = item(k)
            XCTAssertFalse(a.isApplicable(item: i, context: ContextDetector.detect(i)), "must NOT apply to \(k)")
        }
    }

    func testPrettyCodeLocalCoversCodeAndJSONOnly() {
        let byID = Dictionary(uniqueKeysWithValues:
            DefaultTransformationSeed.defaults().map { ($0.id, $0) })
        // Code + JSON (replaces the retired dedicated Pretty JSON), never prose.
        XCTAssertEqual(Set(byID["builtin.code.pretty_local"]?.applicableTypes ?? []), ["code", "json"])
    }

    func testTypeSlowlyNotForCodeOrJSON() {
        let a = TypeSlowlyAction()
        for k in [SemanticKind.text, .url, .markdown] {
            let i = item(k, "some short value")
            XCTAssertTrue(a.isApplicable(item: i, context: ContextDetector.detect(i)), "should apply to \(k)")
        }
        for k in [SemanticKind.code, .json] {
            let i = item(k, "let x = 42")
            XCTAssertFalse(a.isApplicable(item: i, context: ContextDetector.detect(i)), "must NOT apply to \(k)")
        }
    }

    // MARK: full-audit corrections

    private var transformByID: [String: CustomTransformationDescriptor] {
        Dictionary(uniqueKeysWithValues: DefaultTransformationSeed.defaults().map { ($0.id, $0) })
    }

    func testCaseOpsNotOnCode() {
        // UPPER/lower would mangle code identifiers — prose only.
        XCTAssertFalse(transformByID["builtin.text.uppercase"]?.applicableTypes.contains("code") ?? true)
        XCTAssertFalse(transformByID["builtin.text.lowercase"]?.applicableTypes.contains("code") ?? true)
    }

    func testStripTagsNotOnRichText() {
        XCTAssertFalse(transformByID["builtin.html.strip_tags"]?.applicableTypes.contains("richText") ?? true)
    }

    func testSummarizeNotOnCode() {
        let ai = Dictionary(uniqueKeysWithValues: DefaultAISeed.defaults().map { ($0.id, $0) })
        XCTAssertFalse(ai["ai.text.summarize"]?.applicableTypes.contains("code") ?? true)
    }

    func testDuplicateResizeRetired() {
        // The legacy resize_max_1920 is gone; only the universal Resize remains.
        XCTAssertNil(BuiltinActionMetadata.descriptions["builtin.image.resize_max_1920"])
        XCTAssertFalse(CuratedDefaults.enabledByDefault.contains("builtin.image.resize_max_1920"))
        XCTAssertTrue(CuratedDefaults.enabledByDefault.contains("builtin.image.resize"))
    }

    func testAIDefaultsCurated() {
        for id in ["ai.text.summarize", "ai.text.translate", "ai.text.fix_grammar",
                   "ai.code.explain", "ai.code.find_bugs", "ai.text.clean_ocr"] {
            XCTAssertTrue(CuratedDefaults.isEnabledByDefault(id), "\(id) should be ON")
        }
        for id in ["ai.text.ipa_transcription", "ai.image.sketch", "ai.image.watercolor",
                   "ai.image.cartoon", "ai.text.image_whiteboard", "ai.text.latin_to_cyrillic",
                   "ai.code.translate", "ai.code.pretty"] {
            XCTAssertFalse(CuratedDefaults.isEnabledByDefault(id), "\(id) should be OFF (novelty)")
        }
    }

    func testCodeTranslatePromptHasNoPlaceholder() {
        let ai = Dictionary(uniqueKeysWithValues: DefaultAISeed.defaults().map { ($0.id, $0) })
        XCTAssertFalse(ai["ai.code.translate"]?.promptTemplate.contains("FILL IN") ?? true,
                       "unfinished <FILL IN…> placeholder still shipped")
    }

    func testTidyTextNotOnCode() {
        XCTAssertFalse(transformByID["builtin.text.trim"]?.applicableTypes.contains("code") ?? true)
    }

    func testIPAActionSeeded() {
        let byID = Dictionary(uniqueKeysWithValues:
            DefaultAISeed.defaults().map { ($0.id, $0) })
        let ipa = byID["ai.text.ipa_transcription"]
        XCTAssertNotNil(ipa)
        XCTAssertEqual(ipa?.title, "Phonetic transcription (IPA)")
    }
}
