//
//  ProviderResolverTests.swift
//  DrPasteTests
//
//  #A44 (0.57.0) contract tests for the unified provider-resolution
//  helper. Every fixture builds a `ProvidersConfig` in-memory and
//  drives `ProviderResolver.resolve` directly so the assertions never
//  touch Keychain or the live registry.
//

import XCTest
@testable import DrPaste

final class ProviderResolverTests: XCTestCase {

    // MARK: Fixtures

    private func makeOpenAI(id: String = "openai") -> ConfiguredProvider {
        ConfiguredProvider(id: id, kind: .openai, displayName: "OpenAI",
                           model: "gpt-5",
                           baseURL: "https://api.openai.com/v1", enabled: true)
    }

    private func makeAnthropic(id: String = "anthropic") -> ConfiguredProvider {
        ConfiguredProvider(id: id, kind: .anthropic, displayName: "Anthropic",
                           model: "claude-sonnet-4.5", baseURL: nil, enabled: true)
    }

    private func makeGemini(id: String = "gemini") -> ConfiguredProvider {
        ConfiguredProvider(id: id, kind: .gemini, displayName: "Gemini",
                           model: "gemini-2.5-flash-image", baseURL: nil, enabled: true)
    }

    private func makeOpenRouter(id: String = "openrouter") -> ConfiguredProvider {
        ConfiguredProvider(id: id, kind: .openrouter, displayName: "OpenRouter",
                           model: "google/gemini-2.5-flash-image",
                           baseURL: "https://openrouter.ai/api/v1", enabled: true)
    }

    private func makeCustom(id: String = "custom") -> ConfiguredProvider {
        ConfiguredProvider(id: id, kind: .custom, displayName: "Custom",
                           model: "local-model",
                           baseURL: "http://localhost:9999/v1", enabled: true)
    }

    private func makeConfig(_ providers: [ConfiguredProvider],
                            defaultID: String? = nil) -> ProvidersConfig {
        ProvidersConfig(defaultProviderID: defaultID, providers: providers)
    }

    private func keyedSet(_ ids: [String]) -> (String) -> Bool {
        let set = Set(ids)
        return { set.contains($0) }
    }

    // MARK: Explicit per-action wins

    func testExplicitNominalProviderResolvesWithoutReroute() {
        let cfg = makeConfig([makeOpenAI(), makeAnthropic()], defaultID: "anthropic")
        let r = ProviderResolver.resolve(
            nominalProviderID: "openai",
            operationKind: .text,
            config: cfg,
            hasKey: keyedSet(["openai", "anthropic"]))
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.providerID, "openai")
        XCTAssertFalse(r?.isRerouted ?? true)
        XCTAssertNil(r?.rerouteReason)
    }

    // MARK: Capability mismatch reroutes with a reason

    func testAnthropicForImageEditRoutesToImageCapableProvider() {
        let cfg = makeConfig([makeAnthropic(), makeGemini()], defaultID: "anthropic")
        let r = ProviderResolver.resolve(
            nominalProviderID: "anthropic",
            operationKind: .imageEdit,
            config: cfg,
            hasKey: keyedSet(["anthropic", "gemini"]))
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.providerID, "gemini")
        XCTAssertTrue(r?.isRerouted ?? false)
        XCTAssertNotNil(r?.rerouteReason)
        XCTAssertTrue(r?.rerouteReason?.contains("image") ?? false)
    }

    // MARK: Cost-rank fallback for image-edit when nothing pinned

    func testFollowDefaultPicksCheapestImageProvider() {
        // Two image-capable providers, both keyed; cheaper one wins.
        let cfg = makeConfig([makeOpenAI(), makeGemini()], defaultID: nil)
        let r = ProviderResolver.resolve(
            nominalProviderID: nil,
            operationKind: .imageEdit,
            config: cfg,
            hasKey: keyedSet(["openai", "gemini"]))
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.providerKind.imageEditCostRank,
                       ProviderKind.gemini.imageEditCostRank,
                       "gemini is the cheapest image-edit provider per cost rank")
    }

    // MARK: No image-capable provider → nil

    func testImageEditWithNoCapableProviderReturnsNil() {
        let cfg = makeConfig([makeAnthropic()], defaultID: "anthropic")
        let r = ProviderResolver.resolve(
            nominalProviderID: nil,
            operationKind: .imageEdit,
            config: cfg,
            hasKey: keyedSet(["anthropic"]))
        XCTAssertNil(r)
    }

    // MARK: Missing API key on nominal → reroute

    func testNominalWithoutKeyFallsBackToDefault() {
        let cfg = makeConfig([makeOpenAI(), makeAnthropic()], defaultID: "anthropic")
        // OpenAI is the nominal pick but lacks a key.
        let r = ProviderResolver.resolve(
            nominalProviderID: "openai",
            operationKind: .text,
            config: cfg,
            hasKey: keyedSet(["anthropic"]))
        XCTAssertEqual(r?.providerID, "anthropic")
        XCTAssertTrue(r?.isRerouted ?? false)
        XCTAssertTrue(r?.rerouteReason?.contains("API key") ?? false)
    }

    // MARK: Disabled nominal → reroute

    func testDisabledNominalProviderFallsBackToDefault() {
        var openai = makeOpenAI(); openai.enabled = false
        let cfg = makeConfig([openai, makeAnthropic()], defaultID: "anthropic")
        let r = ProviderResolver.resolve(
            nominalProviderID: "openai",
            operationKind: .text,
            config: cfg,
            hasKey: keyedSet(["openai", "anthropic"]))
        XCTAssertEqual(r?.providerID, "anthropic")
        XCTAssertTrue(r?.isRerouted ?? false)
        XCTAssertTrue(r?.rerouteReason?.contains("disabled") ?? false)
    }

    // MARK: Empty config → nil + recovery hint

    func testNoProvidersConfiguredReturnsNil() {
        let cfg = makeConfig([], defaultID: nil)
        let r = ProviderResolver.resolve(
            nominalProviderID: nil,
            operationKind: .text,
            config: cfg,
            hasKey: { _ in false })
        XCTAssertNil(r)
    }

    // MARK: Runtime credential adapter

    func testRuntimeCredentialAdapterAllowsNoAuthCustomTextButNotImage() {
        let cfg = makeConfig([makeCustom()], defaultID: "custom")

        XCTAssertTrue(ProviderResolver.runtimeHasCredential(
            providerID: "custom",
            operationKind: .text,
            config: cfg
        ))
        XCTAssertFalse(ProviderResolver.runtimeHasCredential(
            providerID: "custom",
            operationKind: .imageEdit,
            config: cfg
        ))
    }
}
