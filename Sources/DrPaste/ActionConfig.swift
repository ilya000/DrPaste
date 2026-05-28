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
import AppKit

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
    var version: Int = 4
    /// builtin action.id → enabled. Default true (если ключа нет в map'е — enabled).
    var enabledFlags: [String: Bool] = [:]
    /// Пользовательские AI actions.
    var customAI: [CustomAIDescriptor] = []
    /// Custom titles per action ID (правка #6 lite — пользователь может переименовать built-in).
    /// Если ключа нет — используется action.title (default).
    var customTitles: [String: String] = [:]
    /// Custom order per content type (правка #5).
    /// Key — SemanticKind.rawValue, value — [actionID] в порядке отображения.
    /// Actions не в массиве идут после, в default order.
    var actionOrder: [String: [String]] = [:]
    /// User-defined transformations (engine architecture, light version).
    var customTransformations: [CustomTransformationDescriptor] = []
    /// Per-action hotkeys: actionID → ActionHotkey.
    /// When pressed, action triggers directly without opening the HUD.
    var actionHotkeys: [String: ActionHotkey] = [:]
    /// Seed version counter — increments when new default AI actions are bundled.
    /// Existing users get new defaults on upgrade; existing entries are not duplicated.
    var seedAIVersion: Int = 0
    /// Full snapshot for export (also includes preferences).
    var preferences: ActionConfigPreferences = ActionConfigPreferences()

    init() {}

    /// Custom decode для backward compat: новые поля используют decodeIfPresent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.enabledFlags = try c.decodeIfPresent([String: Bool].self, forKey: .enabledFlags) ?? [:]
        self.customAI = try c.decodeIfPresent([CustomAIDescriptor].self, forKey: .customAI) ?? []
        self.customTitles = try c.decodeIfPresent([String: String].self, forKey: .customTitles) ?? [:]
        self.actionOrder = try c.decodeIfPresent([String: [String]].self, forKey: .actionOrder) ?? [:]
        self.customTransformations = try c.decodeIfPresent([CustomTransformationDescriptor].self,
                                                            forKey: .customTransformations) ?? []
        self.actionHotkeys = try c.decodeIfPresent([String: ActionHotkey].self,
                                                    forKey: .actionHotkeys) ?? [:]
        self.seedAIVersion = try c.decodeIfPresent(Int.self, forKey: .seedAIVersion) ?? 0
        self.preferences = try c.decodeIfPresent(ActionConfigPreferences.self,
                                                 forKey: .preferences) ?? ActionConfigPreferences()
    }

    private enum CodingKeys: String, CodingKey {
        case version, enabledFlags, customAI, customTitles, actionOrder,
             customTransformations, actionHotkeys, seedAIVersion, preferences
    }

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

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
        self.soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.6
        self.soundsEnabled = try c.decodeIfPresent([String: Bool].self, forKey: .soundsEnabled) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case fontScale, soundVolume, soundsEnabled
    }
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
        if kind == .richText {
            return richTextSample()
        }
        let text: String
        let semantic = kind
        switch kind {
        case .text:
            text = """
            ¡Hola! how are you doing today?
            My website is https://example.com/?utm_source=test
            Contact email: hello@example.com
            tHIS tEXT has WRONG capitalization.
            """
        case .richText:
            text = ""  // unreachable
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
            Anna\t30\tMadrid
            Carlos\t42\tBarcelona
            Sofia\t27\tValencia
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

    /// Programmatically генерирует rich text sample как настоящий RTF
    /// (правка #9 детали). Сохраняет в blobs storage с фиксированным именем —
    /// перезаписываемое при каждом запросе, чтобы изменения в коде сразу применялись.
    static func richTextSample() -> ClipboardItem {
        let s = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        let bold = NSFontManager.shared.convert(body, toHaveTrait: .boldFontMask)
        let italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        let h1 = NSFont.systemFont(ofSize: 22, weight: .bold)
        let h2 = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        s.append(.init(string: "Welcome to DrPaste\n", attributes: [.font: h1]))
        s.append(.init(string: "\nDrPaste is a ", attributes: [.font: body]))
        s.append(.init(string: "press-and-hold", attributes: [.font: bold]))
        s.append(.init(string: " clipboard manager for macOS, designed as the natural extension of the ",
                       attributes: [.font: body]))
        s.append(.init(string: "Paste", attributes: [.font: italic]))
        s.append(.init(string: " gesture itself.\n\n", attributes: [.font: body]))

        s.append(.init(string: "What's in this sample\n", attributes: [.font: h2]))
        s.append(.init(string: "\n  • Headings (h1, h2)\n", attributes: [.font: body]))
        s.append(.init(string: "  • ", attributes: [.font: body]))
        s.append(.init(string: "Bold", attributes: [.font: bold]))
        s.append(.init(string: " and ", attributes: [.font: body]))
        s.append(.init(string: "italic", attributes: [.font: italic]))
        s.append(.init(string: " emphasis\n", attributes: [.font: body]))
        s.append(.init(string: "  • Inline ", attributes: [.font: body]))
        s.append(.init(string: "code", attributes: [.font: mono,
                                                    .backgroundColor: NSColor.controlBackgroundColor]))
        s.append(.init(string: " in monospaced font\n", attributes: [.font: body]))
        s.append(.init(string: "  • A hyperlink: ", attributes: [.font: body]))
        s.append(.init(string: "github.com/ilya000/DrPaste",
                       attributes: [.font: body,
                                    .link: URL(string: "https://github.com/ilya000/DrPaste")!,
                                    .foregroundColor: NSColor.linkColor,
                                    .underlineStyle: NSUnderlineStyle.single.rawValue]))
        s.append(.init(string: "\n\n", attributes: [.font: body]))

        s.append(.init(string: "Try ", attributes: [.font: body]))
        s.append(.init(string: "Rich → Markdown", attributes: [.font: bold]))
        s.append(.init(string: ", ", attributes: [.font: body]))
        s.append(.init(string: "Rich → HTML", attributes: [.font: bold]))
        s.append(.init(string: ", or ", attributes: [.font: body]))
        s.append(.init(string: "Rich → Wiki markup", attributes: [.font: bold]))
        s.append(.init(string: " to see the conversion in action.", attributes: [.font: body]))

        let range = NSRange(location: 0, length: s.length)
        let rtfData = (try? s.data(from: range,
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        let relPath = "richtext-sample.rtf"
        let url = AppStorage.blobsDir.appendingPathComponent(relPath)
        try? rtfData.write(to: url)

        return ClipboardItem(
            id: UUID(),
            semantic: .richText,
            createdAt: Date(),
            representations: ["public.rtf": relPath],
            typesOrdered: ["public.rtf"],
            previewText: s.string,
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: "Settings Playground",
            sourceWindowTitle: nil,
            tags: []
        )
    }
}
