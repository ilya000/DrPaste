//
//  PreferenceKeys.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Centralised UserDefaults key strings. Every key used in the project
//  should live here as a static constant. Three reasons:
//
//   1. Factory Reset iterates a single source of truth via `allKeys`
//      and can't drift from the actual keys used by the rest of the
//      code (the previous hand-maintained list was already silently
//      out of date).
//   2. SKILL.md APPENDIX B documents the key names by symbol reference,
//      so code and docs can't drift apart.
//   3. Compile-time renames find every call site through the symbol
//      graph, no string-search dance.
//
//  Naming convention: `drpaste.<area>.<purpose>`. New keys must follow.
//  This file is the dictionary; do NOT inline new "drpaste.*" strings
//  elsewhere — find a slot here first.
//

import Foundation

enum PreferenceKeys {

    // MARK: HUD

    static let hudFontScale            = "drpaste.hud.fontScale"
    static let cutReplaceCursorOnSecond = "drpaste.hud.cursorOnSecondOnCut"
    /// When true, holding ⌥⌘ after an action hotkey does NOT open the BigHUD
    /// preview — the action fires immediately like a tap. Default false
    /// (hold-preview ON). Lets users who never want the hold-preview turn it off.
    static let actionHotkeyHoldPreviewDisabled = "drpaste.hotkey.holdPreviewDisabled"

    // MARK: Append Copy

    static let appendToastsEnabled     = "drpaste.append.toastsEnabled"

    // MARK: Region capture

    static let cheatSheetDisabled      = "drpaste.cheatSheet.disabled"

    // MARK: Appearance

    static let theme                   = "drpaste.theme"

    // MARK: Sound feedback

    static let soundVolume             = "drpaste.sound.volume"
    static let soundCopySuccess        = "drpaste.sound.copySuccess"
    static let soundCopyFailure        = "drpaste.sound.copyFailure"
    static let soundPasteSuccess       = "drpaste.sound.pasteSuccess"
    static let soundPasteFailure       = "drpaste.sound.pasteFailure"
    static let soundAppend             = "drpaste.sound.append"
    static let soundTypeTick           = "drpaste.sound.typeTick"
    static let soundDelete             = "drpaste.sound.delete"

    // MARK: Welcome / onboarding

    static let welcomeShown            = "drpaste.welcome.shownOnce"
    static let releaseToPasteHintState = "drpaste.hint.releaseToPaste"  // see #A59 schema

    // MARK: Usage probes

    static let openRouterAnchorPrefix  = "drpaste.openrouter.anchor"

    // MARK: APIKeyStorage

    static let apiKeysFallbackOnly     = "drpaste.api_keys.use_fallback_only"

    // MARK: All keys (for Factory Reset)

    /// Every key the app writes to UserDefaults under its own namespace.
    /// Factory Reset iterates this list and removes each. Add a new
    /// constant above? Add it here too.
    ///
    /// NOTE: per-provider OpenRouter anchor entries are stored under
    /// `\(openRouterAnchorPrefix).<providerID>.<field>` and are NOT
    /// individually listed; Factory Reset's caller is expected to
    /// also remove any key whose name begins with that prefix.
    static let allDirectKeys: [String] = [
        hudFontScale,
        cutReplaceCursorOnSecond,
        actionHotkeyHoldPreviewDisabled,
        appendToastsEnabled,
        cheatSheetDisabled,
        theme,
        soundVolume,
        soundCopySuccess, soundCopyFailure,
        soundPasteSuccess, soundPasteFailure,
        soundAppend, soundTypeTick, soundDelete,
        welcomeShown,
        releaseToPasteHintState,
        apiKeysFallbackOnly
    ]
}
