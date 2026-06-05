//
//  BlobGC.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Orphan blob garbage collection (#A53). Between `writeRawBlob` and
//  `ClipboardStore.save`, a crash (forced quit, panic, signal) can
//  leave PNG / RTFD / raw payload files on disk that nothing in
//  `index.json` references. Deleted history items and replaced
//  CustomTransformationDescriptor testSamples also drop their blobs
//  without cleanup. Without periodic GC, Application Support grows
//  monotonically — especially painful on Dropbox-resident
//  Application Support where every orphan also syncs.
//
//  Strategy (on-launch, debounced):
//    1. Walk `index.json` items → collect every referenced blob
//       relative path from `representations.values` + `previewImageRel`.
//    2. Walk `actions.json` user.* descriptors → collect every
//       `actionTestSamples` rel.
//    3. Walk `blobs/` and `images/` directories. Anything not in the
//       reference set AND older than 24 hours → delete.
//
//  The 24-hour grace window protects against a race where the
//  pasteboard wrote a blob seconds before the index save fired and the
//  walk happens between them — the file is real, just not indexed yet.
//
//  Runs once per launch via `runIfDue` (with a 12-hour debounce in
//  UserDefaults so a user who relaunches DrPaste 5 times an hour
//  doesn't pay the IO cost 5 times). NSLog summary at completion so
//  the run is visible in Console.app for diagnostics.
//

import Foundation
import AppKit

@MainActor
enum BlobGC {

    /// UserDefaults key for the last-run timestamp. Bare `Double` of
    /// `timeIntervalSinceReferenceDate`.
    private static let lastRunKey = "drpaste.blobGC.lastRun"

    /// Minimum interval between runs. 12 hours strikes a balance:
    /// fresh enough that a crash + relaunch cycle the same day still
    /// cleans up, sparing enough that the IO walk doesn't fire on
    /// every quick relaunch.
    private static let debounceInterval: TimeInterval = 12 * 60 * 60

    /// Grace window before a blob is eligible for deletion. Protects
    /// against the index-save race described in the file header.
    /// `nonisolated` because `sweepUnreferenced` reads it off the main
    /// actor — it's an immutable Sendable constant, so this is safe.
    nonisolated private static let graceWindow: TimeInterval = 24 * 60 * 60

    /// Run the GC if the last run is more than `debounceInterval` ago,
    /// or has never run. Idempotent within the debounce window.
    /// Off-main because directory walks are I/O-bound.
    static func runIfDue() {
        let now = Date()
        let lastRun = UserDefaults.standard.double(forKey: lastRunKey)
        let lastRunDate = Date(timeIntervalSinceReferenceDate: lastRun)
        guard lastRun == 0 || now.timeIntervalSince(lastRunDate) > debounceInterval else {
            return
        }
        // Capture the reference sets on the main actor (they read
        // ObservableObject state), then hand them off to a detached
        // task for the filesystem walk + deletion.
        let referenced = collectReferencedBlobs()
        Task.detached(priority: .background) {
            let summary = sweepUnreferenced(referenced: referenced, now: now)
            await MainActor.run {
                UserDefaults.standard.set(now.timeIntervalSinceReferenceDate,
                                          forKey: lastRunKey)
                NSLog("DrPaste BlobGC: %@", summary.description)
            }
        }
    }

    /// Collect the set of blob relative paths currently referenced by
    /// in-memory state. MainActor — touches the AppDelegate's store +
    /// registry. Returns a Set for O(1) "is referenced?" lookups
    /// during the sweep.
    ///
    /// Accumulator state is intentionally NOT scanned here — any blob
    /// it just wrote is < 24 h old and the grace window will protect
    /// it on this sweep. By the time the next sweep runs (12 h later
    /// minimum), accumulator blobs that ended up in history are
    /// referenced through `store.items`; blobs that didn't are real
    /// orphans and get cleaned up.
    private static func collectReferencedBlobs() -> Set<String> {
        var refs = Set<String>()
        guard let app = NSApp.delegate as? AppDelegate else { return refs }

        // History items: representations + thumbnail.
        for item in app.store.items {
            for (_, rel) in item.representations { refs.insert(rel) }
            if let preview = item.previewImageRel { refs.insert(preview) }
        }

        // Action test inputs — every CustomTransformationDescriptor /
        // CustomAIDescriptor may carry a persisted test image whose
        // blob lives in `images/` (per-action override). Same for
        // the Playground's per-tab image override.
        let cfg = app.registry.config
        for (_, sampleRel) in cfg.actionTestImageBlobs { refs.insert(sampleRel) }
        for (_, sampleRel) in cfg.playgroundImageBlobs { refs.insert(sampleRel) }

        return refs
    }

    /// Walk `blobs/` and `images/`, delete anything not in `referenced`
    /// and older than `graceWindow`. Returns a summary record for
    /// NSLog. Runs on background; does not touch any actor.
    nonisolated private static func sweepUnreferenced(
        referenced: Set<String>,
        now: Date
    ) -> Summary {
        let fm = FileManager.default
        let dirs = [AppStorage.blobsDir, AppStorage.imagesDir]
        var deleted = 0
        var bytesFreed: Int64 = 0
        var scanned = 0
        var skippedGrace = 0
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(at: dir,
                                                            includingPropertiesForKeys:
                                                                [.contentModificationDateKey, .fileSizeKey],
                                                            options: [.skipsHiddenFiles])
            else { continue }
            for url in entries {
                scanned += 1
                let rel = url.lastPathComponent
                if referenced.contains(rel) { continue }
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let mtime = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                let age = now.timeIntervalSince(mtime)
                if age < graceWindow {
                    skippedGrace += 1
                    continue
                }
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                do {
                    try fm.removeItem(at: url)
                    deleted += 1
                    bytesFreed += size
                } catch {
                    // Best effort — log but don't bail; one stuck file
                    // shouldn't prevent the rest of the sweep.
                    NSLog("DrPaste BlobGC: couldn't delete %@: %@",
                          url.path, error.localizedDescription)
                }
            }
        }
        return Summary(scanned: scanned,
                       deleted: deleted,
                       bytesFreed: bytesFreed,
                       skippedGrace: skippedGrace)
    }

    struct Summary {
        let scanned: Int
        let deleted: Int
        let bytesFreed: Int64
        let skippedGrace: Int

        var description: String {
            let mb = Double(bytesFreed) / 1_048_576
            return "scanned=\(scanned) deleted=\(deleted) " +
                   String(format: "freed=%.1fMB", mb) +
                   " in-grace=\(skippedGrace)"
        }
    }
}
