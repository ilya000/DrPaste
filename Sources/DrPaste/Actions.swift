//
//  Actions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  ClipboardAction protocol + ApplyOutcome enum + base local actions.
//  Categorized actions live in FileActions.swift, URLActions.swift,
//  TextActions.swift, JSONActions.swift, TableActions.swift,
//  MarkdownActions.swift, CodeActions.swift, ImageActions.swift.
//

import Foundation

// MARK: - Outcome model

enum ApplyOutcome {
    /// Standard transformation — the HUD preview is refreshed; on commit the
    /// result is written to the pasteboard and pasted.
    case preview(ClipboardItem)
    /// Action could not run (missing AI key, malformed input, AX required).
    /// HUD shows the original plus an inline notice with the reason and an
    /// optional recovery action. On commit the original is written (paste-as-is).
    case failed(original: ClipboardItem, reason: String, recovery: RecoveryAction?)
    /// Side effect (Reveal in Finder, Open URL). On commit the closure runs
    /// and the HUD closes.
    case sideEffect(description: String, perform: () -> Void)
    /// Alternative commit (Type Slowly, and later typeFast). On commit the
    /// platform-specific simulator runs instead of ⌘V.
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
    /// Streaming variant — emits intermediate `.preview` updates through
    /// `onPartial` as content arrives, returning the final outcome at the
    /// end. Declared in the protocol so dynamic dispatch picks up
    /// `AIAction.applyStreaming` when called through a `ClipboardAction`
    /// existential. The extension below provides a default fallback to
    /// `apply()` for actions that don't override (every local transformation,
    /// every image action keep working unchanged).
    func applyStreaming(item: ClipboardItem,
                        context: ContentContext,
                        onPartial: @escaping @MainActor (ClipboardItem) -> Void)
        async -> ApplyOutcome
}

extension ClipboardAction {
    func applyStreaming(item: ClipboardItem,
                        context: ContentContext,
                        onPartial: @escaping @MainActor (ClipboardItem) -> Void)
        async -> ApplyOutcome
    {
        await apply(item: item, context: context)
    }
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
    // Empty representations cause PasteboardWriter to fall back to previewText
    // — this is a transformed item, the raw representations are stale.
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

// UppercaseAction / LowercaseAction / TrimWhitespaceAction migrated to
// DefaultTransformationSeed under the same `builtin.uppercase`,
// `builtin.lowercase`, `builtin.trim` IDs.

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

/// ActionRegistry holds the registered actions and their configuration:
/// enabledFlags for built-ins (keyed by action.id) and custom AI actions from
/// ActionConfig. applicable() filters by both context applicability and the
/// per-action enabled flag.
final class ActionRegistry: ObservableObject {

    @Published private(set) var actions: [ClipboardAction] = []
    @Published var config: ActionConfig = .load() {
        didSet {
            if oldValue != config {
                config.save()
                rebuildCustomAI()
                rebuildCustomTransformations()
                // Drop hotkeys whose action no longer exists (descriptor removed,
                // factory action renamed, action pack unloaded, etc.). Must run
                // after rebuilds so user.* actions reflect current config.
                pruneOrphanedActionHotkeys()
                // Reload hotkeys if the bound set OR any enabled-state changed —
                // disabling an action must unbind its hotkey even though
                // actionHotkeys itself did not change.
                if oldValue.actionHotkeys != config.actionHotkeys
                    || Self.enabledFingerprint(oldValue) != Self.enabledFingerprint(config) {
                    Task { @MainActor in ActionHotkeyManager.shared.reload() }
                }
            }
        }
    }

    /// Snapshot of every action's enabled state — used to detect toggling so
    /// `ActionHotkeyManager` can rebind / unbind direct-trigger hotkeys.
    private static func enabledFingerprint(_ cfg: ActionConfig) -> [String: Bool] {
        var m: [String: Bool] = [:]
        for d in cfg.customAI { m[d.id] = d.enabled }
        for d in cfg.customTransformations { m[d.id] = d.enabled }
        for (k, v) in cfg.enabledFlags { m[k] = v }
        return m
    }

    /// Deprecated: AIAction now resolves its provider through
    /// AIProviderRegistry.shared using the descriptor's providerID. This field
    /// remains for backward-compatible call sites.
    var aiProvider: AIProvider?

    init() {
        // Built-in core actions that cannot be expressed as transformation
        // descriptors (Identity is the pinned anchor; LayoutRepair needs the
        // Cyrillic keymap + spell-check scoring; CleanFormatting strips RTF).
        // Everything else lives in DefaultTransformationSeed.
        actions = [
            IdentityAction(),
            LayoutRepairAction(),
            CleanFormattingAction()
        ]
    }

    /// On first launch (or upgrade with new defaults), seed bundled AI and
    /// transformation actions into the config. Called by AppDelegate AFTER
    /// `init`, before the rebuild step, to avoid didSet side-effects on
    /// partially-initialized state.
    func runFirstLaunchSeeds() {
        var copy = config
        var changed = false

        if seedAI(into: &copy)             { changed = true }
        if seedTransformations(into: &copy) { changed = true }
        if rebrandFancyTextIfNeeded(into: &copy) { changed = true }

        if changed { config = copy }
    }

    /// One-shot migration that brings existing installs (which already have
    /// `builtin.font_*` descriptors seeded under the old "Font: <Style>"
    /// naming) onto the new stylized-letter title scheme, restricts them
    /// to .text only, and removes the regional-indicator entry. Runs once
    /// per install, gated by `seedTransformationVersion >= 3`. Skips any
    /// descriptor whose title the user has manually edited (anything not
    /// starting with "Font: ").
    private func rebrandFancyTextIfNeeded(into copy: inout ActionConfig) -> Bool {
        // Mapping from id → (old-default-title-prefix, new-title) for the
        // descriptors that need rebrand. The "old prefix" is checked so we
        // only overwrite titles still on the factory default.
        let oldTitles: [String: String] = [
            "builtin.font_bold":               "Font: Bold",
            "builtin.font_italic":             "Font: Italic",
            "builtin.font_bold_italic":        "Font: Bold Italic",
            "builtin.font_script":             "Font: Script",
            "builtin.font_bold_script":        "Font: Bold Script",
            "builtin.font_fraktur":            "Font: Fraktur",
            "builtin.font_bold_fraktur":       "Font: Bold Fraktur",
            "builtin.font_double_struck":      "Font: Double-struck",
            "builtin.font_sans":               "Font: Sans-serif",
            "builtin.font_sans_bold":          "Font: Sans-serif Bold",
            "builtin.font_sans_italic":        "Font: Sans-serif Italic",
            "builtin.font_sans_bold_italic":   "Font: Sans-serif Bold Italic",
            "builtin.font_monospace":          "Font: Monospace",
            "builtin.font_fullwidth":          "Font: Fullwidth",
            "builtin.font_small_caps":         "Font: Small Caps",
            "builtin.font_circled":            "Font: Circled",
            "builtin.font_filled_circled":     "Font: Filled Circled",
            "builtin.font_squared":            "Font: Squared",
            "builtin.font_filled_squared":     "Font: Filled Squared",
            "builtin.font_upside_down":        "Font: Upside Down",
            "builtin.font_plain":              "Font: Plain (strip styling)"
        ]
        // Look up new title + applicableTypes directly from the seed table
        // so we have a single source of truth.
        let newDefaults: [String: CustomTransformationDescriptor] = {
            var dict: [String: CustomTransformationDescriptor] = [:]
            for desc in DefaultTransformationSeed.defaults() {
                dict[desc.id] = desc
            }
            return dict
        }()

        var didChange = false
        // Drop the discontinued regional-indicator entry — readability of the
        // boxed-letter glyphs is too poor to keep as a curated default.
        if let idx = copy.customTransformations.firstIndex(where: { $0.id == "builtin.font_regional_indicator" }) {
            copy.customTransformations.remove(at: idx)
            copy.actionHotkeys.removeValue(forKey: "builtin.font_regional_indicator")
            didChange = true
        }
        for idx in copy.customTransformations.indices {
            let d = copy.customTransformations[idx]
            guard oldTitles[d.id] != nil, let new = newDefaults[d.id] else { continue }
            // Rebrand title only if the user hasn't edited it (still matches the
            // factory default for this version of the seed).
            if d.title == oldTitles[d.id] {
                copy.customTransformations[idx].title = new.title
                didChange = true
            }
            // Narrow applicableTypes from the legacy seeded set [text,
            // markdown, code] to [text] only — these decorative styles
            // don't belong in code / URLs / markdown. ONLY runs when the
            // descriptor still has the exact legacy set so that any user
            // customization (added or removed types after the migration)
            // is preserved across subsequent launches.
            let legacy: Set<String> = ["text", "markdown", "code"]
            let currentTypes = Set(copy.customTransformations[idx].applicableTypes)
            if currentTypes == legacy {
                copy.customTransformations[idx].applicableTypes = ["text"]
                didChange = true
            }
        }
        return didChange
    }

    /// Returns true if any AI seeds were appended or migrated.
    private func seedAI(into copy: inout ActionConfig) -> Bool {
        guard copy.seedAIVersion < DefaultAISeed.currentSeedVersion else { return false }

        // Migrate per-action hotkeys from old factory IDs to new seeded IDs.
        for (oldID, newID) in DefaultAISeed.hotkeyIDMigration {
            if let hk = copy.actionHotkeys[oldID] {
                copy.actionHotkeys[newID] = hk
                copy.actionHotkeys.removeValue(forKey: oldID)
            }
        }

        // Append defaults that are not already present.
        for desc in DefaultAISeed.defaults() {
            if !copy.customAI.contains(where: { $0.id == desc.id }) {
                copy.customAI.append(desc)
            }
        }

        // v2 migration: previously seeded entries had providerID hardcoded to
        // "anthropic". Reset to "" (follow default) for seeded user.* IDs whose
        // providerID still matches the original hardcoded value. User-customized
        // entries (manually changed to a different provider) are left alone.
        if copy.seedAIVersion < 2 {
            let seededIDs = Set(DefaultAISeed.defaults().map { $0.id })
            for idx in copy.customAI.indices {
                let entry = copy.customAI[idx]
                if seededIDs.contains(entry.id) && entry.providerID == "anthropic" {
                    copy.customAI[idx].providerID = ""
                }
            }
        }
        copy.seedAIVersion = DefaultAISeed.currentSeedVersion
        return true
    }

    /// Seeds bundled transformation defaults. Migrates pre-existing
    /// `enabledFlags[id]` and `customTitles[id]` into the descriptor so the
    /// switch from hardcoded `builtin.*` action structs to descriptors is
    /// invisible to users who had already customized those actions.
    private func seedTransformations(into copy: inout ActionConfig) -> Bool {
        guard copy.seedTransformationVersion < DefaultTransformationSeed.currentSeedVersion else { return false }

        for seedDesc in DefaultTransformationSeed.defaults() {
            // Skip if already present — preserves user edits across upgrades.
            guard !copy.customTransformations.contains(where: { $0.id == seedDesc.id }) else { continue }

            var d = seedDesc
            // Inherit the user's prior enabled flag for this ID, if any.
            if let flag = copy.enabledFlags[d.id] {
                d.enabled = flag
                copy.enabledFlags.removeValue(forKey: d.id)
            } else {
                d.enabled = CuratedDefaults.isEnabledByDefault(d.id)
            }
            // Inherit any prior custom title set via the legacy customTitles map.
            if let custom = copy.customTitles[d.id], !custom.isEmpty {
                d.title = custom
                copy.customTitles.removeValue(forKey: d.id)
            }
            copy.customTransformations.append(d)
        }
        copy.seedTransformationVersion = DefaultTransformationSeed.currentSeedVersion
        return true
    }

    func register(_ action: ClipboardAction) {
        actions.append(action)
    }

    func register<S: Sequence>(_ batch: S) where S.Element == ClipboardAction {
        actions.append(contentsOf: batch)
    }

    /// All actions filtered by the enabled flag.
    var allEnabled: [ClipboardAction] {
        actions.filter { isEnabled($0.id) }
    }

    func applicable(for item: ClipboardItem, context: ContentContext) -> [ClipboardAction] {
        let filtered = actions.filter { isEnabled($0.id) && $0.isApplicable(item: item, context: context) }
        return reorder(filtered, forContentType: item.semantic)
    }

    /// Applies the user-defined order for a given content type. Identity
    /// (Paste as is) is always first; the rest follow actionOrder. Actions
    /// without an entry in actionOrder appear after, in their original order.
    func reorder(_ list: [ClipboardAction], forContentType kind: SemanticKind) -> [ClipboardAction] {
        let savedOrder = config.actionOrder[kind.rawValue] ?? []
        guard !savedOrder.isEmpty else { return moveIdentityFirst(list) }
        var byID: [String: ClipboardAction] = [:]
        for a in list { byID[a.id] = a }
        var result: [ClipboardAction] = []
        for id in savedOrder {
            if let a = byID.removeValue(forKey: id) { result.append(a) }
        }
        // Append actions that were not in the saved order, preserving default order.
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

    /// Saves the user-defined action order for a content type. Identity is
    /// dropped from the array because it is always pinned first at render time.
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

    /// Unified enabled lookup across all action sources.
    /// - Custom AI / custom transformation descriptors carry their own `enabled` flag.
    /// - Built-in actions use `config.enabledFlags[id]` with curated-default fallback.
    func isEnabled(_ actionID: String) -> Bool {
        if let desc = config.customAI.first(where: { $0.id == actionID }) {
            return desc.enabled
        }
        if let desc = config.customTransformations.first(where: { $0.id == actionID }) {
            return desc.enabled
        }
        if let flag = config.enabledFlags[actionID] { return flag }
        return CuratedDefaults.isEnabledByDefault(actionID)
    }

    /// Unified enable/disable across all action sources.
    func setEnabled(_ enabled: Bool, for actionID: String) {
        var copy = config
        if let idx = copy.customAI.firstIndex(where: { $0.id == actionID }) {
            copy.customAI[idx].enabled = enabled
            config = copy
            return
        }
        if let idx = copy.customTransformations.firstIndex(where: { $0.id == actionID }) {
            copy.customTransformations[idx].enabled = enabled
            config = copy
            return
        }
        copy.enabledFlags[actionID] = enabled
        config = copy
    }

    /// Display title with custom override applied. Used by HUD action chips and
    /// by the Settings playground.
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

    /// Rebuilds AI actions from current config.customAI.
    /// Empty providerID means "use the default provider" — resolved dynamically at apply time
    /// by AIAction.resolveProvider() so changing the default in Settings instantly propagates
    /// to every default-bound action without re-saving anything.
    ///
    /// All descriptors are registered regardless of `enabled` so that disabled
    /// custom AI rows stay visible in the Settings list (parity with built-in
    /// actions, which never disappear when toggled off). Runtime filtering for
    /// disabled descriptors happens in `applicable(for:context:)` via
    /// `isEnabled(_:)`, and in `ActionHotkeyManager.reload` for direct triggers.
    func rebuildCustomAI() {
        // Drop all user.* entries (both AI and transformations). rebuildCustomTransformations
        // runs immediately after via didSet and re-adds the transformation actions.
        actions.removeAll { $0.id.hasPrefix("user.") }
        for desc in config.customAI {
            let kinds = Set(desc.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
            let resolvedProviderID: String? = desc.providerID.isEmpty ? nil : desc.providerID
            let action = AIAction(
                id: desc.id,
                title: desc.title,
                promptTemplate: desc.promptTemplate,
                providerID: resolvedProviderID,
                applicableTypes: kinds.isEmpty ? [.text, .richText, .markdown] : kinds
            )
            actions.append(action)
        }
    }

    /// Adds or updates a custom AI descriptor.
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

    // MARK: - Custom Transformations (lightweight engine architecture)

    /// Rebuilds custom transformation actions from `config.customTransformations`.
    /// All descriptors are registered regardless of `enabled` so the rows stay
    /// visible (greyed) when toggled off in Settings — runtime filtering is
    /// centralized in `isEnabled(_:)`. The filter now matches descriptor IDs
    /// instead of the `user.transform.*` prefix so bundled `builtin.*`
    /// transformations seeded via DefaultTransformationSeed also flow through.
    func rebuildCustomTransformations() {
        let descriptorIDs = Set(config.customTransformations.map { $0.id })
        actions.removeAll { descriptorIDs.contains($0.id) }
        for desc in config.customTransformations {
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

    /// Find the action id that currently holds this hotkey, if any. Used by the
    /// recorder UI to surface a non-blocking warning before stealing the binding.
    /// Orphan entries (id no longer in `actions`) are ignored — they will be
    /// garbage-collected on save and must not look like conflicts.
    func conflictingAction(for hotkey: ActionHotkey, excludingID: String? = nil) -> String? {
        let validIDs = Set(actions.map { $0.id })
        for (id, hk) in config.actionHotkeys
            where id != excludingID && hk == hotkey && validIDs.contains(id)
        {
            return id
        }
        return nil
    }

    /// Convenience: same as `conflictingAction(for:excludingID:)` but also returns
    /// the display title so the UI can show "Already used by '<Title>'".
    func conflictingActionInfo(for hotkey: ActionHotkey, excludingID: String? = nil)
        -> (id: String, title: String)?
    {
        guard let id = conflictingAction(for: hotkey, excludingID: excludingID) else {
            return nil
        }
        let defaultTitle = actions.first(where: { $0.id == id })?.title ?? id
        let title = displayTitle(forActionID: id, defaultTitle: defaultTitle)
        return (id, title)
    }

    /// Removes hotkey bindings whose action no longer exists in `actions`.
    /// Sources of orphans: deleted user.* descriptor, action pack removed/renamed
    /// between versions, factory ID migration that missed an entry. Without GC
    /// the orphan would persist in config.actionHotkeys and surface in the
    /// Welcome window's "Your custom action hotkeys" list as a dead row.
    ///
    /// Safe to call recursively from `config.didSet` — only writes back when at
    /// least one orphan was found, and a second pass finds nothing to prune.
    func pruneOrphanedActionHotkeys() {
        guard !config.actionHotkeys.isEmpty else { return }
        let validIDs = Set(actions.map { $0.id })
        let orphans = config.actionHotkeys.keys.filter { !validIDs.contains($0) }
        guard !orphans.isEmpty else { return }
        var copy = config
        for id in orphans {
            copy.actionHotkeys.removeValue(forKey: id)
        }
        config = copy
    }

    // MARK: - Factory reset

    /// Wipes every user-tunable state back to first-launch defaults:
    /// action config (enabled flags, custom AI, custom transformations, custom
    /// titles, ordering, per-action hotkeys, preferences), AI provider configs
    /// and their Keychain API keys, and the UserDefaults preference keys
    /// (font scale, cut-cursor toggle, welcome suppression).
    /// Reseeds the default AI actions so they appear in the rebuilt registry.
    /// Returns once everything is reloaded; caller may want to surface a "Done"
    /// status string to the UI.
    /// `@MainActor` because it touches `AIProviderRegistry.shared` (main-actor
    /// isolated). All callers are SwiftUI button actions, already on main.
    @MainActor
    func factoryReset() {
        // Wipe provider configs + Keychain keys.
        AIProviderRegistry.shared.factoryReset()
        // Clear every UserDefaults key DrPaste owns. Covers HUD scale, cut-cursor
        // toggle, welcome suppression, per-cue sound flags, and sound volume.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("drpaste.") {
            defaults.removeObject(forKey: key)
        }
        // Reset action config to a blank state, then reseed defaults.
        // Setting config triggers didSet → rebuilds + GC + persistence.
        config = ActionConfig()
        runFirstLaunchSeeds()
        // Rebuilds after seed already happen via didSet, but call explicitly to
        // be safe when seedAIVersion was already at currentSeedVersion (no-op seed).
        rebuildCustomAI()
        rebuildCustomTransformations()
        pruneOrphanedActionHotkeys()
        // Re-register hotkeys (all dropped above, this just clears the manager).
        Task { @MainActor in ActionHotkeyManager.shared.reload() }
    }

    // MARK: - Export / Import

    /// Serializes config to JSON for export. API keys are NOT included.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(config)
    }

    /// Imports config: .replace overwrites everything; .merge adds unique entries.
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
