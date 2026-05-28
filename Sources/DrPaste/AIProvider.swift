//
//  AIProvider.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Multi-provider AI architecture (Правка #4 итерации 2):
//  - protocol AIProvider — единый интерфейс
//  - AIProviderRegistry — singleton с list of ConfiguredProvider
//  - AnthropicProvider, OpenAICompatibleProvider, GeminiProvider — конкретные реализации
//  - APIKeyStorage — Keychain-based key storage
//  - providers.json v2 — новый формат с массивом providers + миграция v1
//

import Foundation
import AppKit

// MARK: - Protocol

protocol AIProvider {
    var id: String { get }
    var displayName: String { get }
    var model: String { get }
    var isLocal: Bool { get }
    /// Имеет ли provider всё необходимое для работы (ключ для cloud, baseURL для local).
    var isReady: Bool { get }
    func run(prompt: String, input: String) async throws -> String
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
    case ollama             // local
    case lmstudio           // local
    case llamaCpp           // local
    case custom             // OpenAI-compatible custom endpoint

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai:    return "OpenAI GPT"
        case .gemini:    return "Google Gemini"
        case .grok:      return "xAI Grok"
        case .mistral:   return "Mistral"
        case .deepseek:  return "DeepSeek"
        case .ollama:    return "Ollama"
        case .lmstudio:  return "LM Studio"
        case .llamaCpp:  return "llama.cpp"
        case .custom:    return "Custom"
        }
    }

    /// Короткий лейбл для badge в UI (HUD action list).
    var badgeLabel: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai:    return "GPT"
        case .gemini:    return "Gemini"
        case .grok:      return "Grok"
        case .mistral:   return "Mistral"
        case .deepseek:  return "DeepSeek"
        case .ollama:    return "Ollama"
        case .lmstudio:  return "LM Studio"
        case .llamaCpp:  return "llama.cpp"
        case .custom:    return "Custom"
        }
    }

    /// SF Symbol для provider icon в action list (#9, #10).
    /// Используем семантические symbols — Apple-нативно, free from trademark issues.
    var iconName: String {
        switch self {
        case .anthropic: return "a.circle.fill"           // Anthropic "A"
        case .openai:    return "circle.hexagongrid.fill"  // OpenAI hexagon pattern
        case .gemini:    return "sparkle"                  // Gemini sparkle
        case .grok:      return "x.circle.fill"            // X / Grok
        case .mistral:   return "wind"                     // Mistral = wind
        case .deepseek:  return "magnifyingglass.circle.fill"
        case .ollama:    return "desktopcomputer"          // local
        case .lmstudio:  return "laptopcomputer"           // local
        case .llamaCpp:  return "terminal.fill"            // local cli-flavor
        case .custom:    return "gearshape.fill"
        }
    }

    var isLocal: Bool {
        switch self {
        case .ollama, .lmstudio, .llamaCpp: return true
        case .custom: return false   // could be local или remote, treat as remote default
        default: return false
        }
    }

    var requiresAPIKey: Bool { !isLocal && self != .custom ? true : false }
    var requiresBaseURL: Bool { isLocal || self == .custom }

    var defaultBaseURL: String? {
        switch self {
        case .ollama:   return "http://localhost:11434"
        case .lmstudio: return "http://localhost:1234"
        case .llamaCpp: return "http://localhost:8080"
        default: return nil
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-6"
        case .openai:    return "gpt-4o-mini"
        case .gemini:    return "gemini-2.5-flash"
        case .grok:      return "grok-4"
        case .mistral:   return "mistral-large-latest"
        case .deepseek:  return "deepseek-chat"
        case .ollama:    return "llama3.2:latest"
        case .lmstudio:  return "local-model"
        case .llamaCpp:  return "local-model"
        case .custom:    return "model"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .anthropic: return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"]
        case .openai:    return ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-5", "gpt-5-mini"]
        case .gemini:    return ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
        case .grok:      return ["grok-4", "grok-3"]
        case .mistral:   return ["mistral-large-latest", "codestral-latest", "mistral-small-latest"]
        case .deepseek:  return ["deepseek-chat", "deepseek-reasoner"]
        case .ollama:    return ["llama3.2:latest", "llama3.1:latest", "qwen2.5:latest", "deepseek-r1:latest"]
        default: return []
        }
    }
}

// MARK: - ConfiguredProvider

/// User-facing описание настроенного provider'а. Сериализуется в providers.json.
/// API key хранится отдельно в Keychain под providerID — здесь только не-секретные поля.
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

    /// Default — Anthropic + Ollama настроены как presets (без ключей пока).
    static func defaultConfig() -> ProvidersConfig {
        return ProvidersConfig(
            version: 2,
            defaultProviderID: "anthropic",
            providers: [
                ConfiguredProvider(id: "anthropic", kind: .anthropic,
                                   displayName: ProviderKind.anthropic.displayName,
                                   model: ProviderKind.anthropic.defaultModel,
                                   baseURL: nil),
                ConfiguredProvider(id: "ollama", kind: .ollama,
                                   displayName: ProviderKind.ollama.displayName,
                                   model: ProviderKind.ollama.defaultModel,
                                   baseURL: ProviderKind.ollama.defaultBaseURL,
                                   enabled: false)   // disabled пока пользователь не подтвердит
            ]
        )
    }

    // MARK: - Migration

    private struct LegacyV1: Codable {
        var anthropicAPIKey: String?
        var anthropicModel: String?
    }

    private static func migrate(from v1: LegacyV1) -> ProvidersConfig {
        // Если был ключ в v1 — перенесём его в Keychain, в config не сохраняем.
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
    }

    /// Получить ready provider по ID. Создаёт concrete instance по first call,
    /// кеширует, инвалидируется при reload().
    func provider(id: String) -> AIProvider? {
        if let cached = providerCache[id] { return cached }
        guard let cp = config.providers.first(where: { $0.id == id }), cp.enabled else { return nil }
        guard let p = makeConcrete(from: cp) else { return nil }
        providerCache[id] = p
        return p
    }

    /// Default provider (для AI actions без explicit providerID).
    var defaultProvider: AIProvider? {
        if let id = config.defaultProviderID, let p = provider(id: id) {
            return p
        }
        // fallback на первый enabled
        for cp in config.providers where cp.enabled {
            if let p = provider(id: cp.id) { return p }
        }
        return nil
    }

    /// Получить kind для UI badge.
    func kind(forProviderID id: String) -> ProviderKind? {
        config.providers.first(where: { $0.id == id })?.kind
    }

    /// Upsert provider. Если apiKey не nil — сохраняем в Keychain.
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
    }

    func remove(providerID: String) {
        APIKeyStorage.remove(for: providerID)
        var newCfg = config
        newCfg.providers.removeAll { $0.id == providerID }
        if newCfg.defaultProviderID == providerID {
            newCfg.defaultProviderID = newCfg.providers.first?.id
        }
        config = newCfg
        providerCache.removeValue(forKey: providerID)
    }

    func setDefault(providerID: String) {
        var newCfg = config
        newCfg.defaultProviderID = providerID
        config = newCfg
    }

    /// Принудительно сбросить кеш — после внешних изменений config.
    func invalidateCache() {
        providerCache.removeAll()
    }

    /// Test connection — посылает короткий prompt и измеряет latency.
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

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)

        struct Block: Decodable { let type: String; let text: String? }
        struct Resp: Decodable { let content: [Block] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
    }
}

// MARK: - OpenAICompatibleProvider

/// Unified provider для OpenAI-compatible chat/completions API:
/// OpenAI, xAI Grok, Mistral, DeepSeek, Ollama, LM Studio, llama.cpp, Custom.
/// Различаются только baseURL и наличием Authorization header.
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
        // Не отправляем max_tokens — gpt-5 family требует max_completion_tokens,
        // gpt-4 ожидает max_tokens. Безопаснее не указывать (API default разумный).
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
            (data, resp) = try await URLSession.shared.data(for: req)
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

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)

        struct Part: Decodable { let text: String? }
        struct Content: Decodable { let parts: [Part] }
        struct Candidate: Decodable { let content: Content }
        struct Resp: Decodable { let candidates: [Candidate] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.candidates.first?.content.parts.compactMap { $0.text }.joined() ?? ""
    }
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

    init(id: String, title: String, promptTemplate: String,
         providerID: String? = nil,
         applicableTypes: Set<SemanticKind> = [.text, .richText, .url, .json, .markdown, .code],
         preserveRichFormatting: Bool = false) {
        self.id = id
        self.title = title
        self.promptTemplate = promptTemplate
        self.providerID = providerID
        self.applicableTypes = applicableTypes
        self.preserveRichFormatting = preserveRichFormatting
    }

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        applicableTypes.contains(item.semantic) || context.contains(.plain)
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
                          reason: "AI provider not configured. Add API key in Settings.",
                          recovery: .openProvidersConfig)
        }
        do {
            // Правка #9: MD round-trip для rich text
            let useRich = preserveRichFormatting && item.semantic == .richText
            let inputText: String
            let systemAddition: String
            if useRich, let md = RichTextHelpers.attributedStringToMarkdown(loadAttr(item: item)) {
                inputText = md
                systemAddition = "\n\nThe input is in Markdown format. Preserve all Markdown markup exactly (bold **, italic *, links [text](url), code `inline`, code blocks ```, headings #, lists -/1.). Only modify the text content, never the markup."
            } else {
                inputText = item.previewText ?? ""
                systemAddition = ""
            }
            let result = try await provider.run(prompt: promptTemplate + systemAddition, input: inputText)
            if useRich {
                if let ns = RichTextHelpers.markdownToAttributedString(result) {
                    return .preview(makeRichTextItem(ns, from: item))
                }
            }
            return .preview(makeTextItem(result, from: item))
        } catch AIProviderError.missingAPIKey {
            return .failed(original: item,
                          reason: "AI provider not configured. Add API key in Settings.",
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
        guard let rel = item.representations["public.rtf"],
              let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
              let attr = try? NSAttributedString(data: data,
                                                 options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil)
        else {
            return NSAttributedString(string: item.previewText ?? "")
        }
        return attr
    }
}

// MARK: - Default AI actions (factory presets)

enum DefaultAIActions {
    /// Default AI actions используют default provider (nil providerID).
    /// Spanish ↔ English как default translate target (Правка #10).
    static func make() -> [AIAction] {
        return [
            AIAction(id: "ai.summarize",
                     title: "summarize",
                     promptTemplate: "Summarize the user's input in 1–3 sentences. Reply with the summary only, no preamble.",
                     applicableTypes: [.text, .richText, .markdown, .code]),
            AIAction(id: "ai.translate_es_en",
                     title: "translate",
                     promptTemplate: "Translate the input to Spanish. If the user provides text in Spanish, translate to English instead. Reply with the translation only.",
                     applicableTypes: [.text, .richText, .markdown]),
            AIAction(id: "ai.translate_es_en_rich",
                     title: "translate (rich)",
                     promptTemplate: "Translate the input to Spanish. If the user provides text in Spanish, translate to English instead. Reply with the translation only.",
                     applicableTypes: [.richText],
                     preserveRichFormatting: true),
            AIAction(id: "ai.fix_grammar",
                     title: "fix grammar",
                     promptTemplate: "Fix grammar, spelling, and punctuation. Preserve the original language and voice. Reply with the corrected text only.",
                     applicableTypes: [.text, .richText, .markdown]),
            AIAction(id: "ai.fix_grammar_rich",
                     title: "fix grammar (rich)",
                     promptTemplate: "Fix grammar, spelling, and punctuation. Preserve the original language and voice. Reply with the corrected text only.",
                     applicableTypes: [.richText],
                     preserveRichFormatting: true),
            AIAction(id: "ai.formal_tone",
                     title: "formal tone",
                     promptTemplate: "Rewrite the input in a more formal, professional tone. Preserve language and meaning. Reply with the rewritten text only.",
                     applicableTypes: [.text, .richText, .markdown])
        ]
    }
}

// MARK: - Helpers for rich text items

func makeRichTextItem(_ attr: NSAttributedString, from item: ClipboardItem) -> ClipboardItem {
    var copy = item
    copy.semantic = .richText
    copy.previewText = attr.string
    // Generate RTF representation and write to blob
    if let rtfData = try? attr.data(from: NSRange(location: 0, length: attr.length),
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
