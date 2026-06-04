//
//  SeedIntegrityTests.swift
//  DrPasteTests
//
//  Contract tests for bundled transformation descriptors and curated defaults.
//

import XCTest
@testable import DrPaste

final class SeedIntegrityTests: XCTestCase {

    func testDefaultTransformationIDsAreUniqueAndStable() {
        let defaults = DefaultTransformationSeed.defaults()
        let ids = defaults.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "Bundled transformation IDs must be unique.")
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("builtin.") })
        XCTAssertEqual(DefaultTransformationSeed.currentSeedVersion, 6)
    }

    func testDefaultTransformationsReferenceValidEnginesAndSemanticKinds() {
        for descriptor in DefaultTransformationSeed.defaults() {
            XCTAssertNotNil(
                TransformationEngine(rawValue: descriptor.engineID),
                "\(descriptor.id) references unknown engine \(descriptor.engineID)"
            )
            XCTAssertFalse(descriptor.applicableTypes.isEmpty, "\(descriptor.id) has no applicable types")
            for rawKind in descriptor.applicableTypes {
                XCTAssertNotNil(
                    SemanticKind(rawValue: rawKind),
                    "\(descriptor.id) references unknown semantic kind \(rawKind)"
                )
            }
        }
    }

    func testSeedContainsCurrentMigrationAnchors() {
        let byID = Dictionary(uniqueKeysWithValues: DefaultTransformationSeed.defaults().map { ($0.id, $0) })

        XCTAssertNil(byID["builtin.font_regional_indicator"])
        XCTAssertEqual(byID["builtin.font_markdown"]?.engine, .unicodeStyle)
        XCTAssertEqual(byID["builtin.font_markdown"]?.parameters["style"], UnicodeFontStyle.markdownAware.rawValue)
        XCTAssertEqual(Set(byID["builtin.md_headings"]?.applicableTypes ?? []), ["markdown", "text", "richText"])
        XCTAssertEqual(Set(byID["builtin.md_links"]?.applicableTypes ?? []), ["markdown", "text", "richText"])
    }

    func testCuratedDefaultsContainOnlyKnownActions() {
        let seeded = Set(DefaultTransformationSeed.defaults().map(\.id))
        let hardcoded: Set<String> = [
            "builtin.identity",
            "builtin.paste_as_text",
            "builtin.clean_formatting",
            "builtin.layout_repair",
            "builtin.rich_to_md",
            "builtin.rich_to_html",
            "builtin.rich_to_wiki",
            "builtin.rich_to_unicode_style",
            "builtin.url_just_domain",
            "builtin.url_md_link",
            "builtin.url_html_link",
            "builtin.table_to_json",
            "builtin.table_to_md",
            "builtin.md_to_rich",
            "builtin.generate_qr",
            "builtin.image_ocr",
            "builtin.image_decode_qr",
            "builtin.image_strip_metadata",
            "builtin.image_resize_1920",
            "builtin.image_grayscale",
            "builtin.image_rotate",
            "builtin.image_rotate_left",
            "builtin.image_ascii_art",
            "builtin.files_paths",
            "builtin.files_names",
            "builtin.files_md_links",
            "builtin.files_reveal",
            "builtin.type_slowly"
        ]
        let known = seeded.union(hardcoded)
        let unknown = CuratedDefaults.enabledByDefault.subtracting(known)

        XCTAssertTrue(unknown.isEmpty, "Curated defaults reference unknown action IDs: \(unknown.sorted())")
    }

    func testCuratedDefaultsKeepCoreGestureActionsEnabled() {
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.identity"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.paste_as_text"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.url_strip_tracking"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.image_ocr"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.type_slowly"))
    }
}
