//
//  ProviderKindTests.swift
//  DrPasteTests
//
//  Pure capability tests for provider catalogue metadata.
//

import XCTest
@testable import DrPaste

final class ProviderKindTests: XCTestCase {

    func testImageEditCapabilityMatchesCostRank() {
        for kind in ProviderKind.allCases {
            if kind.supportsImageEdit {
                XCTAssertLessThan(kind.imageEditCostRank, Int.max, "\(kind) supports image edit but has no finite cost rank")
            } else {
                XCTAssertEqual(kind.imageEditCostRank, Int.max, "\(kind) does not support image edit but has finite cost rank")
            }
        }
    }

    func testImageFallbackOrdering() {
        let imageKinds = ProviderKind.allCases
            .filter(\.supportsImageEdit)
            .sorted { $0.imageEditCostRank < $1.imageEditCostRank }

        XCTAssertEqual(imageKinds, [.gemini, .openrouter, .openai, .custom])
    }

    func testLocalProvidersRequireBaseURLButNotAPIKey() {
        for kind in [ProviderKind.ollama, .lmstudio, .llamaCpp] {
            XCTAssertTrue(kind.isLocal)
            XCTAssertFalse(kind.requiresAPIKey)
            XCTAssertTrue(kind.requiresBaseURL)
            XCTAssertNotNil(kind.defaultBaseURL)
        }
    }

    func testCloudProvidersHaveLabelsIconsAndModels() {
        for kind in ProviderKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.badgeLabel.isEmpty)
            XCTAssertFalse(kind.iconName.isEmpty)
            XCTAssertFalse(kind.defaultModel.isEmpty)
        }
    }

    func testCustomProviderIsNotLocalButRequiresBaseURL() {
        XCTAssertFalse(ProviderKind.custom.isLocal)
        XCTAssertFalse(ProviderKind.custom.requiresAPIKey)
        XCTAssertTrue(ProviderKind.custom.requiresBaseURL)
    }

    func testCloudflareWorkersRequiresCustomAccountURL() {
        XCTAssertFalse(ProviderKind.cloudflareWorkers.isLocal)
        XCTAssertTrue(ProviderKind.cloudflareWorkers.requiresAPIKey)
        XCTAssertTrue(ProviderKind.cloudflareWorkers.requiresBaseURL)
        XCTAssertTrue(ProviderKind.cloudflareWorkers.defaultBaseURL?.contains("YOUR_ACCOUNT_ID") == true)
    }
}
