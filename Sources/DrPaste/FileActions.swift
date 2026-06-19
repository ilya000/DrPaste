//
//  FileActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Actions for file references. Mix of side-effect and info actions.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// Store-free recovery of file PATHS from a clip, shared across every file
/// consumer (file actions, resize, extract-image). Codex sweep — resize and
/// extract previously parsed `previewText` directly, which (a) only handled one
/// delimiter and (b) mangled paths containing commas. Prefer the REAL pasteboard
/// file references, falling back to the human-readable preview only as a last
/// resort.
///
/// Priority:
///   1. `NSFilenamesPboardType` — the full list (property-list array of paths).
///   2. A single `public.file-url` representation.
///   3. newline-/comma-separated `previewText` (legacy / transformed clips).
func clipFilePaths(_ item: ClipboardItem) -> [String] {
    func blob(_ key: String) -> Data? {
        guard let rel = item.representations[key] else { return nil }
        return try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel))
    }
    if let data = blob("NSFilenamesPboardType"),
       let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
       let paths = plist as? [String], !paths.isEmpty {
        return paths
    }
    if let data = blob("public.file-url"),
       let str = String(data: data, encoding: .utf8),
       let url = URL(string: str), url.isFileURL {
        return [url.path]
    }
    if let text = item.previewText {
        return text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    return []
}

private func fileURLs(from item: ClipboardItem, store: ClipboardStore) -> [URL] {
    clipFilePaths(item).map { URL(fileURLWithPath: $0) }
}

/// Parses `text` into the file URLs of paths that ACTUALLY EXIST on disk.
/// Used by `TextToFilesAction` — the gate is "every recovered path is real",
/// so there are never false positives (random prose with a "/" never matches).
/// Accepts newline- or comma-separated lists, `~` expansion, `file://` URLs,
/// and surrounding single/double quotes.
func existingFileURLs(fromText text: String) -> [URL] {
    let fm = FileManager.default
    let tokens: [String]
    if text.contains("\n") {
        tokens = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
    } else {
        tokens = text.split(separator: ",").map(String.init)
    }
    var urls: [URL] = []
    for raw in tokens {
        var p = raw.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { continue }
        // Strip matching surrounding quotes.
        for q in ["\"", "'"] where p.hasPrefix(q) && p.hasSuffix(q) && p.count >= 2 {
            p = String(p.dropFirst().dropLast())
        }
        // file:// URL → POSIX path.
        if p.hasPrefix("file://"), let u = URL(string: p), u.isFileURL { p = u.path }
        // ~ expansion.
        if p.hasPrefix("~") { p = (p as NSString).expandingTildeInPath }
        guard p.hasPrefix("/") else { continue }   // absolute paths only
        if fm.fileExists(atPath: p) {
            urls.append(URL(fileURLWithPath: p))
        }
    }
    return urls
}

struct FilesCopyPathsAction: ClipboardAction {
    let id = "builtin.files.copy_paths"; let title = "Copy paths"; let isLocal = true
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

/// Finder-style thumbnail via Quick Look — image content, PDF first page, app
/// icons, custom icons, Quick Look previews. nil when the file doesn't exist or
/// QL can't render one (caller falls back to the type icon). This is what makes
/// the rich-icons output match what Finder shows, instead of a generic
/// file-type glyph.
private func finderThumbnail(for url: URL, sizePt: CGFloat) async -> NSImage? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: CGSize(width: sizePt, height: sizePt),
        scale: 2,
        representationTypes: .all)
    return await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            cont.resume(returning: rep?.nsImage)
        }
    }
}

/// Type / custom-icon fallback when no Quick Look thumbnail is available.
private func fallbackFileIcon(_ url: URL) -> NSImage {
    let ws = NSWorkspace.shared
    if FileManager.default.fileExists(atPath: url.path) {
        return ws.icon(forFile: url.path)
    }
    if !url.pathExtension.isEmpty, let utType = UTType(filenameExtension: url.pathExtension) {
        return ws.icon(for: utType)
    }
    return ws.icon(for: .folder)
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
        for (idx, url) in urls.enumerated() {
            // The Finder icon is a multi-representation NSImage whose best rep
            // is huge (512 px). Embedding that as-is made the pasted icons
            // gigantic. RASTERISE it to a small 32 px bitmap (16 pt @2x — the
            // Finder small-icon size) and embed THAT via a FileWrapper
            // attachment — small source PNG, so it stays small regardless of
            // how the receiving app honours the attachment bounds. FileWrapper
            // (not `attachment.image`) is also the only form that survives RTFD
            // serialization without the `CGImageDestinationFinalize` failure.
            // Prefer the Finder-style Quick Look thumbnail (image content, PDF
            // first page, app icon, custom icons) — `icon(forFile:)` only ever
            // returns the generic file-TYPE glyph for e.g. image files, which is
            // why the icons looked wrong. Fall back to the type icon for files
            // QL can't render or that don't exist on disk.
            let entryStart = attr.length
            let icon = await finderThumbnail(for: url, sizePt: 32) ?? fallbackFileIcon(url)
            let px: CGFloat = 32
            if let small = ImageRenderer.render(size: NSSize(width: px, height: px),
                                                opaque: false,
                                                draw: { _ in
                       icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
                                 from: .zero, operation: .sourceOver, fraction: 1.0)
                   }),
               let png = ImageRenderer.pngData(from: small) {
                let wrapper = FileWrapper(regularFileWithContents: png)
                wrapper.preferredFilename = "icon-\(UUID().uuidString.prefix(8)).png"
                let attachment = NSTextAttachment(fileWrapper: wrapper)
                attachment.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
                attr.append(NSAttributedString(attachment: attachment))
            }
            attr.append(NSAttributedString(string: " \(url.lastPathComponent)",
                                           attributes: [.font: NSFont.systemFont(ofSize: 13)]))
            // Link the whole entry (icon + name) to the file so the references
            // aren't lost — pasted into Mail / Notes / Pages each row becomes a
            // clickable file:// link, not just a picture + text.
            if attr.length > entryStart {
                attr.addAttribute(.link, value: url,
                                  range: NSRange(location: entryStart, length: attr.length - entryStart))
            }
            if idx < urls.count - 1 {
                attr.append(NSAttributedString(string: "\n"))
            }
        }
        return .preview(makeRichTextItem(attr, from: item))
    }
}

// #A76 (0.58.0) — Text → Files. The inverse of "Copy paths as text": take a
// clip whose text is a list of file paths and turn it back into a real FILES
// clip (`public.file-url` + `NSFilenamesPboardType`). After committing, the
// clipboard holds actual file references — pasting into Finder/Mail drops the
// files themselves, not the path strings, and DrPaste's file actions (Reveal,
// Filenames, rich icons) light up. SAFE by construction: only paths that exist
// on disk are accepted, so it never fires on ordinary prose containing a "/".
struct TextToFilesAction: ClipboardAction {
    let id = "builtin.text.to_files"
    let title = "Text → Files"
    let isLocal = true
    let store: ClipboardStore

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard !context.contains(.files), !context.contains(.image) else { return false }
        guard context.contains(.plain) else { return false }
        guard let t = item.previewText, t.count < 8000, t.contains("/") else { return false }
        return !existingFileURLs(fromText: t).isEmpty
    }

    // Stay visible/editable in Settings for any plain-text clip — the
    // path-existence gate only governs HUD surfacing, not Settings.
    func appliesToContentType(item: ClipboardItem, context: ContentContext) -> Bool {
        !context.contains(.files) && !context.contains(.image) && context.contains(.plain)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let urls = existingFileURLs(fromText: item.previewText ?? "")
        guard !urls.isEmpty else {
            return .failed(original: item,
                           reason: "No existing file paths found in the text",
                           recovery: nil)
        }
        var copy = item
        copy.semantic = .files
        copy.previewText = urls.map { $0.path }.joined(separator: "\n")
        copy.previewImageRel = nil

        var reps: [String: String] = [:]
        var ordered: [String] = []
        // public.file-url first → SemanticClassifier sees a files clip, and
        // single-file paste targets that prefer the modern type work.
        if let first = urls.first {
            let data = Data(first.absoluteString.utf8)
            reps["public.file-url"] = store.writeRawBlob(data, type: "public.file-url")
            ordered.append("public.file-url")
        }
        // NSFilenamesPboardType (plist array) carries ALL paths — this is what
        // Finder reads to paste every file, not just the first.
        let paths = urls.map { $0.path }
        if let plist = try? PropertyListSerialization.data(fromPropertyList: paths,
                                                           format: .xml, options: 0) {
            reps["NSFilenamesPboardType"] = store.writeRawBlob(plist, type: "NSFilenamesPboardType")
            ordered.append("NSFilenamesPboardType")
        }
        copy.representations = reps
        copy.typesOrdered = ordered
        return .preview(copy)
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
            FilesRevealAction(store: store),
            TextToFilesAction(store: store)
        ]
    }
}
