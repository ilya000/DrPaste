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
                rebuildCustomTransformations()
                // Re-register hotkey'и если изменились
                if oldValue.actionHotkeys != config.actionHotkeys {
                    Task { @MainActor in ActionHotkeyManager.shared.reload() }
                }
            }
        }
    }

    /// AI provider устарел — теперь AIAction резолвит provider через AIProviderRegistry.shared
    /// по providerID descriptor'а. Поле оставлено для backward compat call sites.
    var aiProvider: AIProvider?

    init() {
        // Built-in core actions. AppDelegate registers additional action packs.
        actions = [
            IdentityAction(),
            LayoutRepairAction(),
            CleanFormattingAction(),
            TrimWhitespaceAction(),
            UppercaseAction(),
            LowercaseAction()
        ]
    }

    /// #9: On first launch (or upgrade with new defaults), seed default AI actions
    /// into config.customAI as regular editable entries.
    /// MUST be called by AppDelegate AFTER init, before rebuildCustomAI().
    /// Not called from init() to avoid didSet side-effects on partially-initialized state.
    func runFirstLaunchSeeds() {
        guard config.seedAIVersion < DefaultAISeed.currentSeedVersion else { return }
        var copy = config

        // Migrate per-action hotkeys from old factory IDs to new seeded IDs.
        for (oldID, newID) in DefaultAISeed.hotkeyIDMigration {
            if let hk = copy.actionHotkeys[oldID] {
                copy.actionHotkeys[newID] = hk
                copy.actionHotkeys.removeValue(forKey: oldID)
            }
        }

        // Seed defaults that aren't already present (avoid duplicates on upgrade).
        for desc in DefaultAISeed.defaults() {
            if !copy.customAI.contains(where: { $0.id == desc.id }) {
                copy.customAI.append(desc)
            }
        }
        copy.seedAIVersion = DefaultAISeed.currentSeedVersion
        config = copy
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
        let filtered = actions.filter { isEnabled($0.id) && $0.isApplicable(item: item, context: context) }
        return reorder(filtered, forContentType: item.semantic)
    }

    /// Применяет пользовательский order для данного content type (правка #5).
    /// Identity (Paste as is) всегда первый. Остальное по actionOrder.
    /// Actions без entry в order идут после в исходном порядке.
    func reorder(_ list: [ClipboardAction], forContentType kind: SemanticKind) -> [ClipboardAction] {
        let savedOrder = config.actionOrder[kind.rawValue] ?? []
        guard !savedOrder.isEmpty else { return moveIdentityFirst(list) }
        var byID: [String: ClipboardAction] = [:]
        for a in list { byID[a.id] = a }
        var result: [ClipboardAction] = []
        for id in savedOrder {
            if let a = byID.removeValue(forKey: id) { result.append(a) }
        }
        // Оставшиеся — в default order
        for a in list where byID[a.id] != nil {
            result.append(a)
            byID.removeValue(forKey: a.id)
        }
        return moveIdentityFirst(result)
    }

    private func moveIdentityFirst(_ list: [ClipboardAction]) -> [ClipboardAction] {
        guard let idx = list.firstIndex(where: { $0.id == "builtin.identity" }), idx != 0 else {
            return list
        }
        var copy = list
        let identity = copy.remove(at: idx)
        copy.insert(identity, at: 0)
        return copy
    }

    /// Сохранить custom order для content type. Identity автоматически удаляется
    /// из массива — она всегда первая на render.
    func setActionOrder(_ ids: [String], for kind: SemanticKind) {
        var copy = config
        let filtered = ids.filter { $0 != "builtin.identity" }
        if filtered.isEmpty {
            copy.actionOrder.removeValue(forKey: kind.rawValue)
        } else {
            copy.actionOrder[kind.rawValue] = filtered
        }
        config = copy
    }

    /// Built-in default — enabled if action ID is in curated subset (правка #8 lite).
    /// Если в config флаг есть — используем его (пользовательский override).
    /// Иначе — bundled default из CuratedDefaults.
    func isEnabled(_ actionID: String) -> Bool {
        if let flag = config.enabledFlags[actionID] { return flag }
        return CuratedDefaults.isEnabledByDefault(actionID)
    }

    func setEnabled(_ enabled: Bool, for actionID: String) {
        config.enabledFlags[actionID] = enabled
    }

    /// Display title с учётом custom override (правка #6 lite).
    /// Используется в HUD action chips и в Settings playground.
    func displayTitle(forActionID actionID: String, defaultTitle: String) -> String {
        config.customTitles[actionID] ?? defaultTitle
    }

    func setCustomTitle(_ title: String?, forActionID actionID: String) {
        var copy = config
        if let title = title, !title.isEmpty {
            copy.customTitles[actionID] = title
        } else {
            copy.customTitles.removeValue(forKey: actionID)
        }
        config = copy
    }

    // MARK: - Custom AI

    /// Перестраивает AI actions из текущего config.customAI.
    /// Удаляет старые user.* и регистрирует новые из descriptors.
    /// Provider резолвится через AIProviderRegistry.shared по descriptor.providerID.
    func rebuildCustomAI() {
        actions.removeAll { $0.id.hasPrefix("user.") }
        for desc in config.customAI where desc.enabled {
            let kinds = Set(desc.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
            let action = AIAction(
                id: desc.id,
                title: desc.title,
                promptTemplate: desc.promptTemplate,
                providerID: desc.providerID,
                applicableTypes: kinds.isEmpty ? [.text, .richText, .markdown] : kinds
            )
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

    // MARK: - Custom Transformations (правка #7 light — engine architecture)

    /// Перестраивает custom transformation actions из config.customTransformations.
    /// Удаляет старые user.transform.* и регистрирует новые из descriptors.
    func rebuildCustomTransformations() {
        actions.removeAll { $0.id.hasPrefix("user.transform.") }
        for desc in config.customTransformations where desc.enabled {
            let kinds = Set(desc.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
            let action = CustomTransformationAction(
                id: desc.id,
                title: desc.title,
                descriptor: desc,
                applicableSet: kinds.isEmpty ? [.text, .richText, .markdown, .code] : kinds
            )
            actions.append(action)
        }
    }

    func upsertCustomTransformation(_ descriptor: CustomTransformationDescriptor) {
        var copy = config
        if let idx = copy.customTransformations.firstIndex(where: { $0.id == descriptor.id }) {
            copy.customTransformations[idx] = descriptor
        } else {
            copy.customTransformations.append(descriptor)
        }
        config = copy
    }

    func removeCustomTransformation(id: String) {
        var copy = config
        copy.customTransformations.removeAll { $0.id == id }
        config = copy
    }

    // MARK: - Per-action hotkeys (0.6.0)

    func hotkey(for actionID: String) -> ActionHotkey? {
        config.actionHotkeys[actionID]
    }

    func setHotkey(_ hotkey: ActionHotkey?, for actionID: String) {
        var copy = config
        if let hotkey = hotkey {
            copy.actionHotkeys[actionID] = hotkey
        } else {
            copy.actionHotkeys.removeValue(forKey: actionID)
        }
        config = copy
    }

    /// Найти actionID который уже использует данный hotkey (для conflict UI).
    func conflictingAction(for hotkey: ActionHotkey, excludingID: String? = nil) -> String? {
        for (id, hk) in config.actionHotkeys where id != excludingID && hk == hotkey {
            return id
        }
        return nil
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
