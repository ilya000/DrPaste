//
//  ClipboardModel.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Universal Semantic Clipboard Layer (Backlog #1):
//  three layers — raw preservation, semantic interpretation, transformation.
//  ClipboardItem stores every NSPasteboard representation losslessly, plus a
//  semantic kind used for previews / actions, plus source metadata.
//

import Foundation
import AppKit

// MARK: - Semantic kind

enum SemanticKind: String, Codable, CaseIterable {
    case text          // plain text
    case richText      // RTF / HTML / attributedString
    case url
    case email
    case json
    case code
    case markdown
    case table         // CSV / TSV
    case image
    case pdf
    case files
    case unknown

    /// Content types surfaced as user-facing Playground tabs and as
    /// the "Applies to" checkbox grid in the Edit Action sheet.
    /// Single source of truth — SettingsWindow's TabView and
    /// ActionEditor's checkbox grid must show the same list in the
    /// same order, otherwise the user can't reason about what
    /// "Applies to" actually controls. `email` and `pdf` are
    /// classified internally (auto-detect, paste flow, etc.) but
    /// don't get their own Playground tabs — too niche to spend
    /// real estate on. `unknown` is internal-only.
    static let userVisibleKinds: [SemanticKind] = [
        .text, .richText, .url, .json, .table, .markdown, .code, .image, .files
    ]

    var displayName: String {
        switch self {
        case .text:     return "Plain text"
        case .richText: return "Rich text"
        case .url:      return "URL"
        case .email:    return "Email"
        case .json:     return "JSON"
        case .code:     return "Code"
        case .markdown: return "Markdown"
        case .table:    return "Table"
        case .image:    return "Image"
        case .pdf:      return "PDF"
        case .files:    return "Files"
        case .unknown:  return "Unknown"
        }
    }

    var sfSymbol: String {
        switch self {
        case .text:     return "text.alignleft"
        case .richText: return "doc.richtext"
        case .url:      return "link"
        case .email:    return "envelope"
        case .json:     return "curlybraces"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "text.append"
        case .table:    return "tablecells"
        case .image:    return "photo"
        case .pdf:      return "doc.fill"
        case .files:    return "doc.on.doc"
        case .unknown:  return "questionmark.square"
        }
    }
}

// MARK: - Clipboard item (Universal Semantic, Backlog #1)

struct ClipboardItem: Identifiable, Codable, Equatable {
    /// True when the item has no payload worth storing — no
    /// previewText, no image thumbnail, no pasteboard representations.
    /// Cheap purely-in-memory check (does NOT stat the on-disk blob
    /// files; if representations declares a UTType we trust the
    /// declaration). Used to filter out clipboard junk:
    ///   • Pasteboards that briefly publish a typesOrdered list but
    ///     never write payload bytes (some apps do this on focus
    ///     change to advertise their capabilities).
    ///   • Whitespace-only copies (accidental ⌘C on a blank line).
    ///   • Stale items already migrated where blob storage was
    ///     pruned but the index entry stuck around.
    var isEffectivelyEmpty: Bool {
        if let rel = previewImageRel, !rel.isEmpty { return false }
        if !representations.isEmpty { return false }
        if let text = previewText,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    let id: UUID
    var semantic: SemanticKind          // human-readable classification
    let createdAt: Date

    /// All pasteboard representations. UTType identifier → relative path in blob storage.
    /// Lossless raw preservation — Paste-as-is restores every representation.
    var representations: [String: String]
    /// UTTypes in the order they appeared in the source pasteboard (priority for write-back).
    var typesOrdered: [String]

    /// Plain-text preview snippet used by the HUD and history list. Not a
    /// payload; this is a derived view that may be shorter than the original.
    var previewText: String?
    /// Relative path to the PNG preview for image / PDF items.
    /// This is the **thumbnail** (max 600 pt, generated via
    /// PreviewSynthesizer.imageRelative). The full-size image stays in `representations`.
    var previewImageRel: String?

    /// Image metadata. Populated at snapshot time when semantic == .image.
    var originalImageWidth: Int? = nil
    var originalImageHeight: Int? = nil
    var originalImageFileSize: Int? = nil     // bytes of the original before thumbnail downscale
    var imageFormat: String? = nil            // "PNG" / "TIFF" / "JPEG" / "HEIC"

    /// Source metadata — where the item was copied from.
    var sourceBundleID: String?
    var sourceAppName: String?
    var sourceWindowTitle: String?

    var tags: [String]

    /// SHA-256 hex of the largest pasteboard representation (for
    /// image / files items) or the previewText UTF-8 bytes (for
    /// text / rich-text items). Optional Codable field — nil for
    /// items written by versions before 0.50.0; lazy-computed on
    /// first comparison in `ClipboardStore.sameContent` and
    /// backfilled into the store.
    ///
    /// Why: until 0.50.0 image dedup compared `previewImageRel`,
    /// which is a UUID generated per write. Two screenshots of
    /// the same window taken seconds apart would land as separate
    /// history rows even though their bytes are identical. Hash
    /// based dedup catches the case. Same logic dedups large
    /// text copies (5MB Markdown paste twice).
    var contentHash: String? = nil

    /// Convenience plain-text getter kept for backward compatibility with older actions.
    var text: String? {
        get { previewText }
        set { previewText = newValue }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Storage paths

enum AppStorage {
    static var dataDir: URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
        let dir = appSupport.appendingPathComponent("DrPaste", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var imagesDir: URL {
        let dir = dataDir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var blobsDir: URL {
        let dir = dataDir.appendingPathComponent("blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Store

final class ClipboardStore: ObservableObject {

    @Published private(set) var items: [ClipboardItem] = []

    private let indexURL: URL
    private let imagesDir: URL
    private let blobsDir: URL
    private let maxItems: Int

    init(maxItems: Int = 500) {
        self.maxItems = maxItems
        self.imagesDir = AppStorage.imagesDir
        self.blobsDir = AppStorage.blobsDir
        self.indexURL = AppStorage.dataDir.appendingPathComponent("index.json")
        load()
    }

    func add(_ item: ClipboardItem) {
        // Drop empty clips at the source — no point recording a
        // pasteboard change that didn't carry any actual payload
        // (apps that advertise types on focus change but never
        // write bytes, accidental ⌘C on a blank selection, etc.).
        if item.isEffectivelyEmpty { return }
        // Auto-compute contentHash on inbound items so the next
        // sameContent comparison can use it (#A52). Old items
        // already in history may carry nil contentHash; the
        // sameContent path falls back to the previous comparison
        // logic in that case.
        var withHash = item
        if withHash.contentHash == nil {
            withHash.contentHash = ClipboardItem.computeContentHash(for: withHash,
                                                                    blobsDir: blobsDir)
        }
        if let last = items.first, sameContent(last, withHash) { return }
        items.insert(withHash, at: 0)
        trim()
        save()
    }

    /// Inserts a synthetic clip at the given index without de-duplication.
    /// Used by the ⌥⌘C "promote preview to history" flow so the user can
    /// chain further transformations on a freshly-computed preview without
    /// it being silently dropped if its content happens to match the
    /// top-of-history clip.
    func insertSnapshot(_ item: ClipboardItem, at index: Int) {
        // Same empty-clip guard as `add`: a promoted preview that
        // resolved to empty text / no image isn't worth a history
        // row either.
        if item.isEffectivelyEmpty { return }
        let clamped = max(0, min(index, items.count))
        items.insert(item, at: clamped)
        trim()
        save()
    }

    /// #A11 — insert a captured PNG image at the top of history without
    /// going through the pasteboard. Used by ScreenRegionCaptureController
    /// after the user finishes a ⌥⌘+drag selection. Returns the new
    /// ClipboardItem so the caller can open the BigHUD focused on it.
    ///
    /// `sourceApp` is the NSRunningApplication whose window was topmost
    /// under the selection rectangle — populated when known (we cache
    /// `savedFrontmostApp` at gesture start in AppDelegate) so the HUD's
    /// "Captured from <app>" source label can render.
    @discardableResult
    func addCapturedImage(pngData: Data,
                          width: Int,
                          height: Int,
                          sourceApp: NSRunningApplication?) -> ClipboardItem? {
        guard let rel = writeImageData(pngData) else { return nil }
        // Persist a copy of the raw PNG as a public.png representation
        // too, so Paste-as-is can hand the bytes to the receiving app
        // (otherwise we'd only have the thumbnail).
        let blobRel = writeRawBlob(pngData, type: "public.png")
        let item = ClipboardItem(
            id: UUID(),
            semantic: .image,
            createdAt: Date(),
            representations: ["public.png": blobRel],
            typesOrdered: ["public.png"],
            previewText: nil,
            previewImageRel: rel,
            originalImageWidth: width,
            originalImageHeight: height,
            originalImageFileSize: pngData.count,
            imageFormat: "PNG",
            sourceBundleID: sourceApp?.bundleIdentifier,
            sourceAppName: sourceApp?.localizedName,
            sourceWindowTitle: nil,
            tags: []
        )
        // insertSnapshot bypasses the sameContent de-dup check — two
        // back-to-back captures of the same region should both land in
        // history rather than the second silently merging into the first.
        insertSnapshot(item, at: 0)
        return item
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        deleteBlobs(for: item)
        RichTextImageExtractor.invalidate(id)
        save()
    }

    func clearAll() {
        for item in items {
            deleteBlobs(for: item)
            RichTextImageExtractor.invalidate(item.id)
        }
        items.removeAll()
        save()
    }

    func image(for item: ClipboardItem) -> NSImage? {
        if let rel = item.previewImageRel {
            return NSImage(contentsOf: imagesDir.appendingPathComponent(rel))
        }
        // fallback: try to get from raw representations
        let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
        for type in imageTypes {
            if let rel = item.representations[type],
               let data = try? Data(contentsOf: blobURL(rel)),
               let img = NSImage(data: data) {
                return img
            }
        }
        return nil
    }

    /// Writes a raw blob payload and returns its relative path for storage in `representations`.
    func writeRawBlob(_ data: Data, type: String) -> String {
        let safeName = type.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        let rel = "\(UUID().uuidString)-\(safeName).bin"
        let url = blobsDir.appendingPathComponent(rel)
        try? data.write(to: url)
        return rel
    }

    func blobURL(_ rel: String) -> URL {
        blobsDir.appendingPathComponent(rel)
    }

    func writeImageData(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).png"
        let url = imagesDir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            return nil
        }
    }

    // MARK: persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("DrPaste save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }
        // Curative cleanup on launch — drop any empty clips that
        // slipped into earlier index versions before `add()` /
        // `insertSnapshot()` learned to filter them. Save only if
        // we actually pruned something so quiet starts don't
        // re-write the index on every launch.
        let filtered = decoded.filter { !$0.isEffectivelyEmpty }
        self.items = filtered
        if filtered.count != decoded.count {
            save()
        }
    }

    private func trim() {
        guard items.count > maxItems else { return }
        let extras = items.suffix(items.count - maxItems)
        for item in extras { deleteBlobs(for: item) }
        items = Array(items.prefix(maxItems))
    }

    private func deleteBlobs(for item: ClipboardItem) {
        if let rel = item.previewImageRel {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(rel))
        }
        for (_, rel) in item.representations {
            try? FileManager.default.removeItem(at: blobsDir.appendingPathComponent(rel))
        }
    }

    private func sameContent(_ a: ClipboardItem, _ b: ClipboardItem) -> Bool {
        guard a.semantic == b.semantic else { return false }
        // Prefer hash-based comparison when both items carry a
        // `contentHash`. This catches "two copies of the same image
        // bytes that were written under different blob filenames"
        // (#A52, shipped 0.50.0). The previous comparison fell
        // through to `previewImageRel == previewImageRel`, which is
        // a UUID per write — so identical screenshots taken
        // seconds apart never deduped. Hash-match is authoritative
        // when present; only fall back to previous-version
        // representation matching when contentHash is missing
        // (saved items written before 0.50.0 may not have the field).
        if let ha = a.contentHash, let hb = b.contentHash, !ha.isEmpty, !hb.isEmpty {
            return ha == hb
        }
        switch a.semantic {
        case .image:
            return a.previewImageRel == b.previewImageRel
        case .files:
            return a.representations["public.file-url"] == b.representations["public.file-url"]
        default:
            return a.previewText == b.previewText
        }
    }
}

// MARK: - Content hashing (Backlog #A52)

import CryptoKit

extension ClipboardItem {
    /// Computes (if missing) and returns the SHA-256 hash of the
    /// largest representation blob (for image / files items) or the
    /// previewText UTF-8 bytes (for text-like items). Idempotent;
    /// callers can invoke during snapshot creation, and store
    /// rehydration paths can backfill.
    ///
    /// Synchronous file read — call from background queue when
    /// item carries large representations (Excel TSV + HTML + RTF
    /// across multiple blobs).
    static func computeContentHash(for item: ClipboardItem,
                                   blobsDir: URL) -> String? {
        // Pick the largest representation blob; for text-only
        // items the previewText is the canonical content.
        if !item.representations.isEmpty {
            var largest: (rel: String, size: Int)? = nil
            for (_, rel) in item.representations {
                let url = blobsDir.appendingPathComponent(rel)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int {
                    if size > (largest?.size ?? 0) {
                        largest = (rel: rel, size: size)
                    }
                }
            }
            if let l = largest,
               let data = try? Data(contentsOf: blobsDir.appendingPathComponent(l.rel)) {
                let digest = SHA256.hash(data: data)
                return digest.map { String(format: "%02x", $0) }.joined()
            }
        }
        if let text = item.previewText, !text.isEmpty {
            let data = Data(text.utf8)
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }
}

// MARK: - Source resolver (Backlog #1)

enum SourceResolver {
    /// Resolves the copy source: bundle ID, app name, optionally window title via AX.
    static func resolve() -> (bundleID: String?, name: String?, window: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let name = app?.localizedName
        let window = windowTitle(for: app?.processIdentifier)
        return (bundleID, name, window)
    }

    /// Tries to read the focused window title via the AX API. Returns nil silently when AX is unavailable.
    private static func windowTitle(for pid: pid_t?) -> String? {
        guard let pid = pid, AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement,
                                                   kAXFocusedWindowAttribute as CFString,
                                                   &focusedWindow)
        guard result == .success, let focused = focusedWindow else { return nil }
        // AX returns a CFTypeRef whose dynamic type is documented to be
        // AXUIElement when the attribute is kAXFocusedWindowAttribute,
        // but `as!` is still a foot-gun if the platform ever returns
        // something else (private-frameworks, third-party AX shims,
        // future macOS). Verify via CFGetTypeID before the bridge cast
        // — that way an unexpected dynamic type silently returns nil
        // instead of crashing.
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let window = focused as! AXUIElement
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window,
                                      kAXTitleAttribute as CFString,
                                      &titleRef)
        return titleRef as? String
    }
}

// MARK: - Watcher (Universal Semantic snapshot)

final class ClipboardWatcher {

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let store: ClipboardStore
    var ignoreNextChange: Bool = false

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Forced tick — used when a pasteboard change must be picked up
    /// immediately (for example right after simulateCut).
    func forceTick() { tick() }

    private func tick() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        if let item = snapshotPasteboard() {
            store.add(item)
        }
    }

    /// Universal snapshot: walks every pasteboard.type, saves each
    /// representation to blob storage, classifies the semantic kind, and
    /// generates a preview.
    private func snapshotPasteboard() -> ClipboardItem? {
        guard let types = pasteboard.types, !types.isEmpty else { return nil }

        var representations: [String: String] = [:]
        var ordered: [String] = []

        for t in types {
            guard let data = pasteboard.data(forType: t) else { continue }
            let rel = store.writeRawBlob(data, type: t.rawValue)
            representations[t.rawValue] = rel
            ordered.append(t.rawValue)
        }

        guard !representations.isEmpty else { return nil }

        let semantic = SemanticClassifier.classify(types: ordered, pasteboard: pasteboard)
        let previewText = PreviewSynthesizer.text(from: pasteboard, semantic: semantic)
        let previewImage = PreviewSynthesizer.imageRelative(from: pasteboard,
                                                           semantic: semantic,
                                                           store: store)
        let src = SourceResolver.resolve()

        let imgMeta = semantic == .image
            ? PreviewSynthesizer.imageMetadata(from: pasteboard)
            : (width: nil, height: nil, fileSize: nil, format: nil)

        return ClipboardItem(
            id: UUID(),
            semantic: semantic,
            createdAt: Date(),
            representations: representations,
            typesOrdered: ordered,
            previewText: previewText,
            previewImageRel: previewImage,
            originalImageWidth: imgMeta.width,
            originalImageHeight: imgMeta.height,
            originalImageFileSize: imgMeta.fileSize,
            imageFormat: imgMeta.format,
            sourceBundleID: src.bundleID,
            sourceAppName: src.name,
            sourceWindowTitle: src.window,
            tags: []
        )
    }
}

// MARK: - Semantic classifier

enum SemanticClassifier {
    /// Picks the most informative SemanticKind from the available pasteboard types.
    static func classify(types: [String], pasteboard: NSPasteboard) -> SemanticKind {
        let typeSet = Set(types)

        // File references
        if typeSet.contains("public.file-url") {
            return .files
        }
        // Image
        let imageTypes: Set<String> = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
        if !typeSet.isDisjoint(with: imageTypes) {
            return .image
        }
        // PDF
        if typeSet.contains("com.adobe.pdf") {
            return .pdf
        }
        // Rich text
        if typeSet.contains("public.rtf") || typeSet.contains("public.html") {
            // Also inspect the string payload to refine the classification (markdown / code / table / url, etc.).
            if let s = pasteboard.string(forType: .string) {
                let textKind = classifyText(s)
                if textKind == .text { return .richText }
                return textKind == .url || textKind == .json ? textKind : .richText
            }
            return .richText
        }
        // Plain text — sub-classify
        if let s = pasteboard.string(forType: .string) {
            return classifyText(s)
        }
        return .unknown
    }

    static func classifyText(_ raw: String) -> SemanticKind {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .text }

        // URL
        if let _ = URL(string: s),
           s.range(of: #"^https?://"#, options: .regularExpression) != nil {
            return .url
        }
        // Email
        if s.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#,
                   options: .regularExpression) != nil {
            return .email
        }
        // JSON
        if let data = s.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])) != nil,
           (s.first == "{" || s.first == "[") {
            return .json
        }
        // Markdown
        let mdMarkers = ["# ", "## ", "* ", "- ", "```", "[", "]("]
        if mdMarkers.contains(where: { s.contains($0) }) && s.contains("\n") {
            return .markdown
        }
        // Code
        let codeKW = ["function ", "def ", "class ", "import ", "let ", "var ", "const ",
                      "func ", "public ", "private ", "if (", "for (", "return ", "=>"]
        let hasCodePunct = (s.contains("{") && s.contains("}")) || s.contains(";")
        let hasCodeKW = codeKW.contains(where: { s.contains($0) })
        if hasCodePunct || hasCodeKW { return .code }
        // Table (CSV/TSV)
        let lines = s.split(separator: "\n").map(String.init)
        if lines.count >= 2 {
            for sep in ["\t", ",", ";"] {
                let counts = lines.map { $0.components(separatedBy: sep).count }
                if let first = counts.first, first >= 2, counts.allSatisfy({ $0 == first }) {
                    return .table
                }
            }
        }
        return .text
    }
}

// MARK: - Preview synthesizer

enum PreviewSynthesizer {
    /// Text preview: for text / url / json / etc. returns the normalized string;
    /// for image returns "Image NN KB"; for files returns a list of filenames.
    static func text(from pasteboard: NSPasteboard, semantic: SemanticKind) -> String? {
        switch semantic {
        case .image:
            if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
                return "Image \(data.count / 1024) KB"
            }
            return "Image"
        case .pdf:
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("com.adobe.pdf")) {
                return "PDF \(data.count / 1024) KB"
            }
            return "PDF"
        case .files:
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                return urls.map { $0.lastPathComponent }.joined(separator: ", ")
            }
            return nil
        default:
            return pasteboard.string(forType: .string)
        }
    }

    /// For images / PDFs: caches a **thumbnail** (max 600 pt) PNG in imagesDir
    /// and returns its relative path. The full-size payload stays in
    /// `representations[png/tiff/com.adobe.pdf/etc]`. The HUD renders the
    /// thumbnail so layout stays smooth even on very large source assets.
    static func imageRelative(from pasteboard: NSPasteboard,
                              semantic: SemanticKind,
                              store: ClipboardStore) -> String? {
        switch semantic {
        case .image:
            return imageThumbnail(from: pasteboard, store: store)
        case .pdf:
            return pdfThumbnail(from: pasteboard, store: store)
        default:
            return nil
        }
    }

    /// Renders a raster thumbnail from any PNG / TIFF the pasteboard provided.
    private static func imageThumbnail(from pasteboard: NSPasteboard,
                                       store: ClipboardStore) -> String? {
        let imgData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        guard let data = imgData else { return nil }
        let fullImage = NSImage(data: data) ?? NSImage()
        let thumb = makeThumbnail(fullImage, maxDimension: 600)
        let png: Data?
        if let tiff = thumb.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngRep = bitmap.representation(using: .png, properties: [:]) {
            png = pngRep
        } else {
            png = data
        }
        guard let pngData = png else { return nil }
        return store.writeImageData(pngData)
    }

    /// Renders the first page of a clipboard PDF into a PNG thumbnail (≤600 pt
    /// on the larger side, white background) and caches it in imagesDir. Used
    /// by the HUD preview pane so PDFs surface as a real page image instead of
    /// the generic "PDF NN KB" placeholder.
    private static func pdfThumbnail(from pasteboard: NSPasteboard,
                                     store: ClipboardStore) -> String? {
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType("com.adobe.pdf"))
        else { return nil }
        return renderPDFFirstPage(data: data, store: store)
    }

    /// Decodes a PDF blob, draws the first page into a fresh NSBitmapImageRep,
    /// encodes as PNG, and writes it to `store.imagesDir`. Returns the relative
    /// filename (suitable for `ClipboardItem.previewImageRel`) or nil on failure.
    static func renderPDFFirstPage(data: Data, store: ClipboardStore) -> String? {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider),
              let page = doc.page(at: 1)
        else { return nil }

        let pageRect = page.getBoxRect(.cropBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        // Scale so the larger side fits within 600 pt.
        let maxSide: CGFloat = 600
        let scale = min(maxSide / pageRect.width, maxSide / pageRect.height, 2.0)
        let targetSize = CGSize(width: pageRect.width * scale,
                                height: pageRect.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil,
                                  width: Int(targetSize.width),
                                  height: Int(targetSize.height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo)
        else { return nil }

        // White page background — most PDFs assume white paper.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pageRect.origin.x, y: -pageRect.origin.y)
        ctx.drawPDFPage(page)

        guard let cg = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return store.writeImageData(png)
    }

    /// Image metadata. Used by the HUD ContentMetaRow.
    static func imageMetadata(from pasteboard: NSPasteboard)
        -> (width: Int?, height: Int?, fileSize: Int?, format: String?)
    {
        let format: String
        let data: Data?
        if let d = pasteboard.data(forType: .png) { data = d; format = "PNG" }
        else if let d = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) { data = d; format = "JPEG" }
        else if let d = pasteboard.data(forType: NSPasteboard.PasteboardType("public.heic")) { data = d; format = "HEIC" }
        else if let d = pasteboard.data(forType: .tiff) { data = d; format = "TIFF" }
        else { return (nil, nil, nil, nil) }

        guard let imgData = data, let img = NSImage(data: imgData) else {
            return (nil, nil, nil, nil)
        }
        // Native pixel dimensions, not points.
        var width: Int? = nil
        var height: Int? = nil
        if let rep = img.representations.first as? NSBitmapImageRep {
            width = rep.pixelsWide
            height = rep.pixelsHigh
        } else {
            width = Int(img.size.width)
            height = Int(img.size.height)
        }
        return (width, height, imgData.count, format)
    }

    /// Lanczos-quality downscale so the larger side fits within maxDimension pt.
    /// Returns the original image if it is already smaller.
    static func makeThumbnail(_ source: NSImage, maxDimension: CGFloat) -> NSImage {
        let originalSize = source.size
        guard originalSize.width > 0, originalSize.height > 0 else { return source }
        let scale = min(maxDimension / originalSize.width,
                        maxDimension / originalSize.height,
                        1.0)
        if scale >= 1.0 { return source }
        let newSize = NSSize(width: originalSize.width * scale,
                             height: originalSize.height * scale)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: newSize),
                    from: .zero, operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}
