//
//  SeedIntegrityTests.swift
//  DrPasteTests
//
//  Contract tests for bundled transformation descriptors and curated defaults.
//
//  IDs follow convention v2 (#A74, 0.56.0): `builtin.<content_kind>.<verb_noun>`.
//

import XCTest
@testable import DrPaste

final class SeedIntegrityTests: XCTestCase {

    func testDefaultTransformationIDsAreUniqueAndStable() {
        let defaults = DefaultTransformationSeed.defaults()
        let ids = defaults.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "Bundled transformation IDs must be unique.")
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("builtin.") })
        XCTAssertEqual(DefaultTransformationSeed.currentSeedVersion, 9)
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

        // Discontinued descriptor stays out.
        XCTAssertNil(byID["builtin.text.font_regional_indicator"])
        // Markdown-aware fancy font still present and engine-consistent.
        XCTAssertEqual(byID["builtin.text.font_markdown"]?.engine, .unicodeStyle)
        XCTAssertEqual(byID["builtin.text.font_markdown"]?.parameters["style"], UnicodeFontStyle.markdownAware.rawValue)
        // Extract headings covers Markdown + rich text; extract links stays
        // markdown-scoped (it's off by default — the universal text.extract_links wins).
        XCTAssertEqual(Set(byID["builtin.md.extract_headings"]?.applicableTypes ?? []), ["markdown", "richText"])
        XCTAssertEqual(Set(byID["builtin.md.extract_links"]?.applicableTypes ?? []), ["markdown"])
    }

    /// IDs of hardcoded standalone actions registered in main.swift —
    /// those that don't go through DefaultTransformationSeed. Kept as a
    /// shared list so both the curated-defaults check and the phantom-
    /// metadata check below agree on the universe of real action IDs.
    static let standaloneActionIDs: Set<String> = [
        "builtin.identity",
        "builtin.text.layout_repair",
        "builtin.text.type_slowly",
        "builtin.text.generate_qr",
        "builtin.text.unit_conversion",
        "builtin.rich.strip_formatting",
        "builtin.rich.to_md",
        "builtin.rich.to_html",
        "builtin.rich.to_wiki",
        "builtin.rich.to_unicode_styled",
        "builtin.url.extract_domain",
        "builtin.url.to_md_link",
        "builtin.url.to_html_link",
        "builtin.url.preview_card",
        "builtin.table.to_json",
        "builtin.table.to_md",
        "builtin.table.to_wiki",
        "builtin.table.to_rich",
        "builtin.table.to_html",
        "builtin.md.to_rich",
        "builtin.md.to_wiki",
        "builtin.json.flatten",
        "builtin.json.remove_nulls",
        "builtin.image.ocr",
        "builtin.image.decode_qr",
        "builtin.image.info",
        "builtin.image.strip_metadata",
        "builtin.image.resize",
        "builtin.image.compress_jpeg",
        "builtin.image.to_grayscale",
        "builtin.image.invert_colors",
        "builtin.image.rotate_right",
        "builtin.image.rotate_left",
        "builtin.image.to_ascii_art",
        "builtin.files.copy_paths",
        "builtin.files.copy_filenames",
        "builtin.files.to_md_links",
        "builtin.files.reveal_in_finder",
        "builtin.files.copy_shell_safe_paths",
        "builtin.files.to_rich_icons",
        "builtin.files.extract_image"
    ]

    /// Every action ID known to be real: seeded transformations + the
    /// hardcoded standalone registrations.
    static var knownActionIDs: Set<String> {
        Set(DefaultTransformationSeed.defaults().map(\.id)).union(standaloneActionIDs)
    }

    func testCuratedDefaultsContainOnlyKnownActions() {
        let unknown = CuratedDefaults.enabledByDefault.subtracting(Self.knownActionIDs)
        XCTAssertTrue(unknown.isEmpty, "Curated defaults reference unknown action IDs: \(unknown.sorted())")
    }

    /// Reverse-direction invariant: no built-in description may be keyed on
    /// an action ID that isn't actually registered. This catches the
    /// rename-drift class of bug (e.g. a description left under the old
    /// `builtin.image_strip_metadata` after the action became
    /// `builtin.image.strip_metadata`) that the curated-defaults check
    /// alone misses — there the metadata silently fails to resolve and the
    /// action shows with no description / wrong icon. Note: built-in icons
    /// live in a `switch` (not enumerable), so only descriptions are
    /// machine-checkable here.
    func testNoPhantomBuiltinDescriptions() {
        let phantom = Set(BuiltinActionMetadata.descriptions.keys)
            .subtracting(Self.knownActionIDs)
        XCTAssertTrue(phantom.isEmpty,
                      "Descriptions keyed on unknown/phantom action IDs: \(phantom.sorted())")
    }

    func testCuratedDefaultsKeepCoreGestureActionsEnabled() {
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.identity"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.rich.strip_formatting"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.url.strip_tracking"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.image.ocr"))
        XCTAssertTrue(CuratedDefaults.isEnabledByDefault("builtin.text.type_slowly"))
    }
}
