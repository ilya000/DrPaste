//
//  PasteCommitter.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Single-source-of-truth mapper from `ApplyOutcome` → user-visible
//  commit side-effect (#A39, 0.57.0).
//
//  Background: before 0.57, commit-side policy lived in three
//  different `switch outcome` blocks across `main.swift`:
//
//    1. `commitOutcome(_:savedApp:)` — BigHUD commit + deferred AI
//       completion. On `.failed`, pastes the original.
//    2. `actionHotkeyDidFire(actionID:)` direct-trigger — per-action
//       hotkey path. On `.failed`, plays a failure chime only (no
//       paste of original — direct-trigger is "do this action,"
//       not "paste this clip").
//    3. Settings playground "Run test" — renders the outcome in
//       `TestOutputPane`. Must never escape into the system
//       pasteboard or type into the frontmost app, no matter what
//       the user's test action returns.
//
//  Each switch carried the per-outcome handling inline, which is
//  exactly how the 0.42.x Type Slowly bug shipped: the direct-trigger
//  switch collapsed `.alternativeCommit(_, .typeSlowly(_, _))` into
//  plain ⌘V paste, defeating the action's entire purpose. The hot-
//  patch fixed that one path; nothing prevented the next surface
//  (Services menu, drag-out) from carrying the same bug back in.
//
//  This file is the unified policy table. Every commit site routes
//  through `PasteCommitter.commit(_:into:mode:)`. Adding a new mode
//  or outcome requires updating the dispatch here — the compiler
//  forces every case to be considered.
//
//  Scope note: the 0.57.0 ship migrates two of the three surfaces
//  above (BigHUD commit + direct-trigger hotkey) and adds
//  `.previewOnly` mode for the Settings playground guard. The
//  remaining ⌥⌘⏎ paste-and-keep and deferred-AI paths still call
//  the legacy helpers directly because they need additional state
//  bookkeeping (HUD lifecycle, generation tokens) that isn't ready
//  to fold into a pure committer yet. Migration of those is a
//  follow-up under the next batch's #A42 state-machine work.
//

import AppKit
import Foundation

@MainActor
enum PasteCommitter {

    /// How a commit should treat side effects, fail outcomes, and
    /// alternative commit styles. The dispatch table in `commit(_:into:mode:)`
    /// reads from this single source.
    enum Mode {
        /// Standard BigHUD release-to-paste commit. Closes the HUD
        /// (handled by the caller), pastes the result, falls back to
        /// pasting the original on `.failed`.
        case standard

        /// ⌥⌘⏎ paste-and-keep. Identical paste semantics to
        /// `.standard` but the HUD stays open behind it — the caller
        /// is responsible for *not* tearing the panel down. Side
        /// effects still close the HUD before they fire so a Finder
        /// reveal doesn't land behind the stranded HUD.
        case keepingHUDOpen

        /// Deferred-AI completion. AI finished while the HUD was
        /// already gone (user committed during streaming). Pastes
        /// the result without further HUD handling. On `.failed`,
        /// plays the failure chime only — by the time we get here
        /// the user is back in their target app, surprise-pasting
        /// the original would be worse than silence.
        case deferredAI

        /// Per-action hotkey direct trigger. On `.failed`, plays the
        /// failure chime only — same logic as `.deferredAI`: the
        /// user pressed a hotkey to *transform*, not to *paste*.
        case directHotkey

        /// Settings playground "Run test". Refuses to commit to the
        /// system pasteboard, type into the frontmost app, or run
        /// any side effect. The outcome flows back to the caller via
        /// the optional `previewOnly` continuation parameter so
        /// `TestOutputPane` can render it.
        case previewOnly
    }

    /// What `commit` did, or refused to do, for the caller's logging
    /// and UI feedback. `.skipped` carries a human-readable reason
    /// for the cases where the mode rejected the outcome (currently
    /// only `.previewOnly`).
    enum Result: Equatable {
        case committed
        case skipped(reason: String)
    }

    /// Commit a single outcome. Side effects (paste, type-slowly,
    /// reveal-in-finder, failure sound) fire synchronously off the
    /// MainActor, except for `performStandardPaste` which kicks
    /// itself onto a 50 ms `asyncAfter` so the HUD can close first.
    ///
    /// Returns `.committed` for the normal happy path; `.skipped`
    /// for `.previewOnly` rejections. Callers usually ignore the
    /// return value — it exists for tests and a future log line.
    ///
    /// - Parameters:
    ///   - outcome: the `ApplyOutcome` produced by the action.
    ///   - sourceApp: the application the user was in when the
    ///     commit was requested. Pasted-into target. Pass `nil` from
    ///     `.previewOnly` since no app interaction happens.
    ///   - mode: see the `Mode` cases.
    ///   - performer: side-effect delegate. The owning AppDelegate
    ///     implements this; the committer doesn't depend on AppKit
    ///     specifics so it stays testable.
    @discardableResult
    static func commit(_ outcome: ApplyOutcome,
                       into sourceApp: NSRunningApplication?,
                       mode: Mode,
                       performer: PasteCommitterPerformer) -> Result {
        // `.previewOnly` rejects everything that would escape into
        // the system. Returns a structured reason so the caller can
        // surface "test-only" notices in the TestOutputPane.
        if case .previewOnly = mode {
            switch outcome {
            case .preview, .failed:
                // Rendering-only outcomes are safe — the playground
                // shows them inline without touching the system.
                return .committed
            case .sideEffect(let description, _):
                return .skipped(reason: "Side effect not runnable from the test panel: \(description)")
            case .alternativeCommit(_, let style):
                return .skipped(reason: "\(Self.styleLabel(style)) not runnable from the test panel")
            }
        }

        switch outcome {
        case .preview(let item), .alternativeCommit(let item, .standardPaste):
            performer.performStandardPaste(item, savedApp: sourceApp)

        case .alternativeCommit(let item, .typeSlowly(let delay, let jitter)):
            performer.performTypeSlowly(item, savedApp: sourceApp,
                                        delay: delay, jitter: jitter)

        case .alternativeCommit(let item, .typeFast):
            // typeFast is encoded as TypeSlowly with a fixed
            // (50 ms, 0) profile so the simulator path stays
            // single. Preserved verbatim from the pre-committer
            // call sites.
            performer.performTypeSlowly(item, savedApp: sourceApp,
                                        delay: 0.05, jitter: 0)

        case .failed(let original, _, _):
            switch mode {
            case .standard, .keepingHUDOpen:
                // HUD surfaces commit the original on failure so the
                // user still gets *something* from their gesture.
                performer.performStandardPaste(original, savedApp: sourceApp)
                performer.playFailureSound()
            case .deferredAI, .directHotkey:
                // Direct-trigger paths don't surprise-paste — failure
                // chime only.
                performer.playFailureSound()
            case .previewOnly:
                // Unreachable — handled above. Kept for exhaustive
                // switch compile.
                break
            }

        case .sideEffect(_, let perform):
            if case .keepingHUDOpen = mode {
                // Side effects steal focus (Finder reveal, URL
                // open). Leaving the HUD behind a Finder window
                // confuses — close it first.
                performer.closeBigHUDForSideEffect()
            }
            perform()
            performer.playSuccessSound()
        }
        return .committed
    }

    // MARK: Helpers

    private static func styleLabel(_ style: CommitStyle) -> String {
        switch style {
        case .standardPaste:    return "Standard paste"
        case .typeSlowly:       return "Type Slowly"
        case .typeFast:         return "Type Fast"
        }
    }
}

/// Side-effect delegate that the committer talks to. The
/// AppDelegate already implements `performStandardPaste`,
/// `performTypeSlowly`, and the two sound calls; this protocol
/// lifts them into a testable seam without committing to a
/// particular owner type. Default extension implementations are
/// not provided — the AppDelegate's existing helpers satisfy the
/// requirements verbatim.
@MainActor
protocol PasteCommitterPerformer {
    func performStandardPaste(_ item: ClipboardItem,
                              savedApp: NSRunningApplication?)
    func performTypeSlowly(_ item: ClipboardItem,
                           savedApp: NSRunningApplication?,
                           delay: TimeInterval,
                           jitter: Double)
    func playSuccessSound()
    func playFailureSound()
    func closeBigHUDForSideEffect()
}
