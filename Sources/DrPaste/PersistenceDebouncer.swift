//
//  PersistenceDebouncer.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Shared debounced-write helper (#A46, 0.57.0).
//
//  Background: the two large JSON files DrPaste maintains —
//  `actions.json` (ActionConfig) and `index.json` (ClipboardStore) —
//  used to be rewritten synchronously on every mutation. Rapid copy
//  bursts (multi-clip ⌥⌘S session, batch import) and Settings
//  thrash (toggle a checkbox, drag a row) would re-pretty-print and
//  re-write the entire file dozens of times per second. On
//  Dropbox-resident Application Support the cost compounds —
//  Dropbox sees each rewrite as a new file revision and queues
//  upload. Users reported 200–500 ms UI hitches in Settings.
//
//  Strategy:
//
//    - Coalesce writes within a 200 ms window. The last call in
//      the burst wins; intermediate states never hit disk.
//    - Flush immediately on lifecycle exits (applicationWillTerminate,
//      Factory Reset) so the user never loses an in-flight edit.
//    - Run the actual `Data.write(to:options:.atomic)` off the main
//      thread — `.atomic` already does a temp-file-rename swap, so
//      the writer thread can't tear a half-written file. The main
//      thread is only on the hook for prepping the bytes (encoder).
//
//  Thread safety: callers can `schedule`/`flushSync` from any
//  thread. The helper hops to main to mutate its tracking state
//  (so concurrent calls don't race over the DispatchWorkItem
//  handle) and then dispatches the actual disk hit onto a private
//  serial background queue.
//
//  Usage:
//
//      // owner side
//      private let saver = PersistenceDebouncer(label: "ActionConfig")
//
//      func scheduleSave() {
//          saver.schedule { [weak self] in self?.actuallyWrite() }
//      }
//
//      func applicationWillTerminate() {
//          saver.flushSync()    // blocks briefly to finish a pending write
//      }
//

import Foundation

/// Coalescing 200 ms-debounced writer. Hold one per file you want
/// to persist; the helper is intentionally tiny and does not
/// generically wrap the file IO itself — callers supply the
/// "actually write this file now" closure so encoding choices stay
/// at the call site.
public final class PersistenceDebouncer: @unchecked Sendable {

    /// Tag for NSLog diagnostics. Visible in Console.app on rapid
    /// burst flushes so the user / support can correlate a
    /// "DrPaste rewrote X" log line with whatever activity drove it.
    public let label: String

    /// Debounce window. 200 ms balances "instant enough that an
    /// app-quit-after-Settings-edit lands" against "long enough
    /// that toggling three checkboxes coalesces into one write."
    public let interval: TimeInterval

    /// Background queue for the actual disk hit. `.utility` priority
    /// matches the "expensive but not user-blocking" intent.
    private let queue: DispatchQueue

    /// Pending work-item handle. Nil when no save is queued. Touched
    /// only on main via `schedule` / `flushSync` so the cancel/replace
    /// dance can't tear.
    private var pendingItem: DispatchWorkItem?

    /// The latest scheduled closure. Held separately so `flushSync`
    /// can run it inline without firing the async dispatch.
    private var pendingWriter: (() -> Void)?

    public init(label: String, interval: TimeInterval = 0.2) {
        self.label = label
        self.interval = interval
        self.queue = DispatchQueue(label: "drpaste.persistence.\(label.lowercased())",
                                   qos: .utility)
    }

    /// Queue a write to fire after `interval` of inactivity. Multiple
    /// calls inside the window collapse — only the last writer runs.
    /// Safe to call from any thread; the bookkeeping hops to main
    /// so concurrent calls can't race the cancel/replace.
    public func schedule(_ writer: @escaping () -> Void) {
        runOnMain {
            self.pendingItem?.cancel()
            self.pendingWriter = writer
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // Move actual file IO off the main thread.
                self.queue.async {
                    writer()
                }
                // Clear pending markers on the main thread.
                self.runOnMain {
                    self.pendingItem = nil
                    self.pendingWriter = nil
                }
            }
            self.pendingItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + self.interval, execute: item)
        }
    }

    /// Run the pending writer right now and block until it returns.
    /// Used by `applicationWillTerminate` so a Settings edit made
    /// 50 ms before quit never gets lost.
    ///
    /// Safe to call from any thread, including main. When called
    /// from main it runs the writer synchronously; otherwise it
    /// dispatch-syncs to main first.
    ///
    /// Safe to call when nothing is queued — returns immediately.
    public func flushSync() {
        runOnMain {
            self.pendingItem?.cancel()
            let writer = self.pendingWriter
            self.pendingItem = nil
            self.pendingWriter = nil
            writer?()
        }
    }

    /// Diagnostic — true when a save is queued but not yet on disk.
    /// Exposed for tests; the runtime doesn't read this.
    public var hasPendingWrite: Bool {
        var result = false
        runOnMain { result = self.pendingWriter != nil }
        return result
    }

    /// Run the closure on main, synchronously. Used to keep
    /// `pendingItem` / `pendingWriter` mutations race-free without
    /// requiring `@MainActor` on the type (callers shouldn't have
    /// to also be MainActor just to schedule a save).
    private func runOnMain(_ block: () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
    }
}
