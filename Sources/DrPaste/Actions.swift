//
//  Actions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  ClipboardAction protocol + ApplyOutcome enum (Backlog #2) +
//  base local actions. Дополнительные categorized actions —
//  в FileActions.swift, URLActions.swift, TextActions.swift,
//  JSONActions.swift, TableActions.swift, MarkdownActions.swift,
//  CodeActions.swift, ImageActions.swift.
//

import Foundation

// MARK: - Outcome model (Backlog #2 + #4 + #7)

enum ApplyOutcome {
    /// Обычная transformation — preview обновляется, на commit пишется в pasteboard и paste-ится.
    case preview(ClipboardItem)
    /// Action не смог применить (нет AI key, malformed input, требует AX).
    /// HUD показывает original + inline notice с reason и optional recovery action.
    /// На commit пишется original (paste-as-is).
    case failed(original: ClipboardItem, reason: String, recovery: RecoveryAction?)
    /// Side-effect (Reveal in Finder, Open URL) — на commit выполняется action и закрывается HUD.
    case sideEffect(description: String, perform: () -> Void)
    /// Alternative commit (Type Slowly, в будущем typeFast) — на commit вместо ⌘V
    /// запускается специальный simulator.
    case alternativeCommit(ClipboardItem, style: CommitStyle)
}

enum CommitStyle {
    case standardPaste                                  // default: write + ⌘V
    case typeSlowly(delay: TimeInterval, jitter: Double)
    case typeFast                                        // 50ms, no jitter
}

enum RecoveryAction {
    case openProvidersConfig
    case openAccessibilitySettings
    case custom(label: String, url: URL)
}

// MARK: - Action protocol

protocol ClipboardAction {
    var id: String { get }
    var title: String { get }
    var isLocal: Bool { get }
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome
}

// MARK: - Identity

struct IdentityAction: ClipboardAction {
    let id = "builtin.identity"
    let title = "Paste as is"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool { true }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        .preview(item)
    }
}

// MARK: - Helpers

func makeTextItem(_ text: String, from item: ClipboardItem) -> ClipboardItem {
    var copy = item
    copy.semantic = .text
    copy.previewText = text
    // Empty representations — PasteboardWriter использует fallback на previewText
    // (это transformed item, raw representations устарели).
    copy.representations = [:]
    copy.typesOrdered = []
    copy.previewImageRel = nil
    return copy
}

func makePlainText(_ item: ClipboardItem) -> ClipboardItem {
    makeTextItem(item.previewText ?? "", from: item)
}

// MARK: - Basic text actions

struct CleanFormattingAction: ClipboardAction {
    let id = "builtin.clean_formatting"
    let title = "Plain text"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.richText)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        .preview(makePlainText(item))
    }
}

struct UppercaseAction: ClipboardAction {
    let id = "builtin.uppercase"
    let title = "UPPERCASE"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        .preview(makeTextItem((item.previewText ?? "").uppercased(), from: item))
    }
}

struct LowercaseAction: ClipboardAction {
    let id = "builtin.lowercase"
    let title = "lowercase"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        .preview(makeTextItem((item.previewText ?? "").lowercased(), from: item))
    }
}

struct TrimWhitespaceAction: ClipboardAction {
    let id = "builtin.trim"
    let title = "Trim whitespace"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let lines = (item.previewText ?? "").split(separator: "\n", omittingEmptySubsequences: false)
        let result = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .preview(makeTextItem(result, from: item))
    }
}

// MARK: - Layout repair

struct LayoutRepairAction: ClipboardAction {
    let id = "builtin.layout_repair"
    let title = "Fix keyboard layout"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.layoutWrong) || context.contains(.mixedScript)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let repaired = KeyboardLayoutRepair.repair(item.previewText ?? "")
        return .preview(makeTextItem(repaired, from: item))
    }
}

// MARK: - Registry

/// ActionRegistry хранит зарегистрированные actions + конфигурацию (Backlog #8):
/// enabledFlags для built-in (по action.id) и custom AI actions из ActionConfig.
/// При applicable() фильтрует и по applicability контекста, и по enabled flag.
final class ActionRegistry: ObservableObject {

    @Published private(set) var actions: [ClipboardAction] = []
    @Published var config: ActionConfig = .load() {
        didSet {
            if oldValue != config {
                config.save()
                rebuildCustomAI()
            }
        }
    }

    /// AI provider — нужен для конструирования AIAction из CustomAIDescriptor.
    var aiProvider: AIProvider?

    init() {
        // Built-in core actions. Дальше AppDelegate регистрирует action packs.
        actions = [
            IdentityAction(),
            LayoutRepairAction(),
            CleanFormattingAction(),
            TrimWhitespaceAction(),
            UppercaseAction(),
            LowercaseAction()
        ]
    }

    func register(_ action: ClipboardAction) {
        actions.append(action)
    }

    func register<S: Sequence>(_ batch: S) where S.Element == ClipboardAction {
        actions.append(contentsOf: batch)
    }

    /// Все actions с учётом enabled flag.
    var allEnabled: [ClipboardAction] {
        actions.filter { isEnabled($0.id) }
    }

    func applicable(for item: ClipboardItem, context: ContentContext) -> [ClipboardAction] {
        actions.filter { isEnabled($0.id) && $0.isApplicable(item: item, context: context) }
    }

    /// Built-in default — enabled. Если в config флаг есть — используем его.
    func isEnabled(_ actionID: String) -> Bool {
        config.enabledFlags[actionID] ?? true
    }

    func setEnabled(_ enabled: Bool, for actionID: String) {
        config.enabledFlags[actionID] = enabled
    }

    // MARK: - Custom AI

    /// Перестраивает AI actions из текущего config.customAI.
    /// Удаляет старые user.* и регистрирует новые из descriptors.
    func rebuildCustomAI() {
        guard let provider = aiProvider else { return }
        actions.removeAll { $0.id.hasPrefix("user.") }
        for desc in config.customAI where desc.enabled {
            let types = Set(desc.applicableTypes)
            let action = AIAction(
                id: desc.id,
                title: desc.title,
                promptTemplate: desc.promptTemplate,
                provider: provider
            )
            // Note: applicability через CustomAIAction wrapper если нужно ограничивать типы.
            // В минимальной версии — AIAction всегда применим к plain text.
            _ = types  // reserved for future per-type filtering
            actions.append(action)
        }
    }

    /// Добавляет / обновляет custom AI descriptor.
    func upsertCustomAI(_ descriptor: CustomAIDescriptor) {
        var copy = config
        if let idx = copy.customAI.firstIndex(where: { $0.id == descriptor.id }) {
            copy.customAI[idx] = descriptor
        } else {
            copy.customAI.append(descriptor)
        }
        config = copy  // triggers save + rebuildCustomAI
    }

    func removeCustomAI(id: String) {
        var copy = config
        copy.customAI.removeAll { $0.id == id }
        config = copy
    }

    // MARK: - Export / Import

    /// Сериализует config в JSON для export. API keys в export НЕ включаются.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(config)
    }

    /// Импорт config: replace = заменяет полностью, merge = добавляет уникальное.
    enum ImportStrategy { case replace, merge }

    func importJSON(_ data: Data, strategy: ImportStrategy) -> Bool {
        guard let incoming = try? JSONDecoder().decode(ActionConfig.self, from: data) else {
            return false
        }
        switch strategy {
        case .replace:
            config = incoming
        case .merge:
            var copy = config
            for (k, v) in incoming.enabledFlags { copy.enabledFlags[k] = v }
            for desc in incoming.customAI where !copy.customAI.contains(where: { $0.id == desc.id }) {
                copy.customAI.append(desc)
            }
            config = copy
        }
        return true
    }
}
