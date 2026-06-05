//
//  MetadataIntegrityTests.swift
//  DrPasteTests
//
//  Ensures Settings/Browse descriptions do not drift away from bundled actions.
//

import XCTest
@testable import DrPaste

final class MetadataIntegrityTests: XCTestCase {

    func testCuratedDefaultsHaveSettingsDescriptionsOrSeedTitles() {
        let seededIDs = Set(DefaultTransformationSeed.defaults().map(\.id))
        let missing = CuratedDefaults.enabledByDefault.filter { id in
            BuiltinActionMetadata.descriptions[id] == nil && !seededIDs.contains(id)
        }

        XCTAssertTrue(missing.isEmpty, "Curated hardcoded actions missing descriptions: \(missing.sorted())")
    }

    func testMetadataDoesNotDescribeRemovedRegionalIndicatorAction() {
        XCTAssertNil(BuiltinActionMetadata.descriptions["builtin.text.font_regional_indicator"])
    }

    func testImportantNewActionsHaveDescriptions() {
        XCTAssertNotNil(BuiltinActionMetadata.descriptions["builtin.md.to_rich"])
        XCTAssertNotNil(BuiltinActionMetadata.descriptions["builtin.image.to_ascii_art"])
        XCTAssertNotNil(BuiltinActionMetadata.descriptions["builtin.text.type_slowly"])
    }

    func testDescriptionsAreHumanReadableSentences() {
        for (id, description) in BuiltinActionMetadata.descriptions {
            XCTAssertFalse(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(id) has empty description")
            XCTAssertGreaterThan(description.count, 12, "\(id) description is too terse")
        }
    }
}
