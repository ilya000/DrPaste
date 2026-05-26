//
//  AIProvider.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Bring-your-own-AI: абстракция + Anthropic provider.
//  AI actions всегда регистрируются (Backlog #2): без ключа — возвращают .failed
//  с recovery action, что даёт discovery в HUD.
//

import Foundation

protocol AIProvider {
    var id: String { get }
    var displayName: String { get }
    func run(prompt: String, input: String) async throws -> String
}

enum AIProviderError: Error {
    case missingAPIKey
    case http(status: Int, body: String)
    case decode(String)
}

struct AIProviderConfig: Codable {
    var anthropicAPIKey: String?
    var anthropicModel: String?

    static func load() -> AIProviderConfig {
        let url = configURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(AIProviderConfig.self, from: data) else {
            return AIProviderConfig()
        }
        return cfg
    }

    static func configURL() -> URL {
        AppStorage.dataDir.appendingPathComponent("providers.json")
    }
}

final class AnthropicProvider: AIProvider {
    let id = "anthropic"
    let displayName = "Anthropic (Claude)"

    private let apiKey: String?
    private let model: String

    init(config: AIProviderConfig) {
        self.apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? config.anthropicAPIKey
        self.model = config.anthropicModel ?? "claude-sonnet-4-6"
    }

    var hasKey: Bool { (apiKey ?? "").isEmpty == false }

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
        guard let http = resp as? HTTPURLResponse else {
            throw AIProviderError.decode("no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AIProviderError.http(status: http.statusCode, body: bodyStr)
        }

        struct AnthropicResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
    }
}

// MARK: - AI Action

struct AIAction: ClipboardAction {
    let id: String
    let title: String
    let isLocal: Bool = false
    let promptTemplate: String
    let provider: AIProvider

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // AI actions всегда видны для plain text (Backlog #2 discovery).
        // Если ключа нет — apply вернёт .failed с recovery.
        context.contains(.plain)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        do {
            let result = try await provider.run(prompt: promptTemplate, input: item.previewText ?? "")
            return .preview(makeTextItem(result, from: item))
        } catch AIProviderError.missingAPIKey {
            return .failed(original: item,
                          reason: "AI provider not configured. Add API key in Settings.",
                          recovery: .openProvidersConfig)
        } catch AIProviderError.http(let status, _) {
            return .failed(original: item,
                          reason: "AI provider HTTP \(status). Check API key and model.",
                          recovery: .openProvidersConfig)
        } catch {
            return .failed(original: item,
                          reason: "AI provider error: \(error.localizedDescription)",
                          recovery: nil)
        }
    }
}

enum DefaultAIActions {
    static func make(provider: AIProvider) -> [AIAction] {
        return [
            AIAction(id: "ai.summarize", title: "AI: summarize",
                     promptTemplate: "Summarize the user's input in 1–3 sentences. Reply with the summary only, no preamble.",
                     provider: provider),
            AIAction(id: "ai.translate_ru_en", title: "AI: translate RU↔EN",
                     promptTemplate: "Translate the user's input. If it's Russian, translate to English. If English, translate to Russian. Reply with the translation only.",
                     provider: provider),
            AIAction(id: "ai.fix_grammar", title: "AI: fix grammar",
                     promptTemplate: "Fix grammar, spelling, and punctuation. Preserve the original language and voice. Reply with the corrected text only.",
                     provider: provider),
            AIAction(id: "ai.formal_tone", title: "AI: formal tone",
                     promptTemplate: "Rewrite the input in a more formal, professional tone. Preserve language and meaning. Reply with the rewritten text only.",
                     provider: provider)
        ]
    }
}
