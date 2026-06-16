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
import AppKit

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

    /// Type-level applicability, IGNORING runtime "Show this action when…"
    /// trait conditions. The Settings management list uses this so a trait-gated
    /// action stays visible and editable regardless of whether the current
    /// sample happens to match its condition — otherwise adding a condition
    /// makes the action vanish from Settings and become unfindable. Defaults to
    /// full `isApplicable` (correct for standalone built-ins, which carry no
    /// trait gate); descriptor-backed actions override it to drop only the gate.
    func appliesToContentType(item: ClipboardItem, context: ContentContext) -> Bool {
        isApplicable(item: item, context: context)
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

// CleanFormattingAction merged with PasteAsTextAction in 0.56.0 (#A74)
// into single `builtin.rich.strip_formatting` (MoreActions.swift).
// Both old IDs migrate to the unified new ID via IDMigration056.

// UppercaseAction / LowercaseAction / TrimWhitespaceAction migrated to
// DefaultTransformationSeed under the new convention v2 IDs
// (builtin.text.uppercase / .lowercase / .trim).

// MARK: - Layout repair

struct LayoutRepairAction: ClipboardAction {
    let id = "builtin.text.layout_repair"
    let title = "Fix layout"
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

    /// #A46 (0.57.0) — debounced `actions.json` writer. Settings
    /// thrash (toggle a checkbox, drag a row, edit a hotkey) used
    /// to rewrite the pretty-printed JSON synchronously on every
    /// change; now the last edit in a 200 ms window wins and the
    /// disk hit moves off-main. The other side-effects in
    /// `config.didSet` (rebuilds, hotkey reload) run immediately —
    /// they are pure in-memory operations and the user wants them
    /// instant.
    private let configSaver = PersistenceDebouncer(label: "ActionConfig")

    @Published var config: ActionConfig = .load() {
        didSet {
            if oldValue != config {
                let snapshot = config
                configSaver.schedule {
                    snapshot.save()
                }
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
                    Task { @MainActor in
                        ActionHotkeyManager.shared.reload()
                        // #A10: re-push the ⌥⌘<letter> map to the EventTap
                        // engine so hold-preview routes the same hotkey set
                        // that the Carbon side just re-registered.
                        if let app = NSApp {
                            (app.delegate as? AppDelegate)?.reloadHoldPreviewMap()
                        }
                    }
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
            LayoutRepairAction()
            // CleanFormattingAction merged with PasteAsTextAction in 0.56.0;
            // single `builtin.rich.strip_formatting` lives in MoreActions.swift.
        ]
    }

    /// On first launch (or upgrade with new defaults), seed bundled AI and
    /// transformation actions into the config. Called by AppDelegate AFTER
    /// `init`, before the rebuild step, to avoid didSet side-effects on
    /// partially-initialized state.
    func runFirstLaunchSeeds() {
        var copy = config
        var changed = false

        // #A74 (0.56.0) — Pre-distribution ID consolidation. Runs
        // BEFORE every other migration / seed step so all downstream
        // logic operates on the new naming convention. Single-shot
        // guarded by `seedTransformationVersion < 9`.
        if copy.seedTransformationVersion < 9 {
            let rewrites = IDMigration056.apply(to: &copy)
            if rewrites > 0 {
                NSLog("DrPaste: #A74 ID migration to 0.56.0 — rewrote \(rewrites) entries")
                changed = true
            }
        }

        // The pre-v2 one-shot migrations (remapLegacyActionIDs,
        // rebrandFancyTextIfNeeded, expandMarkdownExtractTypesIfNeeded,
        // renameCyrillicActionsIfNeeded) were retired in 0.56.0: IDMigration056
        // above now rewrites every legacy ID to the v2 convention in a single
        // pass, so those chained renames are dead. Removed pre-distribution
        // (#A74 clean slate — no shipped users to migrate through the old chain).
        if seedAI(into: &copy)             { changed = true }
        if seedTransformations(into: &copy) { changed = true }
        if applyBuiltinTraitGatesIfNeeded(into: &copy) { changed = true }
        if applyApplicabilityCurationIfNeeded(into: &copy) { changed = true }
        if applyAICodeApplicabilityIfNeeded(into: &copy) { changed = true }
        if applyAITitleCleanupIfNeeded(into: &copy) { changed = true }
        if applyTraitKeyCleanupIfNeeded(into: &copy) { changed = true }
        if applyDeclutterV2IfNeeded(into: &copy) { changed = true }
        if applyDeclutterV3IfNeeded(into: &copy) { changed = true }
        if applyTranslateConsolidationIfNeeded(into: &copy) { changed = true }
        if applyDeclutterV4IfNeeded(into: &copy) { changed = true }
        if applyDeclutterV5IfNeeded(into: &copy) { changed = true }
        if applyDeclutterV6IfNeeded(into: &copy) { changed = true }
        if applyAICurationIfNeeded(into: &copy) { changed = true }
        if applyStripTagsGateIfNeeded(into: &copy) { changed = true }
        if applyZalgoLightDefaultIfNeeded(into: &copy) { changed = true }
        if applyTidyTextExpansionIfNeeded(into: &copy) { changed = true }
        if applyContextGatesIfNeeded(into: &copy) { changed = true }
        if applyRemoveRetiredStandalonesIfNeeded(into: &copy) { changed = true }
        if applyA78CurationIfNeeded(into: &copy) { changed = true }
        if applyA78CurationV2IfNeeded(into: &copy) { changed = true }
        if applyCuratedOrderResetIfNeeded(into: &copy) { changed = true }
        if applyWowSetEnableIfNeeded(into: &copy) { changed = true }
        if applyRetireFontPlainIfNeeded(into: &copy) { changed = true }
        if applyFontMarkdownMdOnlyIfNeeded(into: &copy) { changed = true }

        if changed { config = copy }
    }

    /// One-shot: scope "**md** → 𝐦𝐝" (`builtin.text.font_markdown`) to Markdown
    /// only on existing configs — parsing **bold** / *italic* markup belongs to
    /// Markdown clips, not arbitrary plain text.
    private func applyFontMarkdownMdOnlyIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.fontMarkdownMdOnly.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        for idx in copy.customTransformations.indices
        where copy.customTransformations[idx].id == "builtin.text.font_markdown"
            // Only migrate the EXACT old shipped set — never stomp a user who
            // deliberately changed the "Applies to" of this action (#A41/#A76).
            && copy.customTransformations[idx].applicableTypes == ["text", "markdown"] {
            copy.customTransformations[idx].applicableTypes = ["markdown"]
            changed = true
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: remove the retired "𝒜 → ABC  Plain ASCII"
    /// (`builtin.text.font_plain`) from existing configs. It is fully redundant
    /// with "Plain text" (`builtin.rich.strip_formatting`), which already folds
    /// styled Unicode → ASCII for every clip kind. Create-Unicode actions
    /// (Bold / Italic / … + Unicode Fancy) stay — they're already `fromChat`-
    /// gated for chat/social use.
    private func applyRetireFontPlainIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.retireFontPlain.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        let before = copy.customTransformations.count
        copy.customTransformations.removeAll { $0.id == "builtin.text.font_plain" }
        copy.enabledFlags.removeValue(forKey: "builtin.text.font_plain")
        copy.actionHotkeys.removeValue(forKey: "builtin.text.font_plain")
        UserDefaults.standard.set(true, forKey: key)
        return copy.customTransformations.count != before
    }

    /// One-shot: force-ENABLE the "wow / first-open" marketing set on existing
    /// configs, even if an earlier declutter migration had turned some off.
    /// All five are already in `CuratedDefaults.enabledByDefault` (new installs
    /// get them on); this fixes EXISTING configs where the stored
    /// `enabledFlags` / descriptor `enabled` says otherwise. Covers all three
    /// storage paths (custom AI descriptor, custom transformation descriptor,
    /// standalone built-in `enabledFlags`). Owner decision — force on everyone.
    private func applyWowSetEnableIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.wowSetEnable.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        let wow: Set<String> = [
            "builtin.url.preview_card",
            "builtin.text.generate_qr",
            "builtin.image.ocr",
            "builtin.files.to_rich_icons",
            "ai.text.image_whiteboard",
        ]
        var changed = false
        for idx in copy.customAI.indices
        where wow.contains(copy.customAI[idx].id) && !copy.customAI[idx].enabled {
            copy.customAI[idx].enabled = true; changed = true
        }
        for idx in copy.customTransformations.indices
        where wow.contains(copy.customTransformations[idx].id) && !copy.customTransformations[idx].enabled {
            copy.customTransformations[idx].enabled = true; changed = true
        }
        // Standalone built-ins (not descriptor-backed) read `enabledFlags`.
        let descriptorIDs = Set(copy.customAI.map { $0.id })
            .union(copy.customTransformations.map { $0.id })
        for id in wow where !descriptorIDs.contains(id) && copy.enabledFlags[id] != true {
            copy.enabledFlags[id] = true; changed = true
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot, RE-FORCEABLE reset (deliberately NOT a preserve-edits
    /// migration): discard ANY saved per-kind action order so the curated
    /// default order (`CuratedActionOrder`) applies to every user — including
    /// those who had hand-ordered. Owner decision: the new order is forced on
    /// everyone, customizations are dropped. Bump `version` whenever the
    /// curated order is re-tuned to push the fresh order out to everyone again.
    private func applyCuratedOrderResetIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.curatedOrder.resetVersion"
        let version = 2   // bump when re-tuning CuratedActionOrder to re-force everyone
        guard UserDefaults.standard.integer(forKey: key) < version else { return false }
        let changed = !copy.actionOrder.isEmpty
        copy.actionOrder.removeAll()
        UserDefaults.standard.set(version, forKey: key)
        return changed
    }

    /// One-shot: sharpen the HUD by context-gating broad utilities — they now
    /// surface only when relevant. Tidy text → messy/wrapped; case fixers →
    /// uppercase/lowercase-heavy; Sort/Unique → multiline; Clean URL → has
    /// tracking params; fancy fonts + UwU → chat/social source. Stamps the
    /// requiredTraits onto existing descriptors once.
    /// One-shot (#A77): fully REMOVE retired standalone actions from existing
    /// configs, so they no longer clutter the Settings list:
    ///   • Normalize spaces / Collapse blank lines — covered by "Tidy text".
    ///   • Markdown → plain — covered by "Plain text" (runs mdToPlain itself).
    /// Their hotkeys (if any) are pruned by `pruneOrphanedActionHotkeys`.
    private func applyRemoveRetiredStandalonesIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.removeRetiredStandalones.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        let remove: Set<String> = [
            "builtin.text.normalize_spaces",
            "builtin.text.collapse_blank_lines",
            "builtin.md.to_plain"
        ]
        let before = copy.customTransformations.count
        copy.customTransformations.removeAll { remove.contains($0.id) }
        var changed = copy.customTransformations.count != before

        // #A77 — strip the now-invalid `richText` "Applies to" from
        // remove_line_breaks so the editor checkbox matches reality (the
        // richTextDenylist already blocks it at runtime).
        for idx in copy.customTransformations.indices
        where copy.customTransformations[idx].id == "builtin.text.remove_line_breaks"
            && copy.customTransformations[idx].applicableTypes.contains("richText") {
            copy.customTransformations[idx].applicableTypes.removeAll { $0 == "richText" }
            changed = true
        }

        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot (#A78): curate down the default plain-text action strip on
    /// EXISTING configs (new installs get these via seeds / CuratedDefaults).
    ///   • Trait-gate UPPER/lower (uppercaseHeavy/lowercaseHeavy) and Zalgo
    ///     (fromChat) so they surface only in context.
    ///   • Drop plain text from Wrap “smart quotes” / Wrap in code block — keep
    ///     them on code / markdown.
    ///   • Disable Word/char count and Latin→Cyrillic translit.
    ///   • Disable the AI rewrites Make shorter / Improve clarity (tight AI core
    ///     stays: Fix grammar / Translate / Summarize).
    /// User edits made AFTER this one-shot are never touched (guarded by key).
    private func applyA78CurationIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.a78Curation.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false

        let gates: [String: [String]] = [
            "builtin.text.uppercase": ["uppercaseHeavy", "lowercaseHeavy"],
            "builtin.text.lowercase": ["uppercaseHeavy", "lowercaseHeavy"],
            "builtin.text.zalgo": ["fromChat"]
        ]
        let retypes: [String: [String]] = [
            "builtin.text.wrap_quotes": ["code", "markdown"],
            "builtin.code.wrap_block": ["code", "markdown"]
        ]
        let disableTransforms: Set<String> = [
            "builtin.text.word_count",
            "builtin.text.latin_to_cyrillic"
        ]
        for idx in copy.customTransformations.indices {
            let id = copy.customTransformations[idx].id
            if let want = gates[id], copy.customTransformations[idx].requiredTraits != want {
                copy.customTransformations[idx].requiredTraits = want
                changed = true
            }
            if let want = retypes[id], copy.customTransformations[idx].applicableTypes != want {
                copy.customTransformations[idx].applicableTypes = want
                changed = true
            }
            if disableTransforms.contains(id), copy.customTransformations[idx].enabled {
                copy.customTransformations[idx].enabled = false
                changed = true
            }
        }

        let disableAI: Set<String> = ["ai.text.make_shorter", "ai.text.improve_clarity"]
        for idx in copy.customAI.indices
        where disableAI.contains(copy.customAI[idx].id) && copy.customAI[idx].enabled {
            copy.customAI[idx].enabled = false
            changed = true
        }

        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot (#A78, per-type pass): narrow actions that leaked into content
    /// types where they're nonsense, on EXISTING configs.
    ///   • URL encode / decode — drop `.code` (keep text + url).
    ///   • Validate JSON — `.json` only.
    ///   • Wrap “smart quotes” — `.markdown` only (curly quotes break code).
    ///   • Wrap in code block — `.code` only.
    private func applyA78CurationV2IfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.a78Curation.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        let retypes: [String: [String]] = [
            "builtin.url.encode": ["text", "url"],
            "builtin.url.decode": ["text", "url"],
            "builtin.json.validate": ["json"],
            "builtin.text.wrap_quotes": ["markdown"],
            "builtin.code.wrap_block": ["code"]
        ]
        var changed = false
        for idx in copy.customTransformations.indices {
            if let want = retypes[copy.customTransformations[idx].id],
               copy.customTransformations[idx].applicableTypes != want {
                copy.customTransformations[idx].applicableTypes = want
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    private func applyContextGatesIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.contextGates.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        let gates: [String: [String]] = [
            "builtin.text.trim": ["messySpacing", "wrappedLines"],
            "builtin.text.title_case": ["uppercaseHeavy", "lowercaseHeavy"],
            "builtin.text.sentence_case": ["uppercaseHeavy", "lowercaseHeavy"],
            "builtin.text.sort_lines": ["multiline"],
            "builtin.text.unique_lines": ["multiline"],
            "builtin.url.strip_tracking": ["hasTrackingParams"],
            "builtin.text.uwu_speak": ["fromChat"]
        ]
        for idx in copy.customTransformations.indices {
            let id = copy.customTransformations[idx].id
            let want: [String]?
            if let g = gates[id] {
                want = g
            } else if id.hasPrefix("builtin.text.font_"),
                      id != "builtin.text.font_markdown", id != "builtin.text.font_plain" {
                want = ["fromChat"]
            } else {
                want = nil
            }
            if let want, copy.customTransformations[idx].requiredTraits != want {
                copy.customTransformations[idx].requiredTraits = want
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: "Tidy text" is a core cleanup — make it apply to text /
    /// markdown / rich text and turn it ON. (Still off code/JSON/table, where
    /// normalising spacing would break structure.)
    private func applyTidyTextExpansionIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.tidyTextExpansion.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        let want = ["text", "markdown", "richText"]
        for idx in copy.customTransformations.indices
        where copy.customTransformations[idx].id == "builtin.text.trim" {
            if copy.customTransformations[idx].applicableTypes != want {
                copy.customTransformations[idx].applicableTypes = want
                changed = true
            }
            if !copy.customTransformations[idx].enabled {
                copy.customTransformations[idx].enabled = true
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: lower Zalgo's default intensity from medium → light (minimum).
    /// Only the un-customised default ("medium") is touched.
    private func applyZalgoLightDefaultIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.zalgoLight.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        for idx in copy.customTransformations.indices
        where copy.customTransformations[idx].id == "builtin.text.zalgo"
            && copy.customTransformations[idx].parameters["intensity"] == "medium" {
            copy.customTransformations[idx].parameters["intensity"] = "light"
            changed = true
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: gate "Strip HTML tags" on the `containsHTMLMarkup` trait so it
    /// only surfaces when the clip actually contains HTML — never mangling
    /// `5 < 10`, `List<String>`, or other angle-bracket prose/code.
    private func applyStripTagsGateIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.stripTagsGate.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        for idx in copy.customTransformations.indices
        where copy.customTransformations[idx].id == "builtin.html.strip_tags"
            && copy.customTransformations[idx].requiredTraits != ["containsHTMLMarkup"] {
            copy.customTransformations[idx].requiredTraits = ["containsHTMLMarkup"]
            changed = true
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: curate AI defaults — switch off the novelty / niche AI seeds
    /// (IPA, image styles, Latin→Cyrillic, target-needing code translate, the
    /// AI Pretty Code that the local one covers) and also drop the Tidy-text
    /// `.code` scope (Pretty Code handles code). Runs once.
    private func applyAICurationIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.aiCuration.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        for idx in copy.customAI.indices
        where CuratedDefaults.aiOffByDefault.contains(copy.customAI[idx].id)
            && copy.customAI[idx].enabled {
            copy.customAI[idx].enabled = false
            changed = true
        }
        for idx in copy.customTransformations.indices
        where copy.customTransformations[idx].id == "builtin.text.trim"
            && copy.customTransformations[idx].applicableTypes.contains("code") {
            copy.customTransformations[idx].applicableTypes.removeAll { $0 == "code" }
            changed = true
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot declutter round 6 (full audit): retire the duplicate
    /// `resize_max_1920` (the universal Resize covers it — migrate its hotkey),
    /// and fix content-type scope where an action would mangle / no-op:
    /// UPPER/lower off Code, Strip HTML tags off rich text, Summarize off Code.
    private func applyDeclutterV6IfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.declutter.v6"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false

        if let hk = copy.actionHotkeys["builtin.image.resize_max_1920"] {
            if copy.actionHotkeys["builtin.image.resize"] == nil {
                copy.actionHotkeys["builtin.image.resize"] = hk
            }
            copy.actionHotkeys.removeValue(forKey: "builtin.image.resize_max_1920")
            changed = true
        }

        let newTypes: [String: [String]] = [
            "builtin.text.uppercase":  ["text", "markdown"],
            "builtin.text.lowercase":  ["text", "markdown"],
            "builtin.html.strip_tags": ["text", "code"]
        ]
        for idx in copy.customTransformations.indices {
            if let t = newTypes[copy.customTransformations[idx].id],
               Set(copy.customTransformations[idx].applicableTypes) != Set(t) {
                copy.customTransformations[idx].applicableTypes = t
                changed = true
            }
        }
        for idx in copy.customAI.indices
        where copy.customAI[idx].id == "ai.text.summarize"
            && copy.customAI[idx].applicableTypes.contains("code") {
            copy.customAI[idx].applicableTypes.removeAll { $0 == "code" }
            changed = true
        }

        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot declutter round 5: Extract headings also works on rich text;
    /// the duplicate `md.extract_links` and the merged `font_markdown` (now
    /// covered by Unicode Fancy) are switched off, leaving the universal
    /// "Extract links" on. Runs once; user edits are preserved otherwise.
    private func applyDeclutterV5IfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.declutter.v5"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        for idx in copy.customTransformations.indices {
            let id = copy.customTransformations[idx].id
            if id == "builtin.md.extract_headings",
               Set(copy.customTransformations[idx].applicableTypes) != ["markdown", "richText"] {
                copy.customTransformations[idx].applicableTypes = ["markdown", "richText"]
                changed = true
            }
            if (id == "builtin.md.extract_links" || id == "builtin.text.font_markdown"),
               copy.customTransformations[idx].enabled {
                copy.customTransformations[idx].enabled = false
                changed = true
            }
            if id == "builtin.text.extract_links", !copy.customTransformations[idx].enabled {
                copy.customTransformations[idx].enabled = true
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot declutter round 4: Pretty Code (local) covers Code + JSON
    /// (never prose / rich text), and the dedicated Pretty JSON — which produced
    /// byte-identical output — is switched off as redundant. Runs once; user
    /// "Applies to" / enabled edits are preserved.
    private func applyDeclutterV4IfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.declutter.v4"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        for idx in copy.customTransformations.indices {
            let id = copy.customTransformations[idx].id
            if id == "builtin.code.pretty_local",
               Set(copy.customTransformations[idx].applicableTypes) != ["code", "json"] {
                copy.customTransformations[idx].applicableTypes = ["code", "json"]
                changed = true
            }
            if id == "builtin.json.pretty", copy.customTransformations[idx].enabled {
                copy.customTransformations[idx].enabled = false
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: collapse the redundant Translate/Fix-grammar "(rich)" duplicates
    /// into a single action each that preserves Rich / Markdown formatting
    /// automatically. The duplicates had identical prompts and never actually
    /// preserved anything (the flag was never wired). Any hotkey on a duplicate
    /// is migrated onto the surviving action.
    private func applyTranslateConsolidationIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.translateConsolidation.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false

        let preserveIDs: Set<String> = ["ai.text.translate", "ai.text.fix_grammar"]
        for idx in copy.customAI.indices where preserveIDs.contains(copy.customAI[idx].id) {
            if !copy.customAI[idx].preserveRichFormatting {
                copy.customAI[idx].preserveRichFormatting = true
                changed = true
            }
            if !copy.customAI[idx].applicableTypes.contains("markdown") {
                copy.customAI[idx].applicableTypes.append("markdown")
                changed = true
            }
        }

        let dupToParent = [
            "ai.rich.translate": "ai.text.translate",
            "ai.rich.fix_grammar": "ai.text.fix_grammar"
        ]
        for (dup, parent) in dupToParent where copy.customAI.contains(where: { $0.id == dup }) {
            if let hk = copy.actionHotkeys[dup], copy.actionHotkeys[parent] == nil {
                copy.actionHotkeys[parent] = hk
            }
            copy.actionHotkeys.removeValue(forKey: dup)
            copy.customAI.removeAll { $0.id == dup }
            changed = true
        }

        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot declutter round 3: scope the HTML/JSON dev actions to where they
    /// make sense — Escape/Unescape HTML to Code only, Validate JSON to JSON +
    /// Code (not plain text). Runs once; user "Applies to" edits are preserved.
    private func applyDeclutterV3IfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.declutter.v3"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        let newTypes: [String: [String]] = [
            "builtin.html.escape":   ["code"],
            "builtin.html.unescape": ["code"],
            "builtin.json.validate": ["json", "code"]
        ]
        for idx in copy.customTransformations.indices {
            if let types = newTypes[copy.customTransformations[idx].id],
               copy.customTransformations[idx].applicableTypes != types {
                copy.customTransformations[idx].applicableTypes = types
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot declutter round 2: fold the whitespace family into the single
    /// "Tidy text" action, turn off the niche/redundant actions, and let the
    /// email actions also surface on a mail-app source (not just on a literal
    /// address in the text). Runs once; later user edits are never undone.
    private func applyDeclutterV2IfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.declutter.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false

        // Rename Trim → Tidy text (only the un-customised default).
        for idx in copy.customTransformations.indices
        where copy.customTransformations[idx].id == "builtin.text.trim"
            && copy.customTransformations[idx].title == "Trim whitespace" {
            copy.customTransformations[idx].title = "Tidy text"
            changed = true
        }

        // Turn off the merged / niche transformations.
        let disable: Set<String> = [
            "builtin.text.sort_lines", "builtin.text.remove_line_breaks",
            "builtin.text.normalize_spaces", "builtin.text.collapse_blank_lines",
            "builtin.code.tabs_to_spaces", "builtin.code.spaces_to_tabs"
        ]
        for idx in copy.customTransformations.indices
        where disable.contains(copy.customTransformations[idx].id)
            && copy.customTransformations[idx].enabled {
            copy.customTransformations[idx].enabled = false
            changed = true
        }

        // Email actions also fire on a mail-app source.
        let emailIDs: Set<String> = ["ai.text.draft_email_reply", "ai.text.generate_email_subject"]
        for idx in copy.customAI.indices where emailIDs.contains(copy.customAI[idx].id) {
            var req = copy.customAI[idx].requiredTraits
            if req.contains("containsEmails") && !req.contains("fromMailApp") {
                req.append("fromMailApp")
                copy.customAI[idx].requiredTraits = req
                changed = true
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: drop trait keys no longer in the vocabulary (e.g. the retired
    /// "emailLike") from every descriptor's required/forbidden lists. A stale
    /// key was harmless at runtime (the filter ignores unknowns) but it made an
    /// action read as "has a condition" (yellow checkbox) while showing nothing
    /// checked in the editor — confusing. Cleaning it restores agreement.
    private func applyTraitKeyCleanupIfNeeded(into copy: inout ActionConfig) -> Bool {
        let knownKey = "drpaste.migration.traitKeyCleanup.v1"
        guard !UserDefaults.standard.bool(forKey: knownKey) else { return false }
        let known = Set(ActionTrait.all.map { $0.key })
        var changed = false
        func clean(_ keys: [String]) -> [String] { keys.filter { known.contains($0) } }
        for idx in copy.customAI.indices {
            let r = clean(copy.customAI[idx].requiredTraits)
            let f = clean(copy.customAI[idx].forbiddenTraits)
            if r != copy.customAI[idx].requiredTraits { copy.customAI[idx].requiredTraits = r; changed = true }
            if f != copy.customAI[idx].forbiddenTraits { copy.customAI[idx].forbiddenTraits = f; changed = true }
        }
        for idx in copy.customTransformations.indices {
            let r = clean(copy.customTransformations[idx].requiredTraits)
            let f = clean(copy.customTransformations[idx].forbiddenTraits)
            if r != copy.customTransformations[idx].requiredTraits { copy.customTransformations[idx].requiredTraits = r; changed = true }
            if f != copy.customTransformations[idx].forbiddenTraits { copy.customTransformations[idx].forbiddenTraits = f; changed = true }
        }
        UserDefaults.standard.set(true, forKey: knownKey)
        return changed
    }

    /// One-shot: drop the inconsistent "AI: " title prefix from the seeded AI
    /// actions (some had it, some didn't — the blue AI badge already marks
    /// them, so the prefix is redundant). Only renames entries still carrying
    /// the exact default "AI: <title>" — user-renamed titles are left alone.
    private func applyAITitleCleanupIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.aiTitleCleanup.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        let seedTitles = Dictionary(uniqueKeysWithValues:
            DefaultAISeed.defaults().map { ($0.id, $0.title) })
        for idx in copy.customAI.indices {
            guard let newTitle = seedTitles[copy.customAI[idx].id] else { continue }
            if copy.customAI[idx].title == "AI: " + newTitle {
                copy.customAI[idx].title = newTitle
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot: restrict the code-specific AI actions (explain / find bugs /
    /// pretty-format) to Code clips only. They used to also surface on plain
    /// text, where they're noise — the semantic classifier already detects code
    /// by formal signals, so Code-only keeps the HUD focused. Runs once; later
    /// user edits to the "Applies to" set are never overwritten.
    private func applyAICodeApplicabilityIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.aiCodeApplicability.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false
        let codeOnly: Set<String> = [
            "ai.code.explain", "ai.code.find_bugs", "ai.code.pretty", "ai.code.translate"
        ]
        let codeTypes = ["code"]
        for idx in copy.customAI.indices where codeOnly.contains(copy.customAI[idx].id) {
            if copy.customAI[idx].applicableTypes != codeTypes {
                copy.customAI[idx].applicableTypes = codeTypes
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// One-shot declutter pass (UserDefaults-guarded) that aligns an existing
    /// config with the curated defaults: Markdown extractors become
    /// Markdown-only, and the redundant / long-tail actions (a dedicated
    /// Unicode-"plain" reverse, Markdown→plain now that the universal cleaner
    /// covers it, and the rarely-used fancy-font variants) are switched off so
    /// the HUD surfaces only the genuinely useful set. Runs once — later user
    /// edits (including deliberately re-enabling any of these) are never undone.
    private func applyApplicabilityCurationIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.applicabilityCuration.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        var changed = false

        let markdownOnly: Set<String> = [
            "builtin.md.extract_headings", "builtin.md.extract_links"
        ]
        let mdTypes = [SemanticKind.markdown.rawValue]
        for idx in copy.customTransformations.indices
        where markdownOnly.contains(copy.customTransformations[idx].id) {
            if copy.customTransformations[idx].applicableTypes != mdTypes {
                copy.customTransformations[idx].applicableTypes = mdTypes
                changed = true
            }
        }

        let disableByDefault: Set<String> = [
            "builtin.text.font_plain", "builtin.md.to_plain",
            "builtin.text.font_bold_script", "builtin.text.font_fraktur",
            "builtin.text.font_bold_fraktur", "builtin.text.font_double_struck",
            "builtin.text.font_sans", "builtin.text.font_sans_bold",
            "builtin.text.font_sans_italic", "builtin.text.font_sans_bold_italic",
            "builtin.text.font_fullwidth", "builtin.text.font_circled",
            "builtin.text.font_filled_circled", "builtin.text.font_squared",
            "builtin.text.font_filled_squared", "builtin.text.font_upside_down"
        ]
        for idx in copy.customTransformations.indices
        where disableByDefault.contains(copy.customTransformations[idx].id) {
            if copy.customTransformations[idx].enabled {
                copy.customTransformations[idx].enabled = false
                changed = true
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        return changed
    }

    /// #A75 — one-shot stamp of the built-in "Show this action when…"
    /// conditions onto an existing config. `seedTransformations` / `seedAI`
    /// are add-only, so a config that already has the built-in descriptors
    /// (from before traits existed) would never pick up their gates. This
    /// copies requiredTraits / forbiddenTraits from the seed onto the
    /// matching installed descriptors, exactly once (UserDefaults-guarded) so
    /// later user edits — including deliberately clearing a gate — are never
    /// re-stamped.
    private func applyBuiltinTraitGatesIfNeeded(into copy: inout ActionConfig) -> Bool {
        let key = "drpaste.migration.builtinTraitGates.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }

        var transformGates: [String: (req: [String], forb: [String])] = [:]
        for d in DefaultTransformationSeed.defaults()
        where !d.requiredTraits.isEmpty || !d.forbiddenTraits.isEmpty {
            transformGates[d.id] = (d.requiredTraits, d.forbiddenTraits)
        }
        var aiGates: [String: (req: [String], forb: [String])] = [:]
        for d in DefaultAISeed.defaults()
        where !d.requiredTraits.isEmpty || !d.forbiddenTraits.isEmpty {
            aiGates[d.id] = (d.requiredTraits, d.forbiddenTraits)
        }

        var changed = false
        for idx in copy.customTransformations.indices {
            if let g = transformGates[copy.customTransformations[idx].id] {
                copy.customTransformations[idx].requiredTraits = g.req
                copy.customTransformations[idx].forbiddenTraits = g.forb
                changed = true
            }
        }
        for idx in copy.customAI.indices {
            if let g = aiGates[copy.customAI[idx].id] {
                copy.customAI[idx].requiredTraits = g.req
                copy.customAI[idx].forbiddenTraits = g.forb
                changed = true
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        return changed
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

        // Append defaults that are not already present. Honour the curated
        // enabled-by-default policy (novelty/niche AI ships OFF) instead of the
        // descriptor's blanket `enabled = true`.
        for desc in DefaultAISeed.defaults() {
            if !copy.customAI.contains(where: { $0.id == desc.id }) {
                var d = desc
                d.enabled = CuratedDefaults.isEnabledByDefault(d.id)
                copy.customAI.append(d)
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
        // v6 migration: image / text→image seeds gained a `Quality: low`
        // directive line (parsed by AIImageHTTP.extractQualityDirective
        // to set OpenAI's quality field; low is ~4× cheaper than the
        // medium default). The keying is `< 6` — not `< 5` — because
        // 0.35.18 bumped seedAIVersion to 5 WITHOUT shipping this
        // block, so a guard on `< 5` would skip the mutation for
        // anyone who already launched under that build. User-
        // customised prompts that already contain a `Quality:` line
        // (whatever tier) are left alone so we don't overwrite an
        // explicit choice.
        if copy.seedAIVersion < 6 {
            let imageSeedIDs: Set<String> = [
                "user.ai_image_sketch",
                "user.ai_image_watercolor",
                "user.ai_image_cartoon",
                "user.ai_text_to_image_whiteboard"
            ]
            for idx in copy.customAI.indices {
                let entry = copy.customAI[idx]
                guard imageSeedIDs.contains(entry.id) else { continue }
                // Already has a Quality directive? Respect it.
                let pattern = #"(?im)^\s*quality\s*:\s*(low|medium|high|auto)\s*$"#
                if entry.promptTemplate.range(of: pattern, options: .regularExpression) != nil {
                    continue
                }
                let trimmed = entry.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.customAI[idx].promptTemplate = trimmed + "\n\nQuality: low"
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
        // The user's explicit hand-ordering wins; otherwise fall back to the
        // curated default order (most valuable / wow first, novelty last). Any
        // applicable action not named in the order is appended afterwards in
        // registration order, so the curated list need not be exhaustive.
        let userOrder = config.actionOrder[kind.rawValue] ?? []
        let order = userOrder.isEmpty ? CuratedActionOrder.order(for: kind) : userOrder
        guard !order.isEmpty else { return moveIdentityFirst(list) }
        var byID: [String: ClipboardAction] = [:]
        for a in list { byID[a.id] = a }
        var result: [ClipboardAction] = []
        for id in order {
            if let a = byID.removeValue(forKey: id) { result.append(a) }
        }
        // Append actions that were not in the order, preserving default order.
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

    /// True when the action carries a "Show this action when…" trait condition
    /// (required or forbidden). Such actions appear in the HUD only when the
    /// current clip matches the condition — i.e. NOT guaranteed — which the
    /// Settings list signals with a different enabled-checkbox colour.
    func hasActiveTraits(_ actionID: String) -> Bool {
        if let desc = config.customAI.first(where: { $0.id == actionID }) {
            return !desc.requiredTraits.isEmpty || !desc.forbiddenTraits.isEmpty
        }
        if let desc = config.customTransformations.first(where: { $0.id == actionID }) {
            return !desc.requiredTraits.isEmpty || !desc.forbiddenTraits.isEmpty
        }
        return false
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

    /// User override for the action's one-line description (second row line
    /// in Settings). Returns nil when the user hasn't customised it — callers
    /// fall back to the bundled default.
    func customDescription(forActionID actionID: String) -> String? {
        config.customDescriptions[actionID]?.text
    }

    /// Persist (or clear) a user description override. Pass nil/empty to drop
    /// the override and restore the bundled default on the next read.
    func setCustomDescription(_ description: String?, forActionID actionID: String) {
        var copy = config
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            let base = BuiltinActionMetadata.descriptions[actionID] ?? ""
            copy.customDescriptions[actionID] = DescriptionOverride(
                text: description,
                baseDefaultHash: ActionConfig.descriptionHash(for: base)
            )
        } else {
            copy.customDescriptions.removeValue(forKey: actionID)
        }
        config = copy
    }

    /// Persisted test-panel Input sample for `actionID`. Returns the
    /// user's override when one exists, otherwise the curated default
    /// from `ActionTestSamples.textSample(for:)`. ActionEditor calls
    /// this on dialog open to pre-fill the Input field.
    func testSample(forActionID actionID: String) -> String? {
        if let stored = config.actionTestSamples[actionID] {
            return stored
        }
        return ActionTestSamples.textSample(for: actionID)
    }

    /// Persist a user-edited test-panel Input sample for `actionID`.
    /// Pass `nil` to drop the override and restore the curated default
    /// on the next dialog open. Empty string IS persisted as an
    /// override ("user explicitly cleared this") because that's
    /// semantically distinct from "use the default".
    func setTestSample(_ sample: String?, forActionID actionID: String) {
        var copy = config
        if let sample = sample {
            // If the user's typed-in text matches the curated default
            // verbatim, drop the override — they didn't really change
            // anything and keeping the entry would balloon
            // actions.json with redundant data. Removing-on-match also
            // lets future updates to the curated default surface
            // automatically for users who never customized.
            if sample == ActionTestSamples.textSample(for: actionID) {
                copy.actionTestSamples.removeValue(forKey: actionID)
            } else {
                copy.actionTestSamples[actionID] = sample
            }
        } else {
            copy.actionTestSamples.removeValue(forKey: actionID)
        }
        config = copy
    }

    /// Persisted custom image blob for `actionID`'s Test panel Input.
    /// Returns the rel filename inside `AppStorage.imagesDir`, or nil
    /// when no user override exists (caller falls back to a
    /// procedurally-generated sample image).
    func testImageRel(forActionID actionID: String) -> String? {
        config.actionTestImageBlobs[actionID]
    }

    /// Persist a user-supplied image as the Test panel Input for
    /// `actionID`. `rel` is the filename inside `AppStorage.imagesDir`;
    /// caller is responsible for copying the bytes there before
    /// invoking this helper. Pass `nil` to drop the override and
    /// restore the procedural sample on the next dialog open.
    func setTestImageRel(_ rel: String?, forActionID actionID: String) {
        var copy = config
        if let rel = rel, !rel.isEmpty {
            copy.actionTestImageBlobs[actionID] = rel
        } else {
            copy.actionTestImageBlobs.removeValue(forKey: actionID)
        }
        config = copy
    }

    // MARK: - Playground per-tab samples

    /// Persisted Sample input text for the Playground's `kind` tab.
    /// Returns the user's override when one exists, otherwise nil so
    /// the caller can fall back to `SettingsSamples.sample(for:)`.
    func playgroundSample(forKind kind: SemanticKind) -> String? {
        config.playgroundSamples[kind.rawValue]
    }

    /// Persist a user-edited Playground Sample input for `kind`. Pass
    /// `nil` to drop the override and restore the curated default on
    /// the next Settings open. Same diff-against-default normalisation
    /// as `setTestSample`: typing the curated text back in clears any
    /// prior stale override so future updates to the default
    /// propagate automatically.
    func setPlaygroundSample(_ sample: String?, forKind kind: SemanticKind) {
        var copy = config
        if let sample = sample {
            let curatedDefault = SettingsSamples.sample(for: kind).previewText ?? ""
            if sample == curatedDefault {
                copy.playgroundSamples.removeValue(forKey: kind.rawValue)
            } else {
                copy.playgroundSamples[kind.rawValue] = sample
            }
        } else {
            copy.playgroundSamples.removeValue(forKey: kind.rawValue)
        }
        config = copy
    }

    /// Persisted custom image filename for the Playground's `kind` tab
    /// (currently only Image tab uses this). Returns the rel inside
    /// `AppStorage.imagesDir` or nil for "no override — use the
    /// standard sample-image fallback chain".
    func playgroundImageRel(forKind kind: SemanticKind) -> String? {
        config.playgroundImageBlobs[kind.rawValue]
    }

    /// Persist a user-dropped custom image for the Playground's
    /// `kind` tab. Same persistence shape as `setTestImageRel` but
    /// keyed by content-type tab instead of per action.
    func setPlaygroundImageRel(_ rel: String?, forKind kind: SemanticKind) {
        var copy = config
        if let rel = rel, !rel.isEmpty {
            copy.playgroundImageBlobs[kind.rawValue] = rel
        } else {
            copy.playgroundImageBlobs.removeValue(forKey: kind.rawValue)
        }
        config = copy
    }

    /// Whether the action with this ID is image-applicable. Used by the
    /// ActionEditor to decide if the Test panel Input should render as
    /// an image preview (drag-drop replaceable) vs the standard text
    /// editor. Probes the action's `isApplicable` against a synthetic
    /// image clip so the predicate stays in sync with each action's
    /// own applicability logic without us maintaining a parallel list.
    func actionAcceptsImage(_ actionID: String) -> Bool {
        guard let action = actions.first(where: { $0.id == actionID }) else { return false }
        let imageProbe = ClipboardItem(
            id: UUID(),
            semantic: .image,
            createdAt: Date(),
            representations: ["public.png": "probe"],
            typesOrdered: ["public.png"],
            previewText: nil,
            previewImageRel: "probe.png",
            sourceBundleID: nil,
            sourceAppName: nil,
            sourceWindowTitle: nil,
            tags: []
        )
        let ctx = ContextDetector.detect(imageProbe)
        return action.isApplicable(item: imageProbe, context: ctx)
    }

    /// Whether the action REQUIRES rich-text input — applicable to
    /// .richText clips but NOT to plain .text clips. Identifies the
    /// rich-text family (rich_to_wiki, rich_to_md, rich_to_html,
    /// rich_to_unicode_style, paste_as_text, clean_formatting). The
    /// ActionEditor uses this to decide whether `runTest` should
    /// promote the testInput markdown to a real RTF inputItem before
    /// dispatching the action; a plain-text item would leave these
    /// actions with nothing to convert.
    func actionRequiresRichText(_ actionID: String) -> Bool {
        guard let action = actions.first(where: { $0.id == actionID }) else { return false }
        let richProbe = ClipboardItem(
            id: UUID(),
            semantic: .richText,
            createdAt: Date(),
            representations: ["public.rtf": "probe"],
            typesOrdered: ["public.rtf"],
            previewText: "probe",
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: nil,
            sourceWindowTitle: nil,
            tags: []
        )
        let textProbe = ClipboardItem(
            id: UUID(),
            semantic: .text,
            createdAt: Date(),
            representations: [:],
            typesOrdered: [],
            previewText: "probe",
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: nil,
            sourceWindowTitle: nil,
            tags: []
        )
        let richCtx = ContextDetector.detect(richProbe)
        let textCtx = ContextDetector.detect(textProbe)
        return action.isApplicable(item: richProbe, context: richCtx)
            && !action.isApplicable(item: textProbe, context: textCtx)
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
        // Drop every existing AI-backed action before re-adding from config.
        // MUST match by ACTION TYPE, not an ID prefix: the #A74 (0.56.0) ID
        // migration renamed AI seeds from `user.*` to `ai.text.*` / `ai.code.*`
        // / `ai.image.*` / `ai.rich.*`, so the old `hasPrefix("user.")` filter
        // matched nothing and every config mutation re-appended the full AI set
        // — duplicating the entire AI block on each didSet (the 127-action
        // explosion). Removing by type also sweeps out any duplicates a prior
        // buggy build already accumulated and any stale entry whose descriptor
        // was deleted from config.
        actions.removeAll { $0 is AIAction || $0 is AIImageAction || $0 is AITextToImageAction }
        for desc in config.customAI {
            let resolvedProviderID: String? = desc.providerID.isEmpty ? nil : desc.providerID
            switch desc.kind {
            case .text:
                let kinds = Set(desc.applicableTypes.compactMap { SemanticKind(rawValue: $0) })
                let action = AIAction(
                    id: desc.id,
                    title: desc.title,
                    promptTemplate: desc.promptTemplate,
                    providerID: resolvedProviderID,
                    applicableTypes: kinds.isEmpty ? [.text, .richText, .markdown] : kinds,
                    preserveRichFormatting: desc.preserveRichFormatting,
                    requiredTraits: desc.requiredTraits,
                    forbiddenTraits: desc.forbiddenTraits
                )
                actions.append(action)
            case .image:
                // Image AI actions ignore `applicableTypes` because the
                // applicability gate is hardcoded to .image (or rich-text
                // with embedded image). Storing applicableTypes in the
                // descriptor just keeps the Codable shape uniform — the
                // value can be ["image"] or [] without affecting behaviour.
                let action = AIImageAction(
                    id: desc.id,
                    title: desc.title,
                    promptTemplate: desc.promptTemplate,
                    providerID: resolvedProviderID
                )
                actions.append(action)
            case .textToImage:
                // Text → Image generation. Like `.image` actions but the
                // applicability gate is the inverse: text-bearing kinds,
                // not image kinds. AITextToImageAction.isApplicable
                // hardcodes the text-content set, so the descriptor's
                // applicableTypes is also informational only.
                let action = AITextToImageAction(
                    id: desc.id,
                    title: desc.title,
                    promptTemplate: desc.promptTemplate,
                    providerID: resolvedProviderID
                )
                actions.append(action)
            }
        }
    }

    /// Adds or updates a custom AI descriptor.
    ///
    /// When `after` is non-nil and the descriptor is brand-new
    /// (no existing row with that id), the new entry is inserted
    /// directly after the row with id == `after` in `customAI`
    /// AND in every per-kind `actionOrder` array that mentions
    /// `after`. This is the Duplicate-button path: a clone lands
    /// right next to its origin in the Settings list, in the HUD
    /// chip strip, and in any pinned ordering — wherever the
    /// original lives, the duplicate lives one step to the right.
    /// `after` is ignored for updates (we don't relocate an
    /// existing row when its descriptor changes).
    func upsertCustomAI(_ descriptor: CustomAIDescriptor, after: String? = nil) {
        var copy = config
        if let idx = copy.customAI.firstIndex(where: { $0.id == descriptor.id }) {
            copy.customAI[idx] = descriptor
        } else if let after = after,
                  let anchorIdx = copy.customAI.firstIndex(where: { $0.id == after }) {
            copy.customAI.insert(descriptor, at: anchorIdx + 1)
            insertIntoActionOrder(&copy, newID: descriptor.id, after: after)
        } else {
            copy.customAI.append(descriptor)
        }
        config = copy  // triggers save + rebuildCustomAI
    }

    /// Place `newID` immediately after `after` in every
    /// `actionOrder[kind]` entry that mentions `after`. Idempotent —
    /// skips kinds where `newID` is already present (re-running the
    /// duplicate flow shouldn't double-insert).
    private func insertIntoActionOrder(_ copy: inout ActionConfig,
                                        newID: String,
                                        after: String) {
        for (kind, ids) in copy.actionOrder {
            guard let pos = ids.firstIndex(of: after) else { continue }
            guard !ids.contains(newID) else { continue }
            var newIDs = ids
            newIDs.insert(newID, at: pos + 1)
            copy.actionOrder[kind] = newIDs
        }
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

    /// Same Duplicate-button neighbour-insert behaviour as
    /// `upsertCustomAI(after:)` — see that comment for the rationale.
    func upsertCustomTransformation(_ descriptor: CustomTransformationDescriptor,
                                     after: String? = nil) {
        var copy = config
        if let idx = copy.customTransformations.firstIndex(where: { $0.id == descriptor.id }) {
            copy.customTransformations[idx] = descriptor
        } else if let after = after,
                  let anchorIdx = copy.customTransformations.firstIndex(where: { $0.id == after }) {
            copy.customTransformations.insert(descriptor, at: anchorIdx + 1)
            insertIntoActionOrder(&copy, newID: descriptor.id, after: after)
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
    /// #A46 (0.57.0) — synchronously drain the pending debounced
    /// save. Called from `applicationWillTerminate` and the Factory
    /// Reset path so a Settings edit made 50 ms before quit / wipe
    /// never strands. Idempotent.
    func flushPendingConfigSave() {
        configSaver.flushSync()
    }

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
        Task { @MainActor in
            ActionHotkeyManager.shared.reload()
            (NSApp.delegate as? AppDelegate)?.reloadHoldPreviewMap()
        }
    }

    // MARK: - Export / Import

    /// Serializes config to JSON for export. API keys are NOT included.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(config)
    }

    /// Imports config. `.replace` overwrites every field wholesale;
    /// `.merge` applies the per-field policy table documented in
    /// `ImportReport.swift` (#A41, 0.57.0).
    enum ImportStrategy { case replace, merge }

    /// Boolean-only entry point — preserved for existing call sites
    /// that don't yet consume the audit report.
    @discardableResult
    func importJSON(_ data: Data, strategy: ImportStrategy) -> Bool {
        importJSONWithReport(data, strategy: strategy) != nil
    }

    /// Report-returning entry point. nil means the JSON failed to
    /// decode at all (caller should surface a parse error); a
    /// non-nil `ImportReport` is the audit summary — pass it to the
    /// Settings sheet so the user can see what changed.
    ///
    /// `.replace` mode returns an empty report because there's no
    /// per-field conflict to surface — the entire file took over.
    func importJSONWithReport(_ data: Data, strategy: ImportStrategy) -> ImportReport? {
        guard let incoming = try? JSONDecoder().decode(ActionConfig.self, from: data) else {
            return nil
        }
        switch strategy {
        case .replace:
            config = incoming
            return ImportReport()
        case .merge:
            let (merged, report) = config.merging(incoming)
            config = merged
            return report
        }
    }
}
