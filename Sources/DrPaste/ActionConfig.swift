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
//  Serialized to actions.json. Export / Import use the same format.
//

import Foundation
import AppKit

/// Descriptor for a custom AI action. Users can add, edit, and delete them.
/// `kind` selects between text-in/text-out (`.text`) and image-in/image-out
/// (`.image`) operation. Both share the same descriptor shape — id, title,
/// promptTemplate, providerID — so the Settings → Actions editor renders
/// either with the same form, and a user can clone a seeded image style
/// (e.g. "AI: Pencil sketch") into their own "Stained glass" descriptor
/// by editing the prompt. `kind` decodes to `.text` when absent so
/// pre-0.32.0 actions.json files remain forward-compatible.
struct CustomAIDescriptor: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Equatable {
        case text         // text-in → text-out, uses AIProvider.run / .stream
        case image        // image-in → image-out, uses gpt-image-1 /images/edits
        case textToImage  // text-in → image-out, uses /images/generations
                          // (OpenAI), :generateContent (Gemini), or
                          // chat completions with text-only multimodal
                          // request returning image (OpenRouter)
    }

    var id: String                       // unique, "user.<slug>"
    var title: String
    var promptTemplate: String
    var providerID: String               // "anthropic" / "openai" / "ollama"
    var applicableTypes: [String]        // semantic kinds: "text", "richText", "url", "image", ...
    var enabled: Bool = true
    /// Operation mode. Default `.text` preserves backward compatibility with
    /// pre-0.32.0 actions.json files (where this field doesn't exist).
    var kind: Kind = .text
    // #A75 trait gating — "Show this action when…". Empty = always.
    var requiredTraits: [String] = []
    var forbiddenTraits: [String] = []
    /// When true and the input is rich text / Markdown, the action round-trips
    /// through Markdown (rich → md → AI, instructed to keep markup → md → rich)
    /// so formatting survives. Suits 1:1 transforms (translate, fix grammar);
    /// false for restructuring actions (summarize, make shorter) where markup
    /// preservation is meaningless.
    var preserveRichFormatting: Bool = false

    init(id: String,
         title: String,
         promptTemplate: String,
         providerID: String,
         applicableTypes: [String],
         enabled: Bool = true,
         kind: Kind = .text,
         requiredTraits: [String] = [],
         forbiddenTraits: [String] = [],
         preserveRichFormatting: Bool = false) {
        self.id = id
        self.title = title
        self.promptTemplate = promptTemplate
        self.providerID = providerID
        self.applicableTypes = applicableTypes
        self.enabled = enabled
        self.kind = kind
        self.requiredTraits = requiredTraits
        self.forbiddenTraits = forbiddenTraits
        self.preserveRichFormatting = preserveRichFormatting
    }

    /// Custom decoder so `kind` defaults to `.text` when absent — old
    /// actions.json files predate the field, and forcing them to be re-
    /// seeded would lose any user-edited prompts.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.promptTemplate = try c.decode(String.self, forKey: .promptTemplate)
        self.providerID = try c.decode(String.self, forKey: .providerID)
        self.applicableTypes = try c.decode([String].self, forKey: .applicableTypes)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        self.requiredTraits = try c.decodeIfPresent([String].self, forKey: .requiredTraits) ?? []
        self.forbiddenTraits = try c.decodeIfPresent([String].self, forKey: .forbiddenTraits) ?? []
        self.preserveRichFormatting = try c.decodeIfPresent(Bool.self, forKey: .preserveRichFormatting) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, promptTemplate, providerID, applicableTypes, enabled, kind
        case requiredTraits, forbiddenTraits, preserveRichFormatting
    }
}

/// Root configuration. Serialized to actions.json.
struct ActionConfig: Codable, Equatable {
    var version: Int = 4
    /// builtin action.id → enabled. Default true (missing key implies enabled).
    var enabledFlags: [String: Bool] = [:]
    /// User-defined AI actions.
    var customAI: [CustomAIDescriptor] = []
    /// Custom titles keyed by action ID — users can rename built-ins. When no
    /// override exists, the action's default title is used.
    var customTitles: [String: String] = [:]
    /// Custom descriptions keyed by action ID — the one-line blurb shown as the
    /// second line of the action row in Settings. When no override exists the
    /// bundled default is used (built-in → `BuiltinActionMetadata.descriptions`,
    /// transformation → engine description, AI → prompt template). Empty string
    /// is NOT stored (an empty override would just hide the useful default).
    var customDescriptions: [String: String] = [:]
    /// Custom action order per content type. Key is SemanticKind.rawValue,
    /// value is the list of action IDs in display order. Actions not present
    /// in the array appear after the listed ones in their default order.
    var actionOrder: [String: [String]] = [:]
    /// User-defined transformations (engine architecture, light version).
    var customTransformations: [CustomTransformationDescriptor] = []
    /// Per-action hotkeys: actionID → ActionHotkey.
    /// When pressed, action triggers directly without opening the HUD.
    var actionHotkeys: [String: ActionHotkey] = [:]
    /// Seed version counter — increments when new default AI actions are bundled.
    /// Existing users get new defaults on upgrade; existing entries are not duplicated.
    var seedAIVersion: Int = 0
    /// Seed version counter for bundled transformations (DefaultTransformationSeed).
    /// Migration on bump: new descriptors are appended, prior `enabledFlags` for
    /// the seeded IDs are folded into the descriptor's `enabled` field.
    var seedTransformationVersion: Int = 0
    /// Per-action overrides for the Edit Action sheet's Test panel Input
    /// field. Keys are action IDs (built-in `builtin.*`, custom AI
    /// `user.*`, or custom transformation `user.transform.*`). Values
    /// are the user's typed-in sample text — replaces the curated
    /// default from `ActionTestSamples.textSample(for:)` when present.
    /// Empty string entries mean "user explicitly cleared this sample";
    /// missing keys mean "use the curated default if any". Persists in
    /// actions.json so the user's hand-picked examples survive across
    /// app restarts and exports.
    var actionTestSamples: [String: String] = [:]
    /// Per-action overrides for image inputs in the Test panel. Keys
    /// are action IDs (same shape as `actionTestSamples`); values are
    /// filenames relative to `AppStorage.imagesDir` pointing at a
    /// PNG/JPEG/HEIC the user dropped onto the Input field. Image
    /// actions (OCR, AI: Watercolor, Grayscale, …) read this when
    /// loading the Test panel — falls back to a procedurally-
    /// generated sample when no override exists. Stored separately
    /// from `actionTestSamples` because the value semantics differ
    /// (text is human-readable, image rel is opaque) and a single
    /// action could in principle have both (descriptive Input
    /// placeholder text + an image override) although today no
    /// action uses both at once.
    var actionTestImageBlobs: [String: String] = [:]
    /// Per-tab Sample input text overrides for the Settings
    /// Playground. Keys are `SemanticKind.rawValue` ("text",
    /// "richText", "url", …); values are the user's edited sample.
    /// Mirrors `actionTestSamples` but keyed by content-type tab
    /// rather than action ID — the Playground sample is shared
    /// across all actions inside a tab, while the Edit Action sheet
    /// keeps a per-action override. Missing key → use the curated
    /// `SettingsSamples.sample(for: kind)` default.
    var playgroundSamples: [String: String] = [:]
    /// Per-tab image override for the Settings Playground's Image
    /// tab. Single key "image" (room to extend if a future tab also
    /// wants an image input) → filename inside `AppStorage.imagesDir`.
    /// Missing key → fall back to the standard `makeSampleImageItem`
    /// chain (bundled Mandrill → cached Mandrill → User Pictures
    /// system photo → SF Symbol).
    var playgroundImageBlobs: [String: String] = [:]
    /// Full snapshot for export (also includes preferences).
    var preferences: ActionConfigPreferences = ActionConfigPreferences()

    init() {}

    /// Custom decode for backward compatibility: new fields use decodeIfPresent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.enabledFlags = try c.decodeIfPresent([String: Bool].self, forKey: .enabledFlags) ?? [:]
        self.customAI = try c.decodeIfPresent([CustomAIDescriptor].self, forKey: .customAI) ?? []
        self.customTitles = try c.decodeIfPresent([String: String].self, forKey: .customTitles) ?? [:]
        self.customDescriptions = try c.decodeIfPresent([String: String].self, forKey: .customDescriptions) ?? [:]
        self.actionOrder = try c.decodeIfPresent([String: [String]].self, forKey: .actionOrder) ?? [:]
        self.customTransformations = try c.decodeIfPresent([CustomTransformationDescriptor].self,
                                                            forKey: .customTransformations) ?? []
        self.actionHotkeys = try c.decodeIfPresent([String: ActionHotkey].self,
                                                    forKey: .actionHotkeys) ?? [:]
        self.seedAIVersion = try c.decodeIfPresent(Int.self, forKey: .seedAIVersion) ?? 0
        self.seedTransformationVersion = try c.decodeIfPresent(Int.self, forKey: .seedTransformationVersion) ?? 0
        self.actionTestSamples = try c.decodeIfPresent([String: String].self,
                                                       forKey: .actionTestSamples) ?? [:]
        self.actionTestImageBlobs = try c.decodeIfPresent([String: String].self,
                                                          forKey: .actionTestImageBlobs) ?? [:]
        self.playgroundSamples = try c.decodeIfPresent([String: String].self,
                                                       forKey: .playgroundSamples) ?? [:]
        self.playgroundImageBlobs = try c.decodeIfPresent([String: String].self,
                                                          forKey: .playgroundImageBlobs) ?? [:]
        self.preferences = try c.decodeIfPresent(ActionConfigPreferences.self,
                                                 forKey: .preferences) ?? ActionConfigPreferences()
    }

    private enum CodingKeys: String, CodingKey {
        case version, enabledFlags, customAI, customTitles, customDescriptions, actionOrder,
             customTransformations, actionHotkeys, seedAIVersion,
             seedTransformationVersion, actionTestSamples,
             actionTestImageBlobs, playgroundSamples, playgroundImageBlobs,
             preferences
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

/// Bundled default sample text for each content tab. Chosen so that as many
/// applicable actions as possible produce a visible effect.
enum SettingsSamples {
    static func sample(for kind: SemanticKind) -> ClipboardItem {
        if kind == .richText {
            return richTextSample()
        }
        if kind == .image {
            // Delegate to the same procedural / bundled-Mandrill
            // sample the Edit Action sheet uses, so the user sees
            // the SAME illustrative image in every test surface.
            // `makeSampleImageItem()` is @MainActor; the Playground
            // already runs on the main actor via SwiftUI, so the
            // call is safe through MainActor.assumeIsolated.
            if let img = MainActor.assumeIsolated({
                ActionTestSamples.makeSampleImageItem()
            }) {
                return img
            }
            // If even the fallback path fails (file I/O glitch),
            // fall through to a text placeholder so the Playground
            // doesn't crash.
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
            // example.com/ is real and always returns a page with a <title>, so
            // Preview card works; the tracking params let Clean URL demo too.
            text = "https://example.com/?utm_source=newsletter&utm_medium=email&fbclid=abc123&id=42"
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

            The venue is 5 meters wide, it was 25°C inside, and it's a 2 km walk.

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
            // Real, always-present paths so file actions actually work in the
            // playground (Reveal in Finder opens these; Copy paths shows real
            // paths). The user can drag their own files in to replace.
            text = "\(NSHomeDirectory()), /Applications"
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

    /// Programmatically generates a real RTF rich-text sample and writes it
    /// to blob storage with a fixed filename so edits to this code take effect
    /// on the next request.
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
