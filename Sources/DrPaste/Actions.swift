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

final class ActionRegistry {
    private(set) var actions: [ClipboardAction]

    init() {
        // Built-in core actions.
        // Categorized actions из FileActions/URLActions/etc. регистрируются через register()
        // из AppDelegate после init().
        self.actions = [
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

    func applicable(for item: ClipboardItem, context: ContentContext) -> [ClipboardAction] {
        return actions.filter { $0.isApplicable(item: item, context: context) }
    }
}
