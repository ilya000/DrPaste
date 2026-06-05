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
    let id = "builtin.files.copy_paths"; let title = "Copy paths as text"; let isLocal = true
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
    let id = "builtin.files.copy_filenames"; let title = "Filenames only"; let isLocal = true
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
    let id = "builtin.files.to_md_links"; let title = "Markdown links"; let isLocal = true
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
    let id = "builtin.files.reveal_in_finder"; let title = "Reveal in Finder"; let isLocal = true
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

// #A74 (0.56.0) — Copy shell-safe escaped paths. Default: single-quoted
// (`'…'`) form, which survives every special character except literal
// single quote. Multi-file → newline-separated.
struct FilesShellSafePathsAction: ClipboardAction {
    let id = "builtin.files.copy_shell_safe_paths"
    let title = "Copy shell-safe paths"
    let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        guard !urls.isEmpty else {
            return .failed(original: item, reason: "No files", recovery: nil)
        }
        let escaped = urls.map { url -> String in
            // POSIX-safe: wrap in single quotes, escape any internal
            // single quotes via the `'\''` trick.
            let p = url.path.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(p)'"
        }.joined(separator: "\n")
        return .preview(makeTextItem(escaped, from: item))
    }
}

// #A74 (0.56.0) — Generate a rich-text representation: each file rendered
// as Finder icon + filename. Pastes into Mail / Notes / Pages as a
// visually-recognisable file list rather than raw paths.
struct FilesRichRepresentationAction: ClipboardAction {
    let id = "builtin.files.to_rich_icons"
    let title = "Files as rich icons"
    let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        guard !urls.isEmpty else {
            return .failed(original: item, reason: "No files", recovery: nil)
        }
        let attr = NSMutableAttributedString()
        let ws = NSWorkspace.shared
        for (idx, url) in urls.enumerated() {
            let icon = ws.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
            attr.append(NSAttributedString(attachment: attachment))
            attr.append(NSAttributedString(string: " \(url.lastPathComponent)",
                                           attributes: [.font: NSFont.systemFont(ofSize: 13)]))
            if idx < urls.count - 1 {
                attr.append(NSAttributedString(string: "\n"))
            }
        }
        return .preview(makeRichTextItem(attr, from: item))
    }
}

enum FileActionsPack {
    static func all(store: ClipboardStore) -> [ClipboardAction] {
        [
            FilesCopyPathsAction(store: store),
            FilesFilenamesAction(store: store),
            FilesShellSafePathsAction(store: store),
            FilesMarkdownLinksAction(store: store),
            FilesRichRepresentationAction(store: store),
            FilesRevealAction(store: store)
        ]
    }
}
