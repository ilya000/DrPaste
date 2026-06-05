//
//  ElapsedClock.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Shared elapsed-time ticker (#A50). Replaces scattered
//  `Timer.scheduledTimer` instances across BigHUD AI loading state,
//  MiniHUD, SettingsWindow test result, and ActionEditor playground —
//  each of which had to manually invalidate the timer on `.onDisappear`
//  or hide() with subtly different lifecycles. Centralising as an
//  ObservableObject driven by a `Task.sleep` loop lets SwiftUI's
//  `.task` modifier auto-cancel for us, and removes one whole class of
//  "I forgot to invalidate that Timer" bugs.
//

import Foundation
import SwiftUI

/// Ticks `elapsed` at 10 Hz from a start time. The publish path is
/// MainActor so SwiftUI views can observe directly without an extra
/// `.receive(on:)`. Pause/resume is intentionally not supported — every
/// caller wants "monotonic seconds since I started this thing".
///
/// Lifecycle:
///   • `init(startedAt:)` creates and starts ticking immediately.
///   • `.cancel()` stops the internal Task; safe to call multiple times.
///   • `deinit` cancels the Task as a safety net for callers that
///     don't hold the clock as a `.task` lifetime.
///
/// Use from SwiftUI:
///   ```swift
///   @StateObject private var clock: ElapsedClock?
///   .onAppear { clock = ElapsedClock(startedAt: Date()) }
///   .onDisappear { clock?.cancel() }
///   ```
/// Or, more concisely, hand the lifetime to the view tree:
///   ```swift
///   .task {
///       let clock = ElapsedClock(startedAt: Date())
///       defer { clock.cancel() }
///       // ... await result, read clock.elapsed as needed
///   }
///   ```
@MainActor
final class ElapsedClock: ObservableObject {

    /// Seconds elapsed since `startedAt`. Updated at 10 Hz on the main
    /// actor; safe to read inside SwiftUI body.
    @Published private(set) var elapsed: TimeInterval = 0

    private let startedAt: Date
    private var task: Task<Void, Never>?

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        start()
    }

    deinit {
        task?.cancel()
    }

    /// Cancel the internal tick task. Idempotent — calling twice is a
    /// no-op. Callers that don't hand the lifetime to SwiftUI (e.g.
    /// AppKit consumers) should call this in their tear-down path.
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Reset elapsed to 0 and re-anchor at `now`. Used by callers that
    /// reuse a clock instance across multiple consecutive runs (e.g. a
    /// playground that fires the same test twice and wants the second
    /// run to count from its own start, not from when the first one
    /// began).
    func restart(at now: Date = Date()) {
        cancel()
        elapsed = 0
        start(from: now)
    }

    private func start(from anchor: Date? = nil) {
        let from = anchor ?? startedAt
        task = Task { [weak self] in
            // 10 Hz tick — matches the cadence the legacy Timers used
            // (0.1 s interval). Lower would make the elapsed counter
            // visibly jumpy on fast AI calls; higher costs CPU for no
            // user-visible benefit.
            while !Task.isCancelled {
                let now = Date()
                await MainActor.run { [weak self] in
                    self?.elapsed = now.timeIntervalSince(from)
                }
                // Sleep on a background priority — escapes MainActor
                // congestion (see #245 lesson: a long-running AI call
                // that hammers MainActor can starve a MainActor-bound
                // Task.sleep, but a background Task.sleep keeps ticking).
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}
