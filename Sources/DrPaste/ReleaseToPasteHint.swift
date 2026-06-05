//
//  ReleaseToPasteHint.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Release-to-paste discoverability hint (#A59). The central gesture
//  of the product — hold ⌥⌘V, browse, release-to-paste — is not
//  surfaced anywhere visible inside BigHUD itself. Footer hints were
//  intentionally kept terse to fit width; this hint sits above the
//  history strip in Gesture Mode only, fades away once the user has
//  visibly internalised the gesture (5 successful commits in the
//  current reset generation), and re-appears once on the next open
//  if the user has been away ≥ 90 days.
//
//  Adversarial-pass-driven design:
//    • Counter is keyed by a per-reset generation. Factory Reset bumps
//      the generation, counter starts over — re-education from a clean
//      slate.
//    • Fresh-install-on-new-machine: UserDefaults doesn't sync by
//      default, so the counter is zero and the hint shows.
//    • Year-old user staleness: 90-day silence triggers exactly one
//      re-show, even if the counter is past threshold.
//    • Settings → General has a toggle to force the hint permanently
//      on for users who want it.
//

import Foundation

/// Persisted state for the discoverability counter. JSON-encoded into
/// UserDefaults under `drpaste.hint.releaseToPaste`.
struct ReleaseToPasteHintState: Codable {
    var successfulCommits: Int = 0
    var lastShownVersion: String = ""
    var lastCommitDate: Date = .distantPast
    var resetGeneration: Int = 0
    /// Set when staleness re-show has been honoured for the current
    /// dormancy gap so we don't repeat it on every open during the
    /// recovery window.
    var staleReshowConsumed: Bool = false
}

enum ReleaseToPasteHint {

    /// UserDefaults key for the JSON-encoded state.
    private static let stateKey = "drpaste.hint.releaseToPaste"
    /// UserDefaults key for the always-on override toggle (Settings →
    /// General → "Show release-to-paste hint").
    private static let forceShowKey = "drpaste.hint.releaseToPaste.forceShow"
    /// Threshold of successful commits after which the hint quiets.
    private static let dismissAfterCommits = 5
    /// Dormancy window before the hint re-shows once.
    private static let staleWindow: TimeInterval = 90 * 24 * 60 * 60

    /// True when the BigHUD should render the hint string. Reads
    /// state + force flag + staleness. Pure — call freely from a
    /// SwiftUI body. The state is mutated only by `recordCommit()`
    /// and `acknowledgeStaleReshow()`.
    static var shouldShow: Bool {
        if UserDefaults.standard.bool(forKey: forceShowKey) { return true }
        let state = loadState()
        // Counter under threshold → show.
        if state.successfulCommits < dismissAfterCommits { return true }
        // Stale re-show pending → show until acknowledged.
        let dormancy = Date().timeIntervalSince(state.lastCommitDate)
        if dormancy > staleWindow && !state.staleReshowConsumed { return true }
        return false
    }

    /// Bump the success counter. Call from BigHUD's commit path after
    /// a successful paste. Idempotent for stale-reshow: the re-show
    /// flag is consumed here so the hint goes quiet on the next open.
    static func recordCommit() {
        var state = loadState()
        state.successfulCommits += 1
        state.lastCommitDate = Date()
        state.lastShownVersion = AppBrand.version
        state.staleReshowConsumed = true
        saveState(state)
    }

    /// Mark the stale-reshow path as consumed without bumping the
    /// counter. Called by BigHUD when the hint surface paints during
    /// a stale-recovery window — the user has seen it, no need to
    /// re-show on every subsequent open.
    static func acknowledgeStaleReshow() {
        var state = loadState()
        state.staleReshowConsumed = true
        saveState(state)
    }

    /// Bump the reset generation and zero the counter — used by
    /// Factory Reset so the user re-learns from scratch.
    static func resetForFactoryReset() {
        var state = loadState()
        state.resetGeneration += 1
        state.successfulCommits = 0
        state.staleReshowConsumed = false
        state.lastCommitDate = .distantPast
        saveState(state)
    }

    // MARK: I/O

    private static func loadState() -> ReleaseToPasteHintState {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let decoded = try? JSONDecoder().decode(ReleaseToPasteHintState.self,
                                                      from: data) else {
            return ReleaseToPasteHintState()
        }
        return decoded
    }

    private static func saveState(_ state: ReleaseToPasteHintState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}
