//
//  FileActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Actions for file references. Mix of side-effect and info actions.
//

import Foundation
import AppKit

private func fileURLs(from item: ClipboardItem, store: ClipboardStore) -> [URL] {
    // Try to recover file URLs from the saved representations first.
    let candidates = ["public.file-url", "NSFilenamesPboardType"]
    for type in candidates {
        if let rel = item.representations[type],
           let data = try? Data(contentsOf: store.blobURL(rel)),
           let str = String(data: data, encoding: .utf8),
           let url = URL(string: str), url.isFileURL {
            return [url]
        }
    }
    // Fallback: parse comma-separated paths from previewText.
    if let text = item.previewText {
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }
    return []
}

struct FilesCopyPathsAction: ClipboardAction {
    let id = "builtin.files_paths"; let title = "Copy paths as text"; let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        guard !urls.isEmpty else { return .failed(original: item, reason: "No file references", recovery: nil) }
        let text = urls.map { $0.path }.joined(separator: "\n")
        return .preview(makeTextItem(text, from: item))
    }
}

struct FilesFilenamesAction: ClipboardAction {
    let id = "builtin.files_names"; let title = "Filenames only"; let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        let names = urls.map { $0.lastPathComponent }.joined(separator: "\n")
        return .preview(makeTextItem(names, from: item))
    }
}

// FilesBashListAction (Bash-quoted list) removed in 0.12.0 — niche dev tool
// (pasting file paths into `cp`/`mv`); zero marketing weight.

struct FilesMarkdownLinksAction: ClipboardAction {
    let id = "builtin.files_md_links"; let title = "Markdown links"; let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        let links = urls.map { "[\($0.lastPathComponent)](\($0.absoluteString))" }
            .joined(separator: "\n")
        return .preview(makeTextItem(links, from: item))
    }
}

// FilesSizeInfoAction (Size info) and FilesSHA256Action (SHA-256 hash)
// removed in 0.12.0 — both were niche file-introspection actions with no
// marketing weight. Anyone who needs them can recover via macOS Finder Quick
// Actions / Shortcuts / shell. Leaving the IDs `builtin.files_size` and
// `builtin.files_sha256` orphan in any existing user config is harmless:
// `pruneOrphanedActionHotkeys` drops their hotkeys on next launch, and the
// HUD never surfaces an action whose registration is gone.

struct FilesRevealAction: ClipboardAction {
    let id = "builtin.files_reveal"; let title = "Reveal in Finder"; let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        guard !urls.isEmpty else { return .failed(original: item, reason: "No files", recovery: nil) }
        let desc = "Will reveal \(urls.count) item(s) in Finder"
        return .sideEffect(description: desc) {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

enum FileActionsPack {
    static func all(store: ClipboardStore) -> [ClipboardAction] {
        [
            FilesCopyPathsAction(store: store),
            FilesFilenamesAction(store: store),
            FilesMarkdownLinksAction(store: store),
            FilesRevealAction(store: store)
        ]
    }
}
