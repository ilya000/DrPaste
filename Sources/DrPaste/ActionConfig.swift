//
//  ActionConfig.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Configuration model for Settings (Backlog #8):
//  enable/disable flags for built-in actions + custom AI action descriptors.
//  Сериализуется в actions.json. Export/Import используют этот же формат.
//

import Foundation

/// Описание custom AI action. Пользователь может добавлять / редактировать / удалять.
struct CustomAIDescriptor: Codable, Identifiable, Equatable {
    var id: String                       // unique, "user.<slug>"
    var title: String
    var promptTemplate: String
    var providerID: String               // "anthropic" / "openai" / "ollama"
    var applicableTypes: [String]        // semantic kinds: "text", "richText", "url", etc.
    var enabled: Bool = true
}

/// Корневая конфигурация. Сериализуется в actions.json.
struct ActionConfig: Codable, Equatable {
    var version: Int = 1
    /// builtin action.id → enabled. Default true (если ключа нет в map'е — enabled).
    var enabledFlags: [String: Bool] = [:]
    /// Пользовательские AI actions.
    var customAI: [CustomAIDescriptor] = []
    /// Полный snapshot для export (preferences тоже).
    var preferences: ActionConfigPreferences = ActionConfigPreferences()

    static func load() -> ActionConfig {
        let url = configURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(ActionConfig.self, from: data) else {
            return ActionConfig()
        }
        return cfg
    }

    func save() {
        let url = Self.configURL()
        guard let data = try? JSONEncoder().withPretty.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func configURL() -> URL {
        AppStorage.dataDir.appendingPathComponent("actions.json")
    }
}

struct ActionConfigPreferences: Codable, Equatable {
    var fontScale: Double = 1.0
    var soundVolume: Double = 0.6
    var soundsEnabled: [String: Bool] = [:]    // SoundCue.rawValue → enabled
}

private extension JSONEncoder {
    var withPretty: JSONEncoder {
        outputFormatting = [.prettyPrinted, .sortedKeys]
        return self
    }
}

// MARK: - Default samples for Settings playground

/// Bundled default sample text для каждого content tab.
/// Подобраны так чтобы максимум applicable actions имели заметный эффект.
enum SettingsSamples {
    static func sample(for kind: SemanticKind) -> ClipboardItem {
        let text: String
        let semantic = kind
        switch kind {
        case .text:
            text = """
            Здравствуйте! how are you doing today?
            My website is https://example.com/?utm_source=test
            Contact email: hello@example.com
            ETO TEKCT V NEPRAVILNOY RASKLADKE.
            """
        case .richText:
            text = "Some **rich** text with *italic* and a [link](https://example.com)"
        case .url:
            text = "https://example.com/article?utm_source=newsletter&utm_medium=email&fbclid=abc123&id=42"
        case .email:
            text = "hello@example.com"
        case .json:
            text = """
            {
              "name": "Test",
              "values": [1, 2, 3],
              "nested": {"city": "Sarasota", "zip": null},
              "active": true
            }
            """
        case .code:
            text = """
            func greet(name: String) -> String {
                return "Hello, " + name
            }
            """
        case .markdown:
            text = """
            # Title
            ## Subtitle
            - First item
            - Second item with [link](https://example.com)
            ```swift
            let x = 42
            ```
            """
        case .table:
            text = """
            name\tage\tcity
            Anna\t30\tBelgrade
            Boris\t42\tSarasota
            Vera\t27\tNizhny
            """
        case .image:
            text = "Image (use Settings sample image when ready)"
        case .pdf:
            text = "PDF (no sample)"
        case .files:
            text = "/Users/example/Documents/report.pdf, /Users/example/Documents/photo.jpg"
        case .unknown:
            text = ""
        }
        return ClipboardItem(
            id: UUID(),
            semantic: semantic,
            createdAt: Date(),
            representations: [:],
            typesOrdered: [],
            previewText: text,
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: "Settings Playground",
            sourceWindowTitle: nil,
            tags: []
        )
    }
}
