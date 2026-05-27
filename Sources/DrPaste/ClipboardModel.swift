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
//  ClipboardItem хранит ВСЕ representations NSPasteboard lossless,
//  плюс semantic kind для preview/actions, плюс source metadata.
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
    let id: UUID
    var semantic: SemanticKind          // human-readable классификация
    let createdAt: Date

    /// Все pasteboard representations. UTType identifier → relative path в blob storage.
    /// Это lossless raw preservation — Paste-as-is восстанавливает ВСЁ.
    var representations: [String: String]
    /// Порядок UTTypes как они были в исходном pasteboard (приоритет при write back).
    var typesOrdered: [String]

    /// Plain-text preview (snippet) для рендеринга в HUD и истории.
    /// Не payload — это derived view, может быть короче или сэмплем.
    var previewText: String?
    /// Относительный path к PNG-превью (для image / PDF kinds).
    /// Это **thumbnail** (max 600 pt, сгенерирован в PreviewSynthesizer.imageRelative).
    /// Full-size image живёт в representations[…].
    var previewImageRel: String?

    /// Image metadata (Правка #13). Заполняется при snapshot если semantic == .image.
    var originalImageWidth: Int? = nil
    var originalImageHeight: Int? = nil
    var originalImageFileSize: Int? = nil     // байт original (до thumbnail downscale)
    var imageFormat: String? = nil            // "PNG" / "TIFF" / "JPEG" / "HEIC"

    /// Source metadata — откуда скопировали.
    var sourceBundleID: String?
    var sourceAppName: String?
    var sourceWindowTitle: String?

    var tags: [String]

    /// Удобный плейн-текст getter с fallback для backwards compatibility со старыми actions.
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
        if let last = items.first, sameContent(last, item) { return }
        items.insert(item, at: 0)
        trim()
        save()
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        deleteBlobs(for: item)
        save()
    }

    func clearAll() {
        for item in items { deleteBlobs(for: item) }
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

    /// Сохраняет raw blob payload, возвращает relative path для хранения в representations.
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
        self.items = decoded
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

// MARK: - Source resolver (Backlog #1)

enum SourceResolver {
    /// Резолвит источник копирования. Bundle ID, app name, опционально window title через AX.
    static func resolve() -> (bundleID: String?, name: String?, window: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let name = app?.localizedName
        let window = windowTitle(for: app?.processIdentifier)
        return (bundleID, name, window)
    }

    /// Пытается прочитать window title через AX API. Тихо возвращает nil если AX недоступен.
    private static func windowTitle(for pid: pid_t?) -> String? {
        guard let pid = pid, AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement,
                                                   kAXFocusedWindowAttribute as CFString,
                                                   &focusedWindow)
        guard result == .success else { return nil }
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement,
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

    /// Принудительный tick — для случаев когда нужно немедленно подхватить
    /// изменение pasteboard (например после simulateCut в Backlog #9).
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

    /// Universal snapshot: проходим по всем pasteboard.types,
    /// сохраняем каждое representation в blob storage,
    /// классифицируем semantic, генерируем preview.
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
    /// Определяет наиболее информативный SemanticKind по доступным types.
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
            // Дополнительно посмотрим на string — определим markdown / code / table / url etc.
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
    /// Текстовый preview: для text/url/json/etc — нормализованная строка,
    /// для image — "Image NN KB", для files — список filenames.
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

    /// Для image — кешируем **thumbnail** (max 600 pt) PNG в imagesDir, возвращаем relative path.
    /// Full-size payload остаётся в representations[png/tiff/etc].
    /// HUD рендерит thumbnail — не nagrushает layout при больших картинках (Правка #13).
    static func imageRelative(from pasteboard: NSPasteboard,
                              semantic: SemanticKind,
                              store: ClipboardStore) -> String? {
        guard semantic == .image else { return nil }
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

    /// Image metadata (Правка #13). Используется в HUD ContentMetaRow.
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
        // Native pixel dimensions (не points)
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

    /// Lanczos-quality downscale до maxDimension pt в большей стороне.
    /// Если image уже меньше — возвращает original.
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
