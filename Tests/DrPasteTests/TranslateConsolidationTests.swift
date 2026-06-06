//
//  TranslateConsolidationTests.swift
//  DrPasteTests
//
//  Translate / Fix grammar are a single action each that preserves Rich /
//  Markdown formatting — the redundant "(rich)" duplicates are gone.
//

import XCTest
@testable import DrPaste

final class TranslateConsolidationTests: XCTestCase {

    private var byID: [String: CustomAIDescriptor] {
        Dictionary(uniqueKeysWithValues: DefaultAISeed.defaults().map { ($0.id, $0) })
    }

    func testRichDuplicatesRemovedFromSeed() {
        XCTAssertNil(byID["ai.rich.translate"])
        XCTAssertNil(byID["ai.rich.fix_grammar"])
    }

    func testTranslatePreservesFormattingAndCoversTypes() {
        let t = byID["ai.text.translate"]
        XCTAssertEqual(t?.preserveRichFormatting, true)
        XCTAssertEqual(Set(t?.applicableTypes ?? []), ["text", "richText", "markdown"])

        let g = byID["ai.text.fix_grammar"]
        XCTAssertEqual(g?.preserveRichFormatting, true)
        XCTAssertEqual(Set(g?.applicableTypes ?? []), ["text", "richText", "markdown"])
    }

    func testRestructuringActionsDoNotPreserve() {
        // Summarize rewrites/condenses — markup preservation is meaningless.
        XCTAssertEqual(byID["ai.text.summarize"]?.preserveRichFormatting, false)
    }

    func testPreserveFlagSurvivesCodableRoundTrip() throws {
        let d = CustomAIDescriptor(id: "x", title: "X", promptTemplate: "p",
                                   providerID: "", applicableTypes: ["text"],
                                   preserveRichFormatting: true)
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(CustomAIDescriptor.self, from: data)
        XCTAssertTrue(back.preserveRichFormatting)
        // Backward-compat: a JSON without the key decodes to false.
        let legacy = #"{"id":"y","title":"Y","promptTemplate":"p","providerID":"","applicableTypes":["text"]}"#
        let old = try JSONDecoder().decode(CustomAIDescriptor.self, from: Data(legacy.utf8))
        XCTAssertFalse(old.preserveRichFormatting)
    }
}
