//
//  AIProvider.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Multi-provider AI architecture:
//  - protocol AIProvider — single interface for all providers
//  - AIProviderRegistry — singleton holding a list of ConfiguredProvider
//  - AnthropicProvider, OpenAICompatibleProvider, GeminiProvider — concrete impls
//  - APIKeyStorage — Keychain-based key storage
//  - providers.json v2 — new format with a providers array plus v1 migration
//

import Foundation
import AppKit
import SwiftUI

// MARK: - Protocol

protocol AIProvider {
    var id: String { get }
    var displayName: String { get }
    var model: String { get }
    var isLocal: Bool { get }
    /// True when the provider has everything it needs (API key for cloud, base URL for local).
    var isReady: Bool { get }
    func run(prompt: String, input: String) async throws -> String

    /// Streaming variant — yields partial token deltas as the provider's
    /// SSE / NDJSON response arrives. Default implementation falls back to
    /// `run()` and emits the entire result in a single chunk, so providers
    /// without streaming support keep working without code changes. SSE-
    /// capable providers (Anthropic Messages, OpenAI chat/completions,
    /// Gemini streamGenerateContent, Ollama, …) override this to yield
    /// per-token deltas as they arrive.
    func stream(prompt: String, input: String) -> AsyncThrowingStream<String, Error>
}

extension AIProvider {
    /// Default fallback wrapping the non-streaming `run()` so any caller
    /// can use the streaming entry point uniformly. Result is emitted as
    /// one chunk on completion.
    func stream(prompt: String, input: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await run(prompt: prompt, input: input)
                    if !result.isEmpty { continuation.yield(result) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum AIProviderError: Error {
    case missingAPIKey
    case missingBaseURL
    case http(status: Int, body: String)
    case decode(String)
    case networkUnreachable
}

// MARK: - Provider kinds

enum ProviderKind: String, Codable, CaseIterable {
    case anthropic          // Claude
    case openai             // GPT
    case gemini             // Google
    case grok               // xAI
    case mistral
    case deepseek
    case openrouter         // gateway — one key, many vendors
    case together           // gateway — open-source focused
    case cloudflareWorkers  // gateway — Cloudflare's own inference
    case groq               // fast inference (LPU hardware)
    case cerebras           // fast inference (wafer-scale hardware)
    case ollama             // local
    case lmstudio           // local
    case llamaCpp           // local
    case custom             // OpenAI-compatible custom endpoint

    var displayName: String {
        switch self {
        case .anthropic:         return "Anthropic Claude"
        case .openai:            return "OpenAI GPT"
        case .gemini:            return "Google Gemini"
        case .grok:              return "xAI Grok"
        case .mistral:           return "Mistral"
        case .deepseek:          return "DeepSeek"
        case .openrouter:        return "OpenRouter"
        case .together:          return "Together AI"
        case .cloudflareWorkers: return "Cloudflare Workers AI"
        case .groq:              return "Groq"
        case .cerebras:          return "Cerebras"
        case .ollama:            return "Ollama"
        case .lmstudio:          return "LM Studio"
        case .llamaCpp:          return "llama.cpp"
        case .custom:            return "Custom"
        }
    }

    /// Short label for the provider badge in the UI (HUD action list).
    var badgeLabel: String {
        switch self {
        case .anthropic:         return "Claude"
        case .openai:            return "GPT"
        case .gemini:            return "Gemini"
        case .grok:              return "Grok"
        case .mistral:           return "Mistral"
        case .deepseek:          return "DeepSeek"
        case .openrouter:        return "OpenRouter"
        case .together:          return "Together"
        case .cloudflareWorkers: return "CF Workers"
        case .groq:              return "Groq"
        case .cerebras:          return "Cerebras"
        case .ollama:            return "Ollama"
        case .lmstudio:          return "LM Studio"
        case .llamaCpp:          return "llama.cpp"
        case .custom:            return "Custom"
        }
    }

    /// SF Symbol name used as the provider icon in the action list. Semantic
    /// symbols are preferred — Apple-native and free of trademark issues.
    /// All AI providers (cloud OR local) get an "AI-flavoured" icon — never
    /// a plain Mac silhouette — so AI actions read as distinct from
    /// built-in / transformation actions at a glance in the Settings list.
    var iconName: String {
        switch self {
        case .anthropic:         return "a.circle.fill"           // Anthropic "A"
        case .openai:            return "circle.hexagongrid.fill"  // OpenAI hexagon pattern
        case .gemini:            return "sparkle"                  // Gemini sparkle
        case .grok:              return "x.circle.fill"            // X / Grok
        case .mistral:           return "wind"                     // Mistral = wind
        case .deepseek:          return "magnifyingglass.circle.fill"
        // OpenRouter: many lines merging into one — visual metaphor for
        // "many models, one key". `arrow.triangle.merge` reads as a
        // router / multiplexer at a glance.
        case .openrouter:        return "arrow.triangle.merge"
        // Together AI — another gateway, but different visual metaphor
        // so it doesn't collide with OpenRouter in the picker list.
        // `network` reads as "many networked sources, one access point".
        case .together:          return "network"
        // Cloudflare Workers AI — Cloudflare's brand cloud + their
        // famous orange. `cloud.bolt.fill` blends "cloud platform" with
        // "fast inference" without colliding with either Ollama
        // (cube.fill) or Groq (bolt.fill).
        case .cloudflareWorkers: return "cloud.bolt.fill"
        // Groq — LPU custom hardware, ultra-fast inference. Pure
        // `bolt.fill` for speed.
        case .groq:              return "bolt.fill"
        // Cerebras — wafer-scale chips, also speed-focused but
        // differentiated from Groq via `gauge.with.dots.needle.67percent`
        // (high speedometer).
        case .cerebras:          return "gauge.with.dots.needle.67percent"
        // Local providers: each gets a distinct AI-coded glyph rather than
        // a generic Mac chassis. Ollama's `cube.fill` echoes its containerised
        // model packaging; LM Studio's `square.stack.3d.up.fill` shows stacked
        // model layers; llama.cpp's `chevron.left.forwardslash.chevron.right`
        // signals its CLI / code-runtime nature; custom's `link.circle.fill`
        // says "user-pointed endpoint".
        case .ollama:            return "cube.fill"
        case .lmstudio:          return "square.stack.3d.up.fill"
        case .llamaCpp:          return "chevron.left.forwardslash.chevron.right"
        case .custom:            return "link.circle.fill"
        }
    }

    /// Brand colour for the provider icon. Mirrors the badge palette used in
    /// the HUD action list so the same brand is identifiable in both places.
    /// Local providers used to share a flat gray that made local-model AI
    /// actions look indistinguishable from built-in non-AI actions — they
    /// now get their own bright hues, picked to avoid collisions with the
    /// cloud-provider palette above (orange / green / blue / primary /
    /// purple / indigo).
    var brandColor: Color {
        switch self {
        case .anthropic:         return .orange
        case .openai:            return .green
        case .gemini:            return .blue
        case .grok:              return .primary
        case .mistral:           return .purple
        case .deepseek:          return .indigo
        // OpenRouter — pink stands out from the cloud-vendor palette
        // so a gateway-routed action reads as "not a direct vendor
        // call" at a glance.
        case .openrouter:        return .pink
        // Together AI — deep navy distinct from gemini's .blue;
        // matches their actual brand mark.
        case .together:          return Color(red: 0.12, green: 0.25, blue: 0.78)
        // Cloudflare Workers AI — Cloudflare brand orange, distinct
        // from Anthropic's system .orange by being slightly redder.
        case .cloudflareWorkers: return Color(red: 0.96, green: 0.50, blue: 0.10)
        // Groq — red matches their actual brand colour and reads as
        // "fast / urgent" alongside the bolt icon.
        case .groq:              return .red
        // Cerebras — magenta-purple, distinct from Mistral's .purple
        // by leaning more towards red.
        case .cerebras:          return Color(red: 0.70, green: 0.20, blue: 0.55)
        case .ollama:            return .cyan
        case .lmstudio:          return .teal
        case .llamaCpp:          return .brown
        case .custom:            return .mint
        }
    }

    var isLocal: Bool {
        switch self {
        case .ollama, .lmstudio, .llamaCpp: return true
        case .custom: return false   // could be local or remote; treated as remote by default.
        default: return false
        }
    }

    var requiresAPIKey: Bool { !isLocal && self != .custom ? true : false }
    /// Most cloud providers have a hardcoded base URL in `makeConcrete`;
    /// only providers where the user MUST supply something (local apps,
    /// custom OpenAI-compatible endpoints, and Cloudflare Workers AI
    /// which bakes the account ID into the URL) need to expose the
    /// base-URL field in the editor.
    var requiresBaseURL: Bool {
        isLocal || self == .custom || self == .cloudflareWorkers
    }

    /// Whether this provider can run image-in / image-out edit
    /// requests (used by `AIImageAction`). Drives the Edit Action
    /// editor's Provider picker filter in Image mode — only kinds
    /// with `supportsImageEdit == true` are listed.
    ///
    /// Supported today:
    ///   • OpenAI       — `/v1/images/edits` with gpt-image-1
    ///   • Gemini       — `:generateContent` with
    ///                    gemini-2.5-flash-image-preview (or
    ///                    -native variants), inlineData base64
    ///   • OpenRouter   — `/v1/chat/completions` with a multimodal
    ///                    image-capable model (Gemini Flash Image,
    ///                    Flux via fal-ai/*, …) — response contains
    ///                    an inline image part the gateway forwarded
    ///                    from the underlying vendor.
    ///   • Custom       — OpenAI-compatible custom endpoint. We
    ///                    can't know in advance whether the user's
    ///                    URL implements /images/edits or not, so
    ///                    we let it through and dispatch as OpenAI-
    ///                    shape. If the endpoint doesn't speak it,
    ///                    the HTTP error message surfaces in the
    ///                    failure notice and the user knows to
    ///                    switch providers.
    ///
    /// Returns false for the rest: Anthropic / Claude has vision
    /// input but no image generation; OpenAI-compat gateways with
    /// known text-only models (Together, Groq, Cerebras) don't
    /// expose /images/edits; local inference servers (Ollama, LM
    /// Studio, llama.cpp) ship text-only models. Cloudflare Workers
    /// AI hosts Flux models but its API shape is per-model
    /// proprietary and not wired here yet — would be a follow-up.
    var supportsImageEdit: Bool {
        switch self {
        case .openai, .gemini, .openrouter, .custom:
            return true
        case .anthropic, .grok, .mistral, .deepseek,
             .together, .cloudflareWorkers, .groq, .cerebras,
             .ollama, .lmstudio, .llamaCpp:
            return false
        }
    }

    /// Cost-rank for image generation/edit. Lower = cheaper. Used
    /// by the auto-select logic to prefer cheap providers when the
    /// user hasn't pinned one explicitly. Numbers are anchored to
    /// May-2026 list prices for the canonical image model on each
    /// provider:
    ///   • Gemini 2.5 Flash Image Preview — ~$0.039 / image
    ///   • OpenRouter — proxies cheap providers (Flux, Imagen)
    ///     and is usually below OpenAI for equivalent quality
    ///   • OpenAI gpt-image-1 — $0.011 (low) … $0.167 (high),
    ///     defaults to medium ≈ $0.042 in our wiring
    ///   • Custom — unknown, could be a free local server OR a
    ///     pricier hosted endpoint; ranked last because we can't
    ///     reason about its cost from the registry alone
    ///
    /// Returns `Int.max` for kinds that can't run image edits at
    /// all, so a `.sorted(by: { $0.imageEditCostRank < $1.imageEditCostRank })`
    /// pass naturally pushes them to the end.
    var imageEditCostRank: Int {
        switch self {
        case .gemini:     return 1
        case .openrouter: return 2
        case .openai:     return 3
        case .custom:     return 4
        case .anthropic, .grok, .mistral, .deepseek,
             .together, .cloudflareWorkers, .groq, .cerebras,
             .ollama, .lmstudio, .llamaCpp:
            return Int.max
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .ollama:            return "http://localhost:11434"
        case .lmstudio:          return "http://localhost:1234"
        case .llamaCpp:          return "http://localhost:8080"
        // Cloudflare Workers AI bakes the account ID into the URL; we
        // can only seed a placeholder. The user replaces YOUR_ACCOUNT_ID
        // with their actual account ID from the Cloudflare dashboard.
        case .cloudflareWorkers:
            return "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"
        default: return nil
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic:         return "claude-sonnet-4-6"
        case .openai:            return "gpt-4o-mini"
        case .gemini:            return "gemini-2.5-flash"
        case .grok:              return "grok-4"
        case .mistral:           return "mistral-large-latest"
        case .deepseek:          return "deepseek-chat"
        case .openrouter:        return "anthropic/claude-sonnet-4.5"
        // Together AI slugs follow `vendor/Model-Name-Turbo`
        // convention. Flagship default is their fastest 70B Llama.
        case .together:          return "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        // Cloudflare Workers AI slugs are `@cf/<vendor>/<model>`;
        // 8B Llama is the cheapest balanced default.
        case .cloudflareWorkers: return "@cf/meta/llama-3.1-8b-instruct"
        // Groq's flagship — Llama 3.3 70B on their LPU hardware.
        case .groq:              return "llama-3.3-70b-versatile"
        // Cerebras's flagship — Llama 3.3 70B on wafer-scale.
        case .cerebras:          return "llama3.3-70b"
        case .ollama:            return "llama3.2:latest"
        case .lmstudio:          return "local-model"
        case .llamaCpp:          return "local-model"
        case .custom:            return "model"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .anthropic:  return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"]
        case .openai:     return ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-5", "gpt-5-mini"]
        case .gemini:     return ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
        case .grok:       return ["grok-4", "grok-3"]
        case .mistral:    return ["mistral-large-latest", "codestral-latest", "mistral-small-latest"]
        case .deepseek:   return ["deepseek-chat", "deepseek-reasoner"]
        // Curated cross-vendor sampling to showcase the gateway's
        // value — Claude / GPT / Gemini / Llama / Mistral / DeepSeek
        // / Qwen / Grok all reachable from one API key. Users can
        // type any slug from openrouter.ai/models — this list is
        // just a starting point.
        case .openrouter: return [
            "anthropic/claude-sonnet-4.5",
            "anthropic/claude-3.5-haiku",
            "openai/gpt-5",
            "openai/gpt-4o-mini",
            "google/gemini-2.5-pro",
            "meta-llama/llama-3.1-70b-instruct",
            "mistralai/mistral-large",
            "deepseek/deepseek-chat",
            "qwen/qwen-2.5-72b-instruct",
            "x-ai/grok-4"
        ]
        case .together: return [
            "meta-llama/Llama-3.3-70B-Instruct-Turbo",
            "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo",
            "Qwen/Qwen2.5-72B-Instruct-Turbo",
            "mistralai/Mixtral-8x7B-Instruct-v0.1",
            "deepseek-ai/DeepSeek-V3"
        ]
        case .cloudflareWorkers: return [
            "@cf/meta/llama-3.1-8b-instruct",
            "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
            "@cf/mistral/mistral-7b-instruct-v0.1",
            "@cf/google/gemma-7b-it",
            "@cf/qwen/qwen1.5-14b-chat-awq"
        ]
        case .groq: return [
            "llama-3.3-70b-versatile",
            "llama-3.1-8b-instant",
            "mixtral-8x7b-32768",
            "gemma2-9b-it",
            "deepseek-r1-distill-llama-70b"
        ]
        case .cerebras: return [
            "llama3.3-70b",
            "llama3.1-8b",
            "llama3.1-70b"
        ]
        case .ollama:     return ["llama3.2:latest", "llama3.1:latest", "qwen2.5:latest", "deepseek-r1:latest"]
        default: return []
        }
    }

    /// Direct deep-link to the provider's API key console / dashboard.
    /// Surfaced as a "Get an API key" link in `ProviderEditor` so the user
    /// doesn't have to dig through marketing pages to find the actual key
    /// creation flow. Returns `nil` for local providers (Ollama, LM Studio,
    /// llama.cpp) where no key is needed, and for `custom` which is
    /// endpoint-agnostic.
    var apiKeyDocsURL: URL? {
        switch self {
        case .anthropic:         return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai:            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:            return URL(string: "https://aistudio.google.com/app/apikey")
        case .grok:              return URL(string: "https://console.x.ai/team/default/api-keys")
        case .mistral:           return URL(string: "https://console.mistral.ai/api-keys")
        case .deepseek:          return URL(string: "https://platform.deepseek.com/api_keys")
        case .openrouter:        return URL(string: "https://openrouter.ai/settings/keys")
        case .together:          return URL(string: "https://api.together.xyz/settings/api-keys")
        case .cloudflareWorkers: return URL(string: "https://dash.cloudflare.com/profile/api-tokens")
        case .groq:              return URL(string: "https://console.groq.com/keys")
        case .cerebras:          return URL(string: "https://cloud.cerebras.ai/")
        case .ollama, .lmstudio, .llamaCpp, .custom: return nil
        }
    }
}

// MARK: - ConfiguredProvider

/// User-facing description of a configured provider. Serialized to
/// providers.json. The API key is stored separately in Keychain under
/// providerID; only non-secret fields live here.
struct ConfiguredProvider: Codable, Identifiable, Equatable {
    var id: String
    var kind: ProviderKind
    var displayName: String
    var model: String
    var baseURL: String?
    var enabled: Bool = true
}

// MARK: - Registry config

struct ProvidersConfig: Codable {
    var version: Int = 2
    var defaultProviderID: String?
    var providers: [ConfiguredProvider]

    static let configURL: URL = AppStorage.dataDir.appendingPathComponent("providers.json")

    static func load() -> ProvidersConfig {
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return defaultConfig()
        }
        // Try v2 first
        if let cfg = try? JSONDecoder().decode(ProvidersConfig.self, from: data) {
            return cfg
        }
        // Fallback to v1 migration
        if let v1 = try? JSONDecoder().decode(LegacyV1.self, from: data) {
            return migrate(from: v1)
        }
        return defaultConfig()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    /// Default — Anthropic + Ollama as presets (not configured yet, no API keys).
    /// `defaultProviderID` is nil — the default is auto-assigned to the first
    /// provider that passes its connection test.
    static func defaultConfig() -> ProvidersConfig {
        return ProvidersConfig(
            version: 2,
            defaultProviderID: nil,
            providers: [
                ConfiguredProvider(id: "anthropic", kind: .anthropic,
                                   displayName: ProviderKind.anthropic.displayName,
                                   model: ProviderKind.anthropic.defaultModel,
                                   baseURL: nil),
                ConfiguredProvider(id: "ollama", kind: .ollama,
                                   displayName: ProviderKind.ollama.displayName,
                                   model: ProviderKind.ollama.defaultModel,
                                   baseURL: ProviderKind.ollama.defaultBaseURL)
                // `enabled` defaults to true — Settings no longer exposes a
                // disable toggle, so all seeded entries start active.
            ]
        )
    }

    // MARK: - Migration

    private struct LegacyV1: Codable {
        var anthropicAPIKey: String?
        var anthropicModel: String?
    }

    private static func migrate(from v1: LegacyV1) -> ProvidersConfig {
        // If a v1 key was present, move it into Keychain and do not store it in config.
        if let key = v1.anthropicAPIKey, !key.isEmpty {
            APIKeyStorage.save(key, for: "anthropic")
        }
        var cfg = defaultConfig()
        if let idx = cfg.providers.firstIndex(where: { $0.id == "anthropic" }) {
            cfg.providers[idx].model = v1.anthropicModel ?? cfg.providers[idx].model
        }
        cfg.save()
        return cfg
    }
}

// MARK: - Registry (singleton)

@MainActor
final class AIProviderRegistry: ObservableObject {
    static let shared = AIProviderRegistry()

    @Published var config: ProvidersConfig {
        didSet { config.save() }
    }

    private var providerCache: [String: AIProvider] = [:]

    private init() {
        self.config = ProvidersConfig.load()
        enableAllProviders()
        reconcileDefaultProvider()
    }

    /// Migration helper. The per-provider enable / disable Toggle was removed
    /// from Settings → AI in 0.16.0 (it was an unlabeled tiny control next to
    /// Edit / Trash that users were flipping off by accident, then seeing
    /// "API key required" errors). Without UI to switch it back on, any
    /// `enabled: false` value persisted in `providers.json` would lock the
    /// provider out forever. Fix at load time: force every provider to
    /// `enabled = true` so the field becomes invariant. Removing a provider
    /// is now done exclusively through the trash button.
    private func enableAllProviders() {
        var newCfg = config
        var didChange = false
        for idx in newCfg.providers.indices where !newCfg.providers[idx].enabled {
            newCfg.providers[idx].enabled = true
            didChange = true
        }
        if didChange {
            config = newCfg
        }
    }

    /// If the currently-saved default isn't actually configured (no API key, no base URL),
    /// promote any configured-and-enabled provider to be the default. This fixes stale
    /// state from previous versions that pre-set "anthropic" as default before configuration.
    private func reconcileDefaultProvider() {
        let currentID = config.defaultProviderID
        if let id = currentID, !id.isEmpty,
           let cp = config.providers.first(where: { $0.id == id }) {
            let hasKey = APIKeyStorage.load(for: cp.id) != nil
            let isReady = cp.kind.isLocal || hasKey
            if isReady { return }
        }
        // Find first ready provider (has key for cloud, has URL for local).
        let firstReady = config.providers.first { cp in
            guard cp.enabled else { return false }
            if cp.kind.isLocal { return (cp.baseURL ?? "").isEmpty == false }
            return APIKeyStorage.load(for: cp.id) != nil
        }
        if let candidate = firstReady {
            var newCfg = config
            newCfg.defaultProviderID = candidate.id
            config = newCfg
        } else {
            // No ready provider — clear stale default so radio shows none selected.
            if config.defaultProviderID != nil {
                var newCfg = config
                newCfg.defaultProviderID = nil
                config = newCfg
            }
        }
    }

    /// Returns a ready provider by ID. Creates the concrete instance on first
    /// call, caches it, and invalidates the cache on reload().
    func provider(id: String) -> AIProvider? {
        if let cached = providerCache[id] { return cached }
        guard let cp = config.providers.first(where: { $0.id == id }), cp.enabled else { return nil }
        guard let p = makeConcrete(from: cp) else { return nil }
        providerCache[id] = p
        return p
    }

    /// Default provider (used by AI actions without an explicit providerID).
    var defaultProvider: AIProvider? {
        if let id = config.defaultProviderID, let p = provider(id: id) {
            return p
        }
        // Fall back to the first enabled provider.
        for cp in config.providers where cp.enabled {
            if let p = provider(id: cp.id) { return p }
        }
        return nil
    }

    /// Returns the provider kind for UI badges.
    func kind(forProviderID id: String) -> ProviderKind? {
        config.providers.first(where: { $0.id == id })?.kind
    }

    /// Cheapest enabled image-capable provider, by
    /// `ProviderKind.imageEditCostRank`. Returns nil when nothing
    /// in the registry can run image edits.
    ///
    /// This is the single source of truth for "pick a provider to
    /// run an image action when the user hasn't pinned one" — used
    /// by both the runtime soft fallback (`AIImageAction.resolveProvider`)
    /// and by the four UI surfaces that mirror that chain (Edit
    /// Action provider picker auto-select + effective-provider
    /// hint, Settings → Playground inflight label, live HUD
    /// inflight label). Keeping it in one place stops them from
    /// drifting apart and surfacing different provider names for
    /// the same action.
    ///
    /// Tie-break order when two enabled providers share the same
    /// rank (rare today since each kind has a unique rank, but
    /// possible if the user adds two Custom providers): preserve
    /// registry order so the user's manually-arranged list wins.
    ///
    /// Cached — SwiftUI re-renders that drive picker chips and HUD
    /// badges call this on every view-body evaluation, and the
    /// filter+sort otherwise runs dozens of times per second during
    /// a streaming AI loading panel. Cache is invalidated on every
    /// mutating registry call (`upsert`, `remove`, `setDefault`,
    /// `invalidateCache`) so it's always at most one config-version
    /// stale.
    func cheapestEnabledImageProvider() -> ConfiguredProvider? {
        if cheapestImageProviderCacheValid {
            return cheapestImageProviderCache
        }
        let result = config.providers
            .filter { $0.enabled && $0.kind.supportsImageEdit }
            .sorted { $0.kind.imageEditCostRank < $1.kind.imageEditCostRank }
            .first
        cheapestImageProviderCache = result
        cheapestImageProviderCacheValid = true
        return result
    }

    /// Drop the cached `cheapestEnabledImageProvider` reading. Called
    /// internally on every mutation; also exposed for the existing
    /// `invalidateCache()` entry point so external invalidations
    /// (e.g. after a Keychain key write that doesn't go through
    /// upsert) clear this cache too.
    func invalidateImageProviderCache() {
        cheapestImageProviderCache = nil
        cheapestImageProviderCacheValid = false
    }

    private var cheapestImageProviderCache: ConfiguredProvider? = nil
    private var cheapestImageProviderCacheValid: Bool = false

    /// Upsert a provider. When apiKey is non-nil, the key is saved to Keychain.
    func upsert(_ cp: ConfiguredProvider, apiKey: String? = nil) {
        if let key = apiKey, !key.isEmpty {
            APIKeyStorage.save(key, for: cp.id)
        }
        var newCfg = config
        if let idx = newCfg.providers.firstIndex(where: { $0.id == cp.id }) {
            newCfg.providers[idx] = cp
        } else {
            newCfg.providers.append(cp)
        }
        config = newCfg
        providerCache.removeValue(forKey: cp.id)
        invalidateImageProviderCache()
    }

    func remove(providerID: String) {
        APIKeyStorage.remove(for: providerID)
        var newCfg = config
        newCfg.providers.removeAll { $0.id == providerID }
        let removedDefault = (newCfg.defaultProviderID == providerID)
        if removedDefault { newCfg.defaultProviderID = nil }
        config = newCfg
        // Codex #7 — when the deleted provider was the default, promote the
        // first READY provider (key present / local URL set), not just the first
        // one in the list. reconcile clears the default to nil if none are ready.
        if removedDefault { reconcileDefaultProvider() }
        providerCache.removeValue(forKey: providerID)
        invalidateImageProviderCache()
    }

    func setDefault(providerID: String) {
        var newCfg = config
        newCfg.defaultProviderID = providerID
        config = newCfg
        // Default change doesn't move which providers are
        // image-capable, but `effectiveProvider`-style lookups
        // upstream may have cached "Default resolves to X" — drop
        // the image-cheapest cache too for consistency.
        invalidateImageProviderCache()
    }

    /// Force-clears the provider cache. Call after external config mutations.
    func invalidateCache() {
        providerCache.removeAll()
        invalidateImageProviderCache()
    }

    /// Wipes all configured providers and their Keychain API keys, then restores
    /// the bundled default config (Anthropic + Ollama placeholders, no default
    /// selected). Used by Factory Reset.
    func factoryReset() {
        for cp in config.providers {
            APIKeyStorage.remove(for: cp.id)
        }
        providerCache.removeAll()
        invalidateImageProviderCache()
        config = ProvidersConfig.defaultConfig()
    }

    /// Test connection — sends a short prompt and measures the round-trip latency.
    func testConnection(providerID: String) async -> Result<String, AIProviderError> {
        guard let p = provider(id: providerID) else {
            return .failure(.missingAPIKey)
        }
        let start = Date()
        do {
            _ = try await p.run(prompt: "Reply with the single word OK.", input: "ping")
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return .success("Connected (\(ms) ms)")
        } catch let e as AIProviderError {
            return .failure(e)
        } catch {
            return .failure(.decode(error.localizedDescription))
        }
    }

    // MARK: - Concrete factory

    private func makeConcrete(from cp: ConfiguredProvider) -> AIProvider? {
        let apiKey = APIKeyStorage.load(for: cp.id)
            ?? ProcessInfo.processInfo.environment["\(cp.kind.rawValue.uppercased())_API_KEY"]
        switch cp.kind {
        case .anthropic:
            return AnthropicProvider(id: cp.id, apiKey: apiKey, model: cp.model)
        case .gemini:
            return GeminiProvider(id: cp.id, apiKey: apiKey, model: cp.model)
        case .openai:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://api.openai.com/v1",
                                            apiKey: apiKey)
        case .grok:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://api.x.ai/v1",
                                            apiKey: apiKey)
        case .mistral:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://api.mistral.ai/v1",
                                            apiKey: apiKey)
        case .deepseek:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://api.deepseek.com",
                                            apiKey: apiKey)
        case .openrouter:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://openrouter.ai/api/v1",
                                            apiKey: apiKey)
        case .together:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://api.together.xyz/v1",
                                            apiKey: apiKey)
        case .cloudflareWorkers:
            // No default — user MUST supply the URL with their
            // account ID. The placeholder string from
            // `defaultBaseURL` will fail with a clear 404 if left
            // unchanged, which is the diagnostic we want.
            guard let baseURL = cp.baseURL, !baseURL.isEmpty,
                  !baseURL.contains("YOUR_ACCOUNT_ID") else { return nil }
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: baseURL, apiKey: apiKey)
        case .groq:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://api.groq.com/openai/v1",
                                            apiKey: apiKey)
        case .cerebras:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "https://api.cerebras.ai/v1",
                                            apiKey: apiKey)
        case .ollama:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "http://localhost:11434/v1",
                                            apiKey: nil, requiresAuth: false)
        case .lmstudio:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "http://localhost:1234/v1",
                                            apiKey: nil, requiresAuth: false)
        case .llamaCpp:
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: cp.baseURL ?? "http://localhost:8080/v1",
                                            apiKey: nil, requiresAuth: false)
        case .custom:
            guard let baseURL = cp.baseURL, !baseURL.isEmpty else { return nil }
            return OpenAICompatibleProvider(id: cp.id, kind: cp.kind, model: cp.model,
                                            baseURL: baseURL, apiKey: apiKey,
                                            requiresAuth: apiKey != nil)
        }
    }
}

// MARK: - AnthropicProvider

final class AnthropicProvider: AIProvider {
    let id: String
    let displayName = ProviderKind.anthropic.displayName
    let model: String
    let isLocal = false

    private let apiKey: String?

    init(id: String = "anthropic", apiKey: String?, model: String) {
        self.id = id
        self.apiKey = apiKey
        self.model = model
    }

    var isReady: Bool { !(apiKey ?? "").isEmpty }

    func run(prompt: String, input: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": prompt,
            "messages": [["role": "user", "content": input]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await AIHTTP.session.data(for: req)
        try checkHTTP(resp: resp, data: data)

        struct Block: Decodable { let type: String; let text: String? }
        struct Resp: Decodable { let content: [Block] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
    }

    /// Anthropic Messages SSE streaming. Endpoint is the same `/v1/messages`
    /// with `stream: true` added to the request body. The server emits
    /// `event: <type>` + `data: <json>` line pairs; we only care about
    /// `content_block_delta` whose JSON contains `delta.text` with a
    /// partial token. Other event types (`message_start`, `ping`,
    /// `message_stop`, etc.) are ignored. The HTTP connection closes when
    /// the stream finishes — that's our signal to call `continuation.finish()`.
    func stream(prompt: String, input: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = apiKey, !apiKey.isEmpty else {
                        throw AIProviderError.missingAPIKey
                    }
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 4096,
                        "stream": true,
                        "system": prompt,
                        "messages": [["role": "user", "content": input]]
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, resp): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, resp) = try await StreamingHTTP.session.bytes(for: req)
                    } catch {
                        throw AIProviderError.networkUnreachable
                    }
                    guard let http = resp as? HTTPURLResponse else {
                        throw AIProviderError.decode("no http response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        // Drain a bounded amount of the error body for a
                        // human-readable message; the API's error JSON is
                        // usually under 1 KB.
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line + "\n"
                            if errBody.count > 4096 { break }
                        }
                        throw AIProviderError.http(status: http.statusCode, body: errBody)
                    }

                    var sawStop = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        // Skip blank lines and `event: ...` framing — only
                        // `data: <json>` lines carry payload.
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        // Expected: {"type":"content_block_delta","index":0,
                        //            "delta":{"type":"text_delta","text":"..."}}
                        if let type = json["type"] as? String {
                            switch type {
                            case "content_block_delta":
                                if let delta = json["delta"] as? [String: Any],
                                   let text = delta["text"] as? String,
                                   !text.isEmpty {
                                    continuation.yield(text)
                                }
                            case "message_stop":
                                // Anthropic's explicit "I'm done" marker.
                                // Some server paths leave the TCP socket
                                // half-open past this point — `bytes.lines`
                                // would then sit forever waiting for the
                                // next ping. Break out as soon as we see
                                // it so the AsyncThrowingStream closes
                                // promptly. Without this guard the
                                // MiniHUD elapsed counter ticks
                                // indefinitely even though the response
                                // is already complete.
                                sawStop = true
                            default:
                                break
                            }
                            if sawStop { break }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAICompatibleProvider

/// Unified provider for any OpenAI-compatible chat/completions API.
/// OpenAI, xAI Grok, Mistral, DeepSeek, Ollama, LM Studio, llama.cpp, Custom.
/// Implementations differ only in baseURL and whether they require an Authorization header.
final class OpenAICompatibleProvider: AIProvider {
    let id: String
    let kind: ProviderKind
    let model: String
    let baseURL: String
    private let apiKey: String?
    private let requiresAuth: Bool

    var displayName: String { kind.displayName }
    var isLocal: Bool { kind.isLocal }
    var isReady: Bool {
        if requiresAuth { return !(apiKey ?? "").isEmpty }
        return !baseURL.isEmpty
    }

    init(id: String, kind: ProviderKind, model: String, baseURL: String,
         apiKey: String?, requiresAuth: Bool = true) {
        self.id = id
        self.kind = kind
        self.model = model
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
        self.requiresAuth = requiresAuth
    }

    func run(prompt: String, input: String) async throws -> String {
        if requiresAuth, (apiKey ?? "").isEmpty {
            throw AIProviderError.missingAPIKey
        }
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw AIProviderError.missingBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresAuth, let key = apiKey {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        // Do not send max_tokens — the gpt-5 family requires max_completion_tokens
        // while gpt-4 expects max_tokens. Omitting the field is safer; the API
        // default is reasonable.
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": input]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await AIHTTP.session.data(for: req)
        } catch {
            throw AIProviderError.networkUnreachable
        }
        try checkHTTP(resp: resp, data: data)

        struct Choice: Decodable {
            struct Msg: Decodable { let content: String? }
            let message: Msg
        }
        struct Resp: Decodable { let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    /// OpenAI-compatible SSE streaming. One implementation handles every
    /// provider on this protocol: OpenAI proper, xAI Grok, Mistral,
    /// DeepSeek, Ollama (OpenAI mode), LM Studio, llama.cpp,
    /// custom endpoints — they all share the chat/completions SSE format.
    /// Server emits `data: { ... }` lines with a `[DONE]` terminator;
    /// per-chunk JSON exposes `choices[0].delta.content` for the delta text.
    func stream(prompt: String, input: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if requiresAuth, (apiKey ?? "").isEmpty {
                        throw AIProviderError.missingAPIKey
                    }
                    guard let url = URL(string: "\(baseURL)/chat/completions") else {
                        throw AIProviderError.missingBaseURL
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if requiresAuth, let key = apiKey {
                        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": prompt],
                            ["role": "user", "content": input]
                        ]
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, resp): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, resp) = try await StreamingHTTP.session.bytes(for: req)
                    } catch {
                        throw AIProviderError.networkUnreachable
                    }
                    guard let http = resp as? HTTPURLResponse else {
                        throw AIProviderError.decode("no http response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line + "\n"
                            if errBody.count > 4096 { break }
                        }
                        throw AIProviderError.http(status: http.statusCode, body: errBody)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        // `[DONE]` is the OpenAI-style terminator.
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        // Expected: {"choices":[{"delta":{"content":"..."},...}]}
                        if let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - GeminiProvider

final class GeminiProvider: AIProvider {
    let id: String
    let displayName = ProviderKind.gemini.displayName
    let model: String
    let isLocal = false

    private let apiKey: String?

    init(id: String = "gemini", apiKey: String?, model: String) {
        self.id = id
        self.apiKey = apiKey
        self.model = model
    }

    var isReady: Bool { !(apiKey ?? "").isEmpty }

    func run(prompt: String, input: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw AIProviderError.missingBaseURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": prompt]]],
            "contents": [["role": "user", "parts": [["text": input]]]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await AIHTTP.session.data(for: req)
        try checkHTTP(resp: resp, data: data)

        struct Part: Decodable { let text: String? }
        struct Content: Decodable { let parts: [Part] }
        struct Candidate: Decodable { let content: Content }
        struct Resp: Decodable { let candidates: [Candidate] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.candidates.first?.content.parts.compactMap { $0.text }.joined() ?? ""
    }

    /// Gemini SSE streaming via the `:streamGenerateContent?alt=sse`
    /// variant. Server emits `data: <json>` lines where each JSON
    /// contains zero or more candidates, each with a content block of
    /// text parts. The stream closes when the response is complete —
    /// no explicit terminator like OpenAI's `[DONE]`. Multiple text
    /// parts within a single chunk are yielded sequentially so the
    /// downstream accumulator stays simple.
    func stream(prompt: String, input: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = apiKey, !apiKey.isEmpty else {
                        throw AIProviderError.missingAPIKey
                    }
                    let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
                    guard let url = URL(string: urlString) else {
                        throw AIProviderError.missingBaseURL
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let body: [String: Any] = [
                        "systemInstruction": ["parts": [["text": prompt]]],
                        "contents": [["role": "user", "parts": [["text": input]]]]
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, resp): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, resp) = try await StreamingHTTP.session.bytes(for: req)
                    } catch {
                        throw AIProviderError.networkUnreachable
                    }
                    guard let http = resp as? HTTPURLResponse else {
                        throw AIProviderError.decode("no http response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line + "\n"
                            if errBody.count > 4096 { break }
                        }
                        throw AIProviderError.http(status: http.statusCode, body: errBody)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        // Expected: {"candidates":[{"content":{"parts":[{"text":"..."}],"role":"model"},...}]}
                        var finished = false
                        if let candidates = json["candidates"] as? [[String: Any]],
                           let first = candidates.first {
                            if let content = first["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]] {
                                for part in parts {
                                    if let text = part["text"] as? String, !text.isEmpty {
                                        continuation.yield(text)
                                    }
                                }
                            }
                            // Gemini signals completion via finishReason
                            // (STOP, MAX_TOKENS, SAFETY, RECITATION,
                            // OTHER). Any non-empty finishReason means
                            // this is the last chunk we should expect.
                            // Without breaking, the for-await stays
                            // open while the server keeps the TCP
                            // half-open, ticking the elapsed counter
                            // long after the response is complete.
                            if let reason = first["finishReason"] as? String,
                               !reason.isEmpty {
                                finished = true
                            }
                        }
                        if finished { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Streaming session

/// Shared URLSession used by every provider's streaming entry point.
/// `timeoutIntervalForRequest = 15` gives a native heartbeat: the timer
/// resets on every byte received, so if a provider stalls mid-stream
/// (network drop, hung connection, model genuinely paused) URLSession
/// throws `URLError.timedOut` after 15 idle seconds. The applyStreaming
/// catch path surfaces any partial content as a `.failed` outcome with
/// the partial text accessible, so the user can still copy / commit what
/// arrived. 600s `timeoutIntervalForResource` is the hard ceiling for
/// any single response (10 minutes — generous, but bounded).
private enum StreamingHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 600
        // SSE responses are framed by newlines; no need to wait for the
        // entire response before yielding bytes.
        config.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
        return URLSession(configuration: config)
    }()
}

// MARK: - HTTP helper

private func checkHTTP(resp: URLResponse, data: Data) throws {
    guard let http = resp as? HTTPURLResponse else {
        throw AIProviderError.decode("no http response")
    }
    guard (200..<300).contains(http.statusCode) else {
        let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
        throw AIProviderError.http(status: http.statusCode, body: bodyStr)
    }
}

// MARK: - AI Action

struct AIAction: ClipboardAction {
    let id: String
    let title: String
    let isLocal: Bool = false
    let promptTemplate: String
    let providerID: String?         // nil = use default
    let applicableTypes: Set<SemanticKind>
    let preserveRichFormatting: Bool
    let requiredTraits: [String]      // #A75 "Show when…" conditions
    let forbiddenTraits: [String]

    init(id: String, title: String, promptTemplate: String,
         providerID: String? = nil,
         applicableTypes: Set<SemanticKind> = [.text, .richText, .url, .json, .markdown, .code],
         preserveRichFormatting: Bool = false,
         requiredTraits: [String] = [],
         forbiddenTraits: [String] = []) {
        self.id = id
        self.title = title
        self.promptTemplate = promptTemplate
        self.providerID = providerID
        self.applicableTypes = applicableTypes
        self.preserveRichFormatting = preserveRichFormatting
        self.requiredTraits = requiredTraits
        self.forbiddenTraits = forbiddenTraits
    }

    /// Appended to the prompt when round-tripping rich / Markdown input so the
    /// model edits only the text and never the markup.
    static let preserveMarkdownInstruction =
        "\n\nThe input is in Markdown format. Preserve all Markdown markup exactly (bold **, italic *, links [text](url), code `inline`, code blocks ```, headings #, lists -/1.). Only modify the text content, never the markup."

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Strict "Applies to" correspondence (rich text still surfaces text
        // actions). See CustomTransformationAction.isApplicable.
        guard applicableTypes.contains(item.semantic)
            || (item.semantic == .richText && applicableTypes.contains(.text)) else { return false }
        return ActionTrait.passes(required: requiredTraits, forbidden: forbiddenTraits, in: context)
    }

    /// Type-only membership (no trait gate) — see ClipboardAction default.
    func appliesToContentType(item: ClipboardItem, context: ContentContext) -> Bool {
        applicableTypes.contains(item.semantic)
            || (item.semantic == .richText && applicableTypes.contains(.text))
    }

    @MainActor
    private func resolveProvider() -> AIProvider? {
        if let id = providerID, let p = AIProviderRegistry.shared.provider(id: id) {
            return p
        }
        return AIProviderRegistry.shared.defaultProvider
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let provider: AIProvider? = await MainActor.run { resolveProvider() }
        guard let provider = provider else {
            return .failed(original: item,
                          reason: "Connect an AI provider to get a result — open Settings → AI.",
                          recovery: .openProvidersConfig)
        }
        do {
            // Formatting-preserving round-trip: rich text → Markdown (or
            // Markdown source straight through) with an instruction to keep
            // markup, then back to rich text for rich input.
            let isRich = item.semantic == .richText
            let isMarkdown = item.semantic == .markdown
            let inputText: String
            let systemAddition: String
            if preserveRichFormatting, isRich,
               let md = RichTextHelpers.attributedStringToMarkdown(loadAttr(item: item)) {
                inputText = md
                systemAddition = Self.preserveMarkdownInstruction
            } else if preserveRichFormatting, isMarkdown {
                inputText = item.previewText ?? ""
                systemAddition = Self.preserveMarkdownInstruction
            } else {
                inputText = item.previewText ?? ""
                systemAddition = ""
            }
            let result = try await provider.run(prompt: promptTemplate + systemAddition, input: inputText)
            if preserveRichFormatting, isRich,
               let ns = RichTextHelpers.markdownToAttributedString(result) {
                return .preview(makeRichTextItem(ns, from: item))
            }
            return .preview(makeTextItem(result, from: item))
        } catch AIProviderError.missingAPIKey {
            return .failed(original: item,
                          reason: "Connect an AI provider to get a result — open Settings → AI.",
                          recovery: .openProvidersConfig)
        } catch AIProviderError.http(let status, _) {
            return .failed(original: item,
                          reason: "AI provider HTTP \(status). Check API key and model.",
                          recovery: .openProvidersConfig)
        } catch AIProviderError.networkUnreachable {
            return .failed(original: item,
                          reason: "Network unreachable. Check that the provider endpoint is online.",
                          recovery: nil)
        } catch {
            return .failed(original: item,
                          reason: "AI provider error: \(error.localizedDescription)",
                          recovery: nil)
        }
    }

    private func loadAttr(item: ClipboardItem) -> NSAttributedString {
        // Codex #4 — flat-RTFD aware: rich clips with attachments are stored as
        // com.apple.flat-rtfd, not public.rtf. Reading only RTF lost them, so
        // Translate / Fix grammar fell back to the plain previewText.
        RichTextHelpers.loadAttributed(from: item)
            ?? NSAttributedString(string: item.previewText ?? "")
    }

    /// Streaming entry point — same logic flow as `apply()` but consumes
    /// the provider's incremental stream and surfaces every accumulated
    /// chunk through `onPartial`. The final ApplyOutcome is returned at
    /// the end exactly like `apply()` would. Mid-stream failures with
    /// non-empty content are surfaced as `.failed(original: partialItem,
    /// reason: ..., recovery: nil)` so the user can still copy / commit
    /// what arrived before the connection cut — critical for offline-
    /// tolerant workflows where a 60% translation is still 60% useful.
    func applyStreaming(item: ClipboardItem,
                        context: ContentContext,
                        onPartial: @escaping @MainActor (ClipboardItem) -> Void)
        async -> ApplyOutcome
    {
        let provider: AIProvider? = await MainActor.run { resolveProvider() }
        guard let provider = provider else {
            return .failed(original: item,
                          reason: "Connect an AI provider to get a result — open Settings → AI.",
                          recovery: .openProvidersConfig)
        }

        // Same rich-text / markdown round-trip prep as the non-streaming
        // path. During streaming we keep the partial preview as plain
        // text (semantic = .text) so SwiftUI's text view updates cheaply
        // at token rate; the final outcome rehydrates rich text via
        // markdownToAttributedString once at the end, so NSTextView
        // reflow only happens once.
        let isRich = item.semantic == .richText
        let isMarkdown = item.semantic == .markdown
        let inputText: String
        let systemAddition: String
        if preserveRichFormatting, isRich,
           let md = RichTextHelpers.attributedStringToMarkdown(loadAttr(item: item)) {
            inputText = md
            systemAddition = Self.preserveMarkdownInstruction
        } else if preserveRichFormatting, isMarkdown {
            inputText = item.previewText ?? ""
            systemAddition = Self.preserveMarkdownInstruction
        } else {
            inputText = item.previewText ?? ""
            systemAddition = ""
        }

        var accumulated = ""
        do {
            for try await chunk in provider.stream(prompt: promptTemplate + systemAddition,
                                                    input: inputText) {
                accumulated += chunk
                let partialItem = makeTextItem(accumulated, from: item)
                await onPartial(partialItem)
            }
            // Final outcome — rich-text rehydration if the action asked for it.
            if preserveRichFormatting, isRich,
               let ns = RichTextHelpers.markdownToAttributedString(accumulated) {
                return .preview(makeRichTextItem(ns, from: item))
            }
            return .preview(makeTextItem(accumulated, from: item))
        } catch AIProviderError.missingAPIKey {
            return .failed(original: item,
                          reason: "Connect an AI provider to get a result — open Settings → AI.",
                          recovery: .openProvidersConfig)
        } catch AIProviderError.http(let status, _) {
            return .failed(original: item,
                          reason: "AI provider HTTP \(status). Check API key and model.",
                          recovery: .openProvidersConfig)
        } catch AIProviderError.networkUnreachable {
            return .failed(original: item,
                          reason: "Network unreachable. Check that the provider endpoint is online.",
                          recovery: nil)
        } catch is CancellationError {
            // Cancellation is normal (user navigated away). Caller's
            // previewToken check drops these updates anyway. Return the
            // accumulated text so the path stays type-stable; the caller
            // will discard it.
            return .preview(makeTextItem(accumulated, from: item))
        } catch {
            // Mid-stream failure with partial content — surface it so the
            // user can copy what arrived. This is the offline-on-a-plane
            // use case: a flaky Wi-Fi gives us 60% of a translation, the
            // connection cuts; user still has 60% in the preview pane to
            // read, copy, or chain into ⌥⌘Space.
            //
            // URLError.timedOut is the heartbeat hit: StreamingHTTP.session
            // has `timeoutIntervalForRequest = 15` so the connection
            // throws timedOut if 15 idle seconds pass with no chunks.
            // Distinguish it from a hard network drop so the user sees a
            // helpful "stalled" message instead of just "timed out".
            let isStall: Bool = {
                if let urlErr = error as? URLError, urlErr.code == .timedOut { return true }
                return false
            }()
            if !accumulated.isEmpty {
                let reason: String
                if isStall {
                    reason = "Stream stalled (\(accumulated.count) chars received, no further data for 15 s)"
                } else {
                    reason = "Stream interrupted (\(accumulated.count) chars received): \(error.localizedDescription)"
                }
                return .failed(
                    original: makeTextItem(accumulated, from: item),
                    reason: reason,
                    recovery: nil
                )
            }
            if isStall {
                return .failed(original: item,
                              reason: "Stream stalled before any data arrived (no chunks for 15 s). Check connection.",
                              recovery: nil)
            }
            return .failed(original: item,
                          reason: "AI provider error: \(error.localizedDescription)",
                          recovery: nil)
        }
    }
}

// MARK: - Default AI action seed

/// Default AI actions are seeded into config.customAI on first launch as regular
/// CustomAIDescriptor entries. Users can edit prompt, provider, applicable types,
/// or delete them. The `seedAIVersion` counter controls upgrades.
enum DefaultAISeed {
    /// Increment when adding new default AI actions to ship to existing users on upgrade.
    /// v2: switch seeded entries from hardcoded "anthropic" providerID to "" (follow default).
    /// v3: add three image-AI styles (Pencil sketch / Watercolor / Cartoon) with
    ///     kind == .image. They route through gpt-image-1 when the resolved
    ///     provider is OpenAI, and surface as regular AI actions in Settings →
    ///     Actions so users can edit the prompt, switch provider, or clone
    ///     them into their own styles ("Oil paint", "Stained glass", …).
    /// v4 — added one text→image seed: "AI: Whiteboard sketch" with
    ///     kind == .textToImage. Copy any concept text and the action
    ///     generates a clean black-and-white marker-on-whiteboard
    ///     illustration. Universal — works for meeting notes,
    ///     document figures, brainstorm visualisation.
    /// v5 — append `Quality: low` directive to every image / text→image
    ///     seed prompt. Parsed out by `AIImageHTTP.extractQualityDirective`
    ///     and forwarded as the `quality` field on OpenAI's
    ///     /v1/images/* endpoints (gpt-image-1: low ~$0.011, medium
    ///     ~$0.042, high ~$0.167 per 1024×1024 — 4× cheaper at low).
    ///     Lives in the prompt so the user controls cost/fidelity in
    ///     the same field they edit the rest of the instructions.
    /// v6 — re-runs the v5 prompt mutation (append-only loop in v5
    ///     bumped seedAIVersion to 5 WITHOUT touching existing
    ///     prompts, so alpha installs that came up under 0.35.18
    ///     never got the Quality: low line). Migration in
    ///     `Actions.swift:seedAI` now keys on `< 6` so those
    ///     installs run the prompt-append step on their next launch.
    /// v7 — added two AI counterparts to the 0.53.0 local actions:
    ///     `user.ai_latin_to_cyrillic` (mirrors the deterministic
    ///     #A18 with context-aware proper-noun handling) and
    ///     `user.ai_pretty_code` (mirrors #A19 with arbitrary-
    ///     language idiomatic format + language autodetect). Seeded
    ///     via the normal new-entry path in `seedAI`; no migration
    ///     beyond the standard new-descriptor insert.
    /// v8 — #A74 pre-distribution ID consolidation (0.56.0). All
    ///     seeded IDs renamed from `user.*` to `ai.<content_kind>.*`
    ///     convention. Migration in IDMigration056 rewrites every
    ///     dict-keyed-by-ID. Bundles 9 new AI seeds:
    ///       ai.text.make_shorter, .improve_clarity, .make_friendly,
    ///       ai.code.explain, .find_bugs, .translate,
    ///       ai.text.draft_email_reply, .generate_email_subject,
    ///       ai.text.clean_ocr.
    ///     The OCR action enables the screenshot → OCR → AI clean
    ///     → paste workflow which is one of DrPaste's flagship
    ///     stories.
    // v9 — adds the "Phonetic transcription (IPA)" text action.
    static let currentSeedVersion: Int = 9

    /// Sentinel for `providerID`: empty string means "use whatever provider is currently default".
    /// Action follows the user's default selection — change the default in Settings → AI and
    /// all default-bound actions instantly switch to the new provider.
    static let defaultProviderSentinel = ""

    static func defaults() -> [CustomAIDescriptor] {
        return [
            CustomAIDescriptor(
                id: "ai.text.summarize",
                title: "Summarize",
                promptTemplate: "Summarize the user's input in 1–3 sentences. Reply with the summary only, no preamble.",
                providerID: defaultProviderSentinel,
                // Prose summary — code has its own "Explain code".
                applicableTypes: ["text", "richText", "markdown"]
            ),
            // One Translate / Fix grammar each: a 1:1 text transform, so it
            // preserves Rich / Markdown formatting automatically (the separate
            // "(rich)" duplicates were identical and never actually preserved
            // anything — the flag was never wired through).
            CustomAIDescriptor(
                id: "ai.text.translate",
                title: "Translate",
                promptTemplate: "Translate the input to Spanish. If the user provides text in Spanish, translate to English instead. Reply with the translation only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"],
                preserveRichFormatting: true
            ),
            CustomAIDescriptor(
                id: "ai.text.fix_grammar",
                title: "Fix grammar",
                promptTemplate: "Fix grammar, spelling, and punctuation. Preserve the original language and voice. Reply with the corrected text only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"],
                preserveRichFormatting: true
            ),
            CustomAIDescriptor(
                id: "ai.text.formal_tone",
                title: "Formal tone",
                promptTemplate: "Rewrite the input in a more formal, professional tone. Preserve language and meaning. Reply with the rewritten text only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"]
            ),
            CustomAIDescriptor(
                id: "ai.text.ipa_transcription",
                title: "IPA",
                promptTemplate: "Transcribe the input into the International Phonetic Alphabet (IPA) — how it is pronounced. Use broad/phonemic transcription wrapped in slashes, e.g. /həˈloʊ/. Transcribe each word; keep the original word order and line breaks. Detect the language automatically. Reply with the IPA transcription only — no preamble, no explanations.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"]
            ),

            // #A18-AI Latin → Cyrillic. The deterministic local sibling
            // (`builtin.latin_to_cyrillic`) handles 80% of cases via a
            // greedy digraph table; this AI version exists for the
            // long tail — context-aware proper-noun handling
            // ("Tchaikovsky" → "Чайковский" not "Тчайковский"),
            // dialectal targets, established spellings for borrowed
            // words. Defaults to Russian; user edits the prompt to
            // pick Ukrainian / Bulgarian / Serbian.
            CustomAIDescriptor(
                id: "ai.text.latin_to_cyrillic",
                title: "Latin → Cyrillic",
                promptTemplate: """
                Transliterate the input from Latin script into Russian \
                Cyrillic. Use accepted Russian spellings for proper \
                nouns and borrowed words (e.g. Tchaikovsky → Чайковский, \
                not Тчайковский; Cherry → Черри; Apple → Эппл). \
                Preserve case structure — UPPERCASE stays uppercase, \
                Title Case stays Title Case, lowercase stays lowercase. \
                Pass non-Latin characters through unchanged. \
                Reply with the Cyrillic text only, no preamble.
                """,
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"]
            ),

            // #A19-AI Pretty Code. The local sibling
            // (`builtin.pretty_code_local`) handles JSON / XML / HTML /
            // CSS deterministically; this AI version handles arbitrary
            // languages with idiomatic style + language autodetect.
            // Common use: format Python / Rust / Go / Swift / Ruby
            // snippets pasted from messy contexts (Slack, chat, OCR).
            CustomAIDescriptor(
                id: "ai.code.pretty",
                title: "Pretty Code",
                promptTemplate: """
                Detect the programming language of the input and \
                reformat it idiomatically: clean indentation (2 spaces \
                unless the language convention is different — Go tabs, \
                Python 4), tidy whitespace, sensible line breaks, \
                consistent quote style. Preserve semantics exactly. \
                Do not add comments or commentary. Do not change \
                identifiers or rewrite logic. Reply with the formatted \
                code only — no preamble, no language fence, no notes.
                """,
                providerID: defaultProviderSentinel,
                applicableTypes: ["code"]
            ),

            // Image-AI seeds — v3 of the seed table. Each ships as a
            // regular CustomAIDescriptor with kind == .image so it
            // appears in Settings → Actions → AI alongside the text
            // entries, fully editable. Prompts are tuned for
            // gpt-image-1 (the only image-edit endpoint we currently
            // dispatch to); users can clone any of these into their
            // own styles by editing the prompt and giving the
            // descriptor a new id.
            // Quality directive — the trailing `Quality: low` line
            // is parsed out by `AIImageHTTP.extractQualityDirective`
            // and forwarded to OpenAI as the `quality` field
            // (gpt-image-1: low ~$0.011, medium ~$0.042, high
            // ~$0.167 per 1024×1024 — 4× saving at low). It lives in
            // the prompt template so the user controls the
            // cost/fidelity tradeoff in the same place they edit
            // the rest of the instructions — delete the line to
            // take OpenAI's default (medium), or change to `Quality:
            // high` for gallery-grade output.
            CustomAIDescriptor(
                id: "ai.image.sketch",
                title: "Pencil sketch",
                promptTemplate: """
                Convert this image into a hand-drawn pencil sketch. \
                Black and white only, no color. Clean cross-hatching \
                for shadow, light pencil strokes for mid-tones, \
                untouched white paper for highlights. Preserve the \
                subject's recognizable outline and proportions \
                exactly. Output as if drawn on plain white paper \
                with a graphite pencil.

                Quality: low
                """,
                providerID: defaultProviderSentinel,
                applicableTypes: ["image"],
                kind: .image
            ),
            CustomAIDescriptor(
                id: "ai.image.watercolor",
                title: "Watercolor",
                promptTemplate: """
                Transform this image into a soft watercolor painting. \
                Visible brush strokes, gentle color bleeding at \
                edges, translucent washes layered on top of each \
                other. Preserve the original composition and colour \
                palette but render it as if painted with wet \
                pigments on cold-press watercolor paper. Slight \
                paper texture is welcome.

                Quality: low
                """,
                providerID: defaultProviderSentinel,
                applicableTypes: ["image"],
                kind: .image
            ),
            CustomAIDescriptor(
                id: "ai.image.cartoon",
                title: "Cartoon",
                promptTemplate: """
                Convert this image into a clean cartoon illustration. \
                Bold black outlines around every shape, flat solid \
                fills inside (no gradients, no photoreal shading), \
                slightly simplified facial features and proportions. \
                Vibrant but limited color palette — think modern \
                animation production style. Preserve subject \
                recognizability.

                Quality: low
                """,
                providerID: defaultProviderSentinel,
                applicableTypes: ["image"],
                kind: .image
            ),

            // Text → Image seed — v4 of the seed table. The user
            // copies any concept text (a sentence, a sketch idea,
            // a meeting topic, a UX flow description) and runs this
            // action; the model produces a clean whiteboard-style
            // sketch they can drop into a doc, slide, or notes
            // app. Universal — works for technical diagrams,
            // brainstorm visualisations, slide-deck illustrations,
            // notebook headers. Black-and-white on white background
            // keeps the cost low (smaller PNG to download) and the
            // result reads as "I sketched this on a whiteboard"
            // rather than "AI made this for me".
            CustomAIDescriptor(
                id: "ai.text.image_whiteboard",
                title: "Whiteboard",
                promptTemplate: """
                Create a clean black-and-white whiteboard-style \
                illustration of the concept described below. Hand-drawn \
                marker on a white background, simple confident lines, \
                minimal shading. The drawing should clearly convey the \
                main idea visually — recognisable shapes, labelled \
                arrows or callouts only when essential. No photoreal \
                rendering, no colour, no gradients, no text outside \
                short callout labels. Aim for the feel of a quick \
                explainer sketch you'd see on a meeting whiteboard.

                Quality: low
                """,
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "markdown", "richText", "code"],
                kind: .textToImage
            ),

            // MARK: #A74 (0.56.0) — new AI writing seeds (3)

            CustomAIDescriptor(
                id: "ai.text.make_shorter",
                title: "Make shorter",
                promptTemplate: "Shorten the input while preserving the key meaning. Do not add new facts. Reply with the shortened text only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"]
            ),
            CustomAIDescriptor(
                id: "ai.text.improve_clarity",
                title: "Improve clarity",
                promptTemplate: "Improve clarity, readability, and flow while preserving the original meaning and tone. Do not add new facts. Reply with the improved text only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"]
            ),
            CustomAIDescriptor(
                id: "ai.text.make_friendly",
                title: "Make friendly",
                promptTemplate: "Rewrite the input in a warmer, friendlier tone while preserving the meaning. Do not add new facts. Reply with the rewritten text only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText", "markdown"]
            ),

            // MARK: #A74 (0.56.0) — new AI code seeds (3)

            CustomAIDescriptor(
                id: "ai.code.explain",
                title: "Explain code",
                promptTemplate: "Explain what this code does in practical terms. Be concise. Mention important assumptions, side effects, or risks if relevant. Reply with the explanation only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["code"]
            ),
            CustomAIDescriptor(
                id: "ai.code.find_bugs",
                title: "Find bugs",
                promptTemplate: "Review this code for bugs, unsafe behavior, edge cases, and maintainability problems. Return a concise list of findings with suggested fixes.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["code"]
            ),
            CustomAIDescriptor(
                id: "ai.code.translate",
                title: "Translate code",
                promptTemplate: """
                Translate this code to the target programming language below. \
                Preserve behavior. Keep the result idiomatic for the target \
                language. Add comments only where necessary. Reply with the \
                translated code only.

                Target language: Python (edit this line to change the target).
                """,
                providerID: defaultProviderSentinel,
                applicableTypes: ["code"]
            ),

            // MARK: #A74 (0.56.0) — new AI email seeds (2)

            CustomAIDescriptor(
                id: "ai.text.draft_email_reply",
                title: "Email reply",
                promptTemplate: "Draft a polite email reply to the message below. Keep it concise, practical, and professional. Do not invent commitments or facts. Reply with the draft only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText"],
                requiredTraits: ["containsEmails", "fromMailApp"]
            ),
            CustomAIDescriptor(
                id: "ai.text.generate_email_subject",
                title: "Email subject",
                promptTemplate: "Generate a concise email subject line for this message. Reply with the subject only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText"],
                requiredTraits: ["containsEmails", "fromMailApp"]
            ),

            // MARK: #A74 (0.56.0) — flagship OCR cleanup workflow

            // Closes the "screenshot → OCR → AI clean → paste" loop.
            // Strong semantic clipboard story — one of DrPaste's
            // marquee workflows. Curated-on so users discover the
            // chain naturally after running OCR.
            CustomAIDescriptor(
                id: "ai.text.clean_ocr",
                title: "Clean OCR",
                promptTemplate: "Clean up OCR text. Fix broken line breaks, spacing, punctuation, and obvious recognition errors while preserving the original meaning. Do not add new facts. Reply with the cleaned text only.",
                providerID: defaultProviderSentinel,
                applicableTypes: ["text", "richText"],
                requiredTraits: ["fromOCR"]
            )
        ]
    }

    /// Hotkey migration map: legacy factory action IDs → current
    /// seeded IDs. Used in ActionRegistry to transfer per-action
    /// hotkeys after seed. Kept for very-old installs that pre-date
    /// the `user.*` prefix; the modern path goes through
    /// `IDMigration056` (#A74) which handles `user.*` → `ai.*`.
    static let hotkeyIDMigration: [String: String] = [
        // Legacy 0.7-era short IDs → 0.56 convention
        "ai.summarize_legacy":      "ai.text.summarize",
        "ai.translate_es_en":       "ai.text.translate",
        "ai.translate_es_en_rich":  "ai.rich.translate",
        "ai.fix_grammar_legacy":    "ai.text.fix_grammar",
        "ai.fix_grammar_rich_legacy": "ai.rich.fix_grammar",
        "ai.formal_tone_legacy":    "ai.text.formal_tone"
    ]
}

// MARK: - Helpers for rich text items

func makeRichTextItem(_ attr: NSAttributedString, from item: ClipboardItem) -> ClipboardItem {
    var copy = item
    copy.semantic = .richText
    copy.previewText = attr.string
    let range = NSRange(location: 0, length: attr.length)

    // If the string carries inline attachments (file icons, embedded /
    // resized images, …) we MUST serialize to RTFD — plain RTF silently
    // drops every attachment, and the RTF encoder additionally chokes on
    // image attachments backed by multi-representation NSImages
    // (`CGImageDestinationFinalize failed for output type 'public.png'`).
    // Flat-RTFD keeps the PNG FileWrapper payloads intact and is a
    // representation key the HUD preview + paste pipeline already handle.
    var hasAttachment = false
    attr.enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
        if value != nil { hasAttachment = true; stop.pointee = true }
    }

    if hasAttachment,
       let rtfdData = try? attr.data(from: range,
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
        let tmpName = "ai-rich-\(UUID().uuidString).rtfd"
        let url = AppStorage.blobsDir.appendingPathComponent(tmpName)
        try? rtfdData.write(to: url)
        copy.representations = ["com.apple.flat-rtfd": tmpName]
        copy.typesOrdered = ["com.apple.flat-rtfd"]
    } else if let rtfData = try? attr.data(from: range,
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
        // Use a fake "store" path — actual blob write happens through ClipboardStore.
        // For HUD preview purposes we can keep the RTF as base64 inside previewText fallback,
        // but better: caller (refreshPreview) wraps this for display only.
        // Here we set representations to a sentinel that HUD recognizes.
        let tmpName = "ai-rich-\(UUID().uuidString).rtf"
        let url = AppStorage.blobsDir.appendingPathComponent(tmpName)
        try? rtfData.write(to: url)
        copy.representations = ["public.rtf": tmpName]
        copy.typesOrdered = ["public.rtf"]
    } else {
        copy.representations = [:]
        copy.typesOrdered = []
    }
    copy.previewImageRel = nil
    return copy
}

// MARK: - Legacy compatibility (existing call sites)

/// Legacy AIProviderConfig — only used by old call sites; remap to ProvidersConfig.
/// Will be removed once SettingsWindow / main.swift migrate.
struct AIProviderConfig {
    var anthropicAPIKey: String?
    var anthropicModel: String?

    static func load() -> AIProviderConfig {
        let cfg = ProvidersConfig.load()
        if let anth = cfg.providers.first(where: { $0.kind == .anthropic }) {
            return AIProviderConfig(
                anthropicAPIKey: APIKeyStorage.load(for: anth.id),
                anthropicModel: anth.model
            )
        }
        return AIProviderConfig()
    }

    static func configURL() -> URL { ProvidersConfig.configURL }
}
