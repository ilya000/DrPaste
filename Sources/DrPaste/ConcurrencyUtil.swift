//
//  ConcurrencyUtil.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Small async/await helpers shared across surfaces.
//

import Foundation

/// Install a watchdog that cancels the given primary task after
/// `timeoutSeconds` of wall-clock time. The watchdog runs as a
/// `Task.detached(priority: .background)` so it executes on the
/// global concurrent executor and is NOT starved by MainActor
/// congestion.
///
/// **Why detached** (#245 lesson, 0.41.0): a MainActor-bound
/// `Task.sleep` watchdog gets queued behind every other MainActor
/// continuation. When `AIProvider.stream(...)` yields many small
/// chunks to MainActor (token-by-token preview), the MainActor
/// queue can stay busy for 30–60 seconds at a time; a MainActor
/// watchdog scheduled to fire at 90 s effectively never fires
/// because its continuation is way down the queue behind all the
/// streaming chunks. Detaching to the global executor sidesteps
/// the issue completely.
///
/// Usage:
///
///     let primary = Task { ... long-running work ... }
///     let cancelWatchdog = installWatchdog(seconds: 90, cancelling: primary)
///     defer { cancelWatchdog.cancel() }
///     try await primary.value
///
/// Returned token cancels the watchdog (use in `defer { ... }`).
@discardableResult
func installWatchdog<R>(seconds: TimeInterval,
                       cancelling primary: Task<R, Error>) -> Task<Void, Never> {
    return Task.detached(priority: .background) {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        guard !Task.isCancelled else { return }
        primary.cancel()
    }
}

/// Sendable-success variant for tasks whose `R` is non-throwing.
@discardableResult
func installWatchdog<R: Sendable>(seconds: TimeInterval,
                                  cancelling primary: Task<R, Never>) -> Task<Void, Never> {
    return Task.detached(priority: .background) {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        guard !Task.isCancelled else { return }
        primary.cancel()
    }
}
