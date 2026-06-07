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

    func testTypeSlowlyScope() {
        let a = TypeSlowlyAction()
        for k in [SemanticKind.text, .url, .markdown] {
            let i = item(k, "some short value")
            XCTAssertTrue(a.isApplicable(item: i, context: ContextDetector.detect(i)), "should apply to \(k)")
        }
        // #A78 — excluded: code / JSON (structure), table (alignment),
        // richText (formatting). Plain keystrokes would mangle all of them.
        for k in [SemanticKind.code, .json, .table, .richText] {
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
                   "ai.code.explain", "ai.code.find_bugs", "ai.text.clean_ocr",
                   "ai.text.image_whiteboard"] {   // part of the wow / first-open set
            XCTAssertTrue(CuratedDefaults.isEnabledByDefault(id), "\(id) should be ON")
        }
        for id in ["ai.text.ipa_transcription", "ai.image.sketch", "ai.image.watercolor",
                   "ai.image.cartoon", "ai.text.latin_to_cyrillic",
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

    func testContextGatesInSeed() {
        let t = transformByID
        XCTAssertEqual(Set(t["builtin.text.trim"]?.requiredTraits ?? []), ["messySpacing", "wrappedLines"])
        XCTAssertEqual(Set(t["builtin.text.title_case"]?.requiredTraits ?? []), ["uppercaseHeavy", "lowercaseHeavy"])
        XCTAssertEqual(Set(t["builtin.text.sort_lines"]?.requiredTraits ?? []), ["multiline"])
        XCTAssertEqual(Set(t["builtin.url.strip_tracking"]?.requiredTraits ?? []), ["hasTrackingParams"])
        XCTAssertEqual(t["builtin.text.font_bold"]?.requiredTraits, ["fromChat"])
        XCTAssertEqual(t["builtin.text.uwu_speak"]?.requiredTraits, ["fromChat"])
    }

    func testGenerateQRURLOnly() {
        let a = GenerateQRAction()
        // #A78 — QR only for URLs ("scan this link").
        let url = item(.url, "https://x.com")
        XCTAssertTrue(a.isApplicable(item: url, context: ContextDetector.detect(url)))
        // Plain text / code / JSON / table → no QR chip.
        for k in [SemanticKind.text, .code, .json, .table] {
            let i = item(k, "the meeting is tomorrow")
            XCTAssertFalse(a.isApplicable(item: i, context: ContextDetector.detect(i)), "QR must NOT apply to \(k)")
        }
    }

    func testTidyNicheActionsRetired() {
        // Normalize spaces / Collapse blank lines no longer ship as standalone
        // seeds — Tidy text covers both.
        XCTAssertNil(transformByID["builtin.text.normalize_spaces"])
        XCTAssertNil(transformByID["builtin.text.collapse_blank_lines"])
    }

    func testMarkdownToPlainRetired() {
        // Redundant with "Plain text", which runs mdToPlain itself.
        XCTAssertNil(transformByID["builtin.md.to_plain"])
    }

    func testA78SeedGatesAndScoping() {
        let t = transformByID
        // Case ops gated like Title/Sentence case.
        XCTAssertEqual(Set(t["builtin.text.uppercase"]?.requiredTraits ?? []), ["uppercaseHeavy", "lowercaseHeavy"])
        XCTAssertEqual(Set(t["builtin.text.lowercase"]?.requiredTraits ?? []), ["uppercaseHeavy", "lowercaseHeavy"])
        // Zalgo gated to chat.
        XCTAssertEqual(t["builtin.text.zalgo"]?.requiredTraits, ["fromChat"])
        // Wrappers scoped off plain text; quotes → markdown, code-block → code.
        XCTAssertEqual(Set(t["builtin.text.wrap_quotes"]?.applicableTypes ?? []), ["markdown"])
        XCTAssertEqual(Set(t["builtin.code.wrap_block"]?.applicableTypes ?? []), ["code"])
        // Per-type leak fixes: URL enc/dec off code, Validate JSON json-only.
        XCTAssertEqual(Set(t["builtin.url.decode"]?.applicableTypes ?? []), ["text", "url"])
        XCTAssertEqual(Set(t["builtin.url.encode"]?.applicableTypes ?? []), ["text", "url"])
        XCTAssertEqual(Set(t["builtin.json.validate"]?.applicableTypes ?? []), ["json"])
    }

    func testA78CuratedDefaults() {
        // Moved OFF the always-on strip.
        for id in ["builtin.text.word_count", "builtin.text.latin_to_cyrillic",
                   "ai.text.make_shorter", "ai.text.improve_clarity"] {
            XCTAssertFalse(CuratedDefaults.isEnabledByDefault(id), "\(id) should be OFF by default")
        }
        // Tight AI core + the kept tone-shifts stay ON.
        for id in ["ai.text.fix_grammar", "ai.text.translate", "ai.text.summarize",
                   "ai.text.formal_tone", "ai.text.make_friendly"] {
            XCTAssertTrue(CuratedDefaults.isEnabledByDefault(id), "\(id) should stay ON")
        }
    }

    private func makeAction(_ id: String) -> CustomTransformationAction? {
        guard let d = transformByID[id] else { return nil }
        let kinds = Set(d.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
        return CustomTransformationAction(
            id: d.id, title: d.title, descriptor: d,
            applicableSet: kinds.isEmpty ? [.text, .richText, .markdown, .code] : kinds)
    }

    private func richItem(_ text: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: .richText, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: text,
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [])
    }

    func testStructuralActionsDoNotBridgeToRichText() {
        // These flatten / re-encode and must NOT surface on a rich-text clip.
        let denied = ["builtin.text.snake_case", "builtin.text.sort_lines",
                      "builtin.text.base64_encode", "builtin.url.encode",
                      "builtin.text.slugify", "builtin.text.word_count",
                      "builtin.text.wrap_quotes", "builtin.code.tabs_to_spaces",
                      "builtin.text.remove_line_breaks"]
        let it = richItem("alpha\nbeta\ngamma")
        let ctx = ContextDetector.detect(it)
        for id in denied {
            let a = makeAction(id)
            XCTAssertNotNil(a, "\(id) missing from seed")
            XCTAssertFalse(a?.appliesToContentType(item: it, context: ctx) ?? true,
                           "\(id) must NOT apply to rich text")
        }
    }

    func testFormattingActionsStillBridgeToRichText() {
        // UPPERCASE preserves formatting and remains useful on a rich clip.
        let a = makeAction("builtin.text.uppercase")
        let it = richItem("hello world")
        XCTAssertTrue(a?.appliesToContentType(item: it, context: ContextDetector.detect(it)) ?? false,
                      "UPPERCASE should still bridge to rich text")
    }

    func testIPAActionSeeded() {
        let byID = Dictionary(uniqueKeysWithValues:
            DefaultAISeed.defaults().map { ($0.id, $0) })
        let ipa = byID["ai.text.ipa_transcription"]
        XCTAssertNotNil(ipa)
        XCTAssertEqual(ipa?.title, "IPA")
    }
}
