//
//  FileActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Actions для file references (Backlog #4).
//  Side-effect и info actions.
//

import Foundation
import AppKit
import CryptoKit

private func fileURLs(from item: ClipboardItem, store: ClipboardStore) -> [URL] {
    // Из representations пробуем достать file URLs
    let candidates = ["public.file-url", "NSFilenamesPboardType"]
    for type in candidates {
        if let rel = item.representations[type],
           let data = try? Data(contentsOf: store.blobURL(rel)),
           let str = String(data: data, encoding: .utf8),
           let url = URL(string: str), url.isFileURL {
            return [url]
        }
    }
    // Fallback: парсим из previewText
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

struct FilesBashListAction: ClipboardAction {
    let id = "builtin.files_bash"; let title = "Bash-quoted list"; let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        let quoted = urls.map { "\"\($0.path)\"" }.joined(separator: " ")
        return .preview(makeTextItem(quoted, from: item))
    }
}

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

struct FilesSizeInfoAction: ClipboardAction {
    let id = "builtin.files_size"; let title = "Size info"; let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.files)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        var totalSize: Int64 = 0
        var count = 0
        for url in urls {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let sz = attrs[.size] as? Int64 {
                totalSize += sz; count += 1
            }
        }
        let mb = Double(totalSize) / 1_048_576.0
        let info = String(format: "%d files, %.2f MB total", count, mb)
        return .preview(makeTextItem(info, from: item))
    }
}

struct FilesSHA256Action: ClipboardAction {
    let id = "builtin.files_sha256"; let title = "SHA-256 hash"; let isLocal = true
    let store: ClipboardStore
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        let urls = fileURLs(from: item, store: store)
        return context.contains(.files) && urls.count == 1
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = fileURLs(from: item, store: store)
        guard let url = urls.first, let data = try? Data(contentsOf: url) else {
            return .failed(original: item, reason: "Couldn't read file", recovery: nil)
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return .preview(makeTextItem(hex, from: item))
    }
}

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
            FilesBashListAction(store: store),
            FilesMarkdownLinksAction(store: store),
            FilesSizeInfoAction(store: store),
            FilesSHA256Action(store: store),
            FilesRevealAction(store: store)
        ]
    }
}
