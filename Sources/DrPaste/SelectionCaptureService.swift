//
//  SelectionCaptureService.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Selection-first capture pipeline (#A40, 0.57.0). Wraps the
//  "snapshot the user's current text/file selection into a
//  ClipboardItem" sequence used by every direct-trigger surface
//  (per-action hotkey, ⌥⌘V hold-preview, ⌥⌘X Cut & Replace,
//  ⌥⌘C Quick Copy, ⌥⌘S Append Copy session seed, macOS Services
//  context menu) so they all agree on:
//
//    1. Accessibility-trust precondition. Without AX, the
//       synthetic ⌘C posts but nothing actually copies; previously
//       each call site checked `AXIsProcessTrusted()` independently
//       (or in some cases didn't), producing inconsistent error
//       behaviour.
//    2. Pasteboard `changeCount` polling with a 0.40 s budget
//       (matches `PasteSimulator.simulateCopyAndAwaitChange` —
//       see the 0.42.2 bump for the reasoning).
//    3. Source-application identity captured AT ENTRY TIME, not
//       inferred later from `NSWorkspace.frontmostApplication`
//       (which can flip mid-await if the user clicks somewhere).
//    4. Lossless representation snapshot — every pasteboard type
//       that has bytes gets written to the blob store, so the
//       resulting `ClipboardItem` can round-trip through Paste-
//       as-is later.
//    5. Optional `promoteToHistory` flag for callers that want the
//       captured selection inserted into the visible clipboard
//       history (BigHUD hold-preview, ⌥⌘X, per-action hotkey).
//       Disabled by default — pure transformations don't need it.
//
//  The service returns a typed `Result<Captured, CaptureError>` so
//  callers can:
//    - `.inaccessible`         → walk the user to System Settings
//                                 → Privacy → Accessibility.
//    - `.noSelection`          → silent abort (common case — user
//                                 fired the hotkey without selecting
//                                 anything).
//    - `.timeout(_)`           → play `.copyFailure`, log frontmost
//                                 bundle ID for diagnostics.
//    - `.emptyPayload`         → pasteboard ticked but every
//                                 representation came back empty
//                                 (rare; some Electron apps do this
//                                 on partial selection clears).
//

import AppKit
import Foundation

@MainActor
enum SelectionCaptureService {

    // MARK: Types

    /// Reason the capture didn't yield a usable selection. Callers
    /// branch on these to choose between a silent abort and a
    /// user-facing failure surface.
    enum CaptureError: Error, Equatable {
        /// `AXIsProcessTrusted()` returned false. Synthetic ⌘C
        /// would post but nothing would actually copy from the
        /// frontmost app, so we don't bother trying.
        case inaccessible
        /// `changeCount` did not advance within `timeout`. Usually
        /// means the user didn't have anything selected.
        case noSelection
        /// Capture took longer than the configured timeout. The
        /// `0.40 s` default is enough for native AppKit; Electron /
        /// Office sometimes need more.
        case timeout(TimeInterval)
        /// Pasteboard advanced its `changeCount` but every type
        /// produced empty data. Rare edge case; treat as a soft
        /// failure with no further retry.
        case emptyPayload
    }

    /// Successful capture result. `captureGeneration` is a monotonic
    /// counter the caller can pair with later state mutations to
    /// detect "this capture is stale, drop it" races — same pattern
    /// the BigHUD preview-token system uses.
    struct Captured {
        let item: ClipboardItem
        let sourceApp: NSRunningApplication?
        let captureGeneration: Int
        let pasteboardChangeCount: Int
    }

    // MARK: API

    /// Snapshot whatever the user currently has selected in the
    /// frontmost app into a fresh `ClipboardItem`.
    ///
    /// - Parameters:
    ///   - sourceApp: Optional override. When nil (the common case)
    ///     the service captures `NSWorkspace.shared.frontmostApplication`
    ///     at entry time. Pass an explicit value when the caller has
    ///     already raced ahead of `NSWorkspace`'s observation cycle
    ///     (e.g. region-capture passes `regionCaptureSourceApp`,
    ///     which was snapshotted milliseconds before the arm).
    ///   - store: Required. Raw representations are written via
    ///     `store.writeRawBlob(_:type:)` so the resulting item can
    ///     restore losslessly via `PasteboardWriter`.
    ///   - timeout: Pasteboard-change polling budget. Default 0.40 s
    ///     matches `PasteSimulator.simulateCopyAndAwaitChange`.
    ///   - promoteToHistory: When `true`, calls `watcher?.forceTick()`
    ///     after a successful capture so the freshly-copied selection
    ///     surfaces in the BigHUD history strip at index 0 on the
    ///     next refresh. Default `false` — most transformation paths
    ///     don't want the raw selection persisted on its own.
    ///   - watcher: The shared `ClipboardWatcher`. Required only when
    ///     `promoteToHistory: true`. The service flips
    ///     `watcher.ignoreNextChange = false` defensively before the
    ///     forceTick so a stale guard from an earlier flow doesn't
    ///     swallow this capture.
    static func capture(
        sourceApp: NSRunningApplication? = nil,
        store: ClipboardStore,
        timeout: TimeInterval = 0.40,
        promoteToHistory: Bool = false,
        watcher: ClipboardWatcher? = nil
    ) async -> Result<Captured, CaptureError> {

        // 1. AX precondition. Without trust, the synthetic ⌘C posts
        //    but the frontmost app doesn't copy anything, so we'd
        //    sit through the full 0.40 s budget for nothing.
        guard AXIsProcessTrusted() else {
            return .failure(.inaccessible)
        }

        // 2. Snapshot source-app identity AT ENTRY TIME. The
        //    pasteboard poll below awaits up to 0.40 s, during
        //    which `NSWorkspace.frontmostApplication` can flip if
        //    the user clicks somewhere else. The post-capture
        //    history entry and any downstream provenance need the
        //    app that was actually copied FROM, not whatever is
        //    in front now.
        let resolvedSourceApp = sourceApp ?? NSWorkspace.shared.frontmostApplication

        // 3. Pre-tick → post-tick changeCount diff is the change
        //    detection signal. Note we read this BEFORE the synthetic
        //    ⌘C so a pasteboard write from another process during
        //    the poll window doesn't false-positive as our success.
        let pb = NSPasteboard.general
        let beforeCount = pb.changeCount

        let captured = await PasteSimulator.simulateCopyAndAwaitChange(timeout: timeout)
        guard captured else {
            // Distinguish "no selection at all" from "took too long".
            // We can't actually tell the two apart from the
            // simulateCopy return value (both produce `false`), but
            // the timeout is the user-actionable case — leak the
            // configured value so the failure UI can show "tried
            // for N ms". Callers that don't care can pattern-match
            // .timeout(_) with a wildcard.
            return .failure(.timeout(timeout))
        }
        let afterCount = pb.changeCount

        // 4. Build the item directly off the live pasteboard. Mirrors
        //    the inlined logic that used to live in
        //    `AppDelegate.snapshotPasteboardAsItem`, but lifted into
        //    the service so every direct-trigger surface gets the
        //    same shape (and any future correctness fix lands in one
        //    place).
        let textValue = pb.string(forType: .string) ?? ""
        let typesRaw = pb.types?.map(\.rawValue) ?? []
        let semantic = SemanticClassifier.classify(types: typesRaw, pasteboard: pb)

        var item = ClipboardItem(
            id: UUID(),
            semantic: semantic,
            createdAt: Date(),
            representations: [:],
            typesOrdered: [],
            previewText: textValue,
            previewImageRel: nil,
            sourceBundleID: resolvedSourceApp?.bundleIdentifier,
            sourceAppName: resolvedSourceApp?.localizedName,
            sourceWindowTitle: nil,
            tags: []
        )

        var nonEmptyPayloadFound = false
        if let types = pb.types {
            for t in types {
                guard let data = pb.data(forType: t), !data.isEmpty else { continue }
                let rel = store.writeRawBlob(data, type: t.rawValue)
                item.representations[t.rawValue] = rel
                item.typesOrdered.append(t.rawValue)
                nonEmptyPayloadFound = true
            }
        }

        // 5. Empty-payload guard. Some Electron apps tick changeCount
        //    even when the user's selection produced nothing
        //    representable. previewText is the last line of defence —
        //    if even THAT is empty, the capture is junk and the
        //    caller shouldn't waste a downstream action on it.
        guard nonEmptyPayloadFound || !textValue.isEmpty else {
            return .failure(.emptyPayload)
        }

        // 6. Optional promotion. Done here (not on the call site)
        //    so the ordering — captureGeneration assigned before
        //    forceTick — stays consistent. The watcher's
        //    `ignoreNextChange` reset is defensive: an earlier flow
        //    may have armed it expecting a synthetic write, and we
        //    don't want that guard to eat our capture.
        if promoteToHistory, let watcher = watcher {
            watcher.ignoreNextChange = false
            watcher.forceTick()
        }

        let generation = Self.nextGeneration()
        return .success(Captured(
            item: item,
            sourceApp: resolvedSourceApp,
            captureGeneration: generation,
            pasteboardChangeCount: max(beforeCount, afterCount)
        ))
    }

    // MARK: Generation counter

    /// Monotonic capture counter. Wrapped on the MainActor so the
    /// service stays Sendable-friendly without `nonisolated(unsafe)`.
    /// Wraps at `Int.max` (effectively never on real hardware).
    private static var _generationCounter: Int = 0
    private static func nextGeneration() -> Int {
        _generationCounter &+= 1
        return _generationCounter
    }
}
