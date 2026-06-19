//
//  Diagnostics.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Diagnostics snapshot (#A58). When a user reports "Type Slowly didn't
//  work" or "the HUD froze on a long AI call" there's no quick way to
//  dump runtime state. NSLog goes to Console.app, which is opaque to
//  most users. This module collects a single plain-text report and
//  Settings → General → "Copy diagnostics" writes it to the pasteboard
//  so the user can paste it into an email / GitHub issue.
//
//  Privacy: the snapshot never includes API keys, never includes the
//  contents of clipboard items beyond their semantic kind + sizes, and
//  redacts the API-key fingerprint to last-4 characters only.
//

import Foundation
import AppKit

@MainActor
enum Diagnostics {

    /// Build a Markdown-formatted diagnostics report capturing the
    /// runtime state that's most useful for triaging user-reported bugs.
    /// Designed to fit comfortably in an email or issue body — typical
    /// length 30–60 lines.
    static func snapshot(store: ClipboardStore?,
                         registry: ActionRegistry?,
                         engine: HotkeyEngine?) -> String {
        var lines: [String] = []

        // MARK: header
        lines.append("# DrPaste diagnostics")
        lines.append("")
        lines.append("- App version: \(AppBrand.version)")
        lines.append("- Build: " + buildSummary())
        lines.append("- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("- Date: \(isoNow())")
        lines.append("")

        // MARK: runtime
        lines.append("## Runtime")
        lines.append("- AX trusted: \(AXIsProcessTrusted() ? "yes" : "no")")
        if let engine = engine {
            lines.append("- BigHUD mode: \(engine.bigHUDMode == .gesture ? "Full Gesture" : "Limited (summon)")")
        } else {
            lines.append("- BigHUD mode: (engine not initialised)")
        }
        // Active surface state — best-effort inspection without depending
        // on #A42's state machines (those land later). BigHUD panel is
        // owned by AppDelegate; from this file we only know the
        // MiniHUDController.shared.isVisible flag for sure.
        if MiniHUDController.shared.isVisible {
            lines.append("- Active surface: MiniHUD visible")
        } else {
            lines.append("- Active surface: none (or BigHUD — not introspected)")
        }
        lines.append("")

        // MARK: history
        lines.append("## History")
        if let store = store {
            lines.append("- Item count: \(store.items.count)")
            let totalBytes = approxStoreBytes(store: store)
            lines.append("- Approx. total blob size: " + formatBytes(totalBytes))
            // Top 3 most recent items: kind + preview length.
            for (idx, item) in store.items.prefix(3).enumerated() {
                let kind = item.semantic.rawValue
                let previewLen = item.previewText?.count ?? 0
                let hasRaw = item.representations.isEmpty ? "no" : "yes"
                lines.append("  - [\(idx)] kind=\(kind) preview=\(previewLen) chars raw=\(hasRaw)")
            }
        } else {
            lines.append("- Store not initialised")
        }
        lines.append("")

        // MARK: actions
        lines.append("## Actions")
        if let registry = registry {
            let all = registry.actions
            lines.append("- Registered actions: \(all.count)")
            let aiCount = all.filter { $0.id.hasPrefix("ai.") || $0 is AIAction || $0 is AIImageAction || $0 is AITextToImageAction }.count
            let userCount = all.filter { $0.id.hasPrefix("user.") }.count
            let builtinCount = all.filter { $0.id.hasPrefix("builtin.") }.count
            lines.append("  - builtin: \(builtinCount)")
            lines.append("  - user.: \(userCount)")
            lines.append("  - AI (any kind): \(aiCount)")
        } else {
            lines.append("- Registry not initialised")
        }
        lines.append("")

        // MARK: providers
        lines.append("## AI Providers")
        let providers = AIProviderRegistry.shared.config.providers
        if providers.isEmpty {
            lines.append("- None configured")
        } else {
            for p in providers {
                let keyFp = redactedFingerprint(for: p.id)
                let isDefault = p.id == AIProviderRegistry.shared.config.defaultProviderID ? " (default)" : ""
                lines.append("- \(p.kind.rawValue) id=\(p.id) key=\(keyFp)\(isDefault)")
            }
        }
        lines.append("")

        // MARK: pasteboard
        lines.append("## Pasteboard")
        let pb = NSPasteboard.general
        lines.append("- changeCount: \(pb.changeCount)")
        let types = pb.types?.prefix(8).map(\.rawValue).joined(separator: ", ") ?? "(none)"
        lines.append("- top types: \(types)")
        lines.append("")

        // MARK: defaults snapshot
        lines.append("## UserDefaults (DrPaste keys)")
        let interestingKeys = [
            "drpaste.hud.fontScale",
            "drpaste.hud.cursorOnSecondOnCut",
            "drpaste.cheatSheet.disabled",
            "drpaste.theme",
            "drpaste.append.session.timeout",
            "drpaste.skipKeychain"
        ]
        for key in interestingKeys {
            let raw = UserDefaults.standard.object(forKey: key)
            let val: String
            if let raw = raw {
                val = String(describing: raw)
            } else {
                val = "(unset)"
            }
            lines.append("- \(key) = \(val)")
        }
        lines.append("")

        lines.append("_Generated by Diagnostics.snapshot() — see #A58_")
        return lines.joined(separator: "\n")
    }

    /// Copy the snapshot to the system pasteboard. Returns the report
    /// so the caller can flash a confirmation in the UI.
    @discardableResult
    static func copyToClipboard(store: ClipboardStore?,
                                registry: ActionRegistry?,
                                engine: HotkeyEngine?) -> String {
        let report = snapshot(store: store, registry: registry, engine: engine)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report, forType: .string)
        NSLog("DrPaste: copied diagnostics to clipboard (\(report.count) chars)")
        return report
    }

    /// Convenience: collect store / registry / engine through the
    /// AppDelegate singleton and copy the snapshot. Used by the
    /// Settings → Configuration "Copy diagnostics" button so the view
    /// doesn't need EnvironmentObject wiring for these app-level
    /// services.
    @discardableResult
    static func copyToClipboardViaDelegate() -> String {
        let app = NSApp.delegate as? AppDelegate
        return copyToClipboard(store: app?.store,
                               registry: app?.registry,
                               engine: app?.engine)
    }

    // MARK: helpers

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private static func buildSummary() -> String {
        // Build commit / build number aren't reliably available at
        // runtime for unsigned local builds, so report the bundle's
        // CFBundleVersion if present, else "(dev)".
        let bundle = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return bundle ?? "(dev)"
    }

    /// Sum of all on-disk blob bytes referenced by the store. Walks the
    /// representations dict on each item. Cheap enough at typical history
    /// sizes (≤ 500 items × few representations); not designed for the
    /// 10k-item edge case.
    private static func approxStoreBytes(store: ClipboardStore) -> Int {
        let fm = FileManager.default
        let blobs = AppStorage.blobsDir
        var total = 0
        for item in store.items {
            for (_, rel) in item.representations {
                let url = blobs.appendingPathComponent(rel)
                if let attrs = try? fm.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? NSNumber {
                    total += size.intValue
                }
            }
        }
        return total
    }

    private static func formatBytes(_ n: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }

    /// Redact API key down to last-4 chars (or "(unset)" / "(short)").
    /// Avoids leaking the full key into a diagnostics paste while still
    /// letting the user verify "yes, that's my key".
    private static func redactedFingerprint(for providerID: String) -> String {
        let key = APIKeyStorage.load(for: providerID) ?? ""
        if key.isEmpty { return "(unset)" }
        guard key.count >= 4 else { return "(short)" }
        return "…" + key.suffix(4)
    }
}
