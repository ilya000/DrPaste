//
//  ContentMeta.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Content metadata для HUD content meta row (Правка #15).
//  Lazy async compute + in-memory cache. Не должно тормозить — budget time 50 ms,
//  для больших inputs используется sampling-based approximation.
//

import Foundation
import AppKit

final class ContentMetaCache: @unchecked Sendable {
    static let shared = ContentMetaCache()
    private let queue = DispatchQueue(label: "DrPaste.ContentMeta", qos: .userInitiated)
    private var cache: [UUID: String] = [:]
    private let lock = NSLock()

    /// Synchronous compute — вызывается из background Task'а.
    /// Возвращает уже cache'нутое значение либо вычисляет и кеширует.
    func computeSync(for item: ClipboardItem) -> String {
        lock.lock()
        if let cached = cache[item.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = compute(item)
        lock.lock()
        cache[item.id] = result
        lock.unlock()
        return result
    }

    func invalidate(for id: UUID) {
        lock.lock()
        cache.removeValue(forKey: id)
        lock.unlock()
    }

    // MARK: compute

    private func compute(_ item: ClipboardItem) -> String {
        switch item.semantic {
        case .text, .code, .markdown:
            return computeText(item)
        case .richText:
            return computeRichText(item)
        case .url:
            return computeURL(item)
        case .email:
            return "Email · \(item.previewText ?? "?")"
        case .json:
            return computeJSON(item)
        case .table:
            return computeTable(item)
        case .image:
            return computeImage(item)
        case .pdf:
            return computePDF(item)
        case .files:
            return computeFiles(item)
        case .unknown:
            let size = item.previewText?.utf8.count ?? 0
            return "Unknown · \(formatBytes(size))"
        }
    }

    private func computeText(_ item: ClipboardItem) -> String {
        let text = item.previewText ?? ""
        let bytes = text.utf8.count
        let label = item.semantic.displayName
        if text.count < 100_000 {
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let chars = text.count
            let lines = text.components(separatedBy: .newlines).count
            return "\(label) · \(words) words · \(chars) chars · \(lines) lines"
        }
        // Большие — sample-based approximation
        let sample = text.prefix(10_000)
        let sampleWords = sample.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let estimatedWords = Int(Double(sampleWords) * Double(text.count) / Double(sample.count))
        return "\(label) · ~\(estimatedWords) words · \(formatBytes(bytes))"
    }

    private func computeRichText(_ item: ClipboardItem) -> String {
        let text = item.previewText ?? ""
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        var sizes: [Int] = [text.utf8.count]
        for type in ["public.rtf", "public.html"] {
            if let rel = item.representations[type],
               let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)) {
                sizes.append(data.count)
            }
        }
        let maxSize = sizes.max() ?? 0
        return "Rich text · \(words) words · \(formatBytes(maxSize))"
    }

    private func computeURL(_ item: ClipboardItem) -> String {
        let text = item.previewText ?? ""
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           let host = url.host {
            return "URL · \(host)"
        }
        return "URL"
    }

    private func computeJSON(_ item: ClipboardItem) -> String {
        let text = item.previewText ?? ""
        let bytes = text.utf8.count
        if bytes > 1_000_000 {
            return "JSON · large · \(formatBytes(bytes))"
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) else {
            return "JSON · invalid · \(formatBytes(bytes))"
        }
        let topLevel: Int
        if let dict = json as? [String: Any] { topLevel = dict.count }
        else if let arr = json as? [Any] { topLevel = arr.count }
        else { topLevel = 0 }
        let label = topLevel > 0
            ? "\(topLevel) \(topLevel == 1 ? "key" : "keys")"
            : "scalar"
        return "JSON · \(label) · \(formatBytes(bytes))"
    }

    private func computeTable(_ item: ClipboardItem) -> String {
        let text = item.previewText ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        let rows = lines.count
        guard let first = lines.first else { return "Table · empty" }
        let sep = first.contains("\t") ? "\t" : ","
        let cols = first.components(separatedBy: sep).count
        return "Table · \(rows) rows · \(cols) cols"
    }

    private func computeImage(_ item: ClipboardItem) -> String {
        let format = item.imageFormat ?? "Image"
        let dims: String
        if let w = item.originalImageWidth, let h = item.originalImageHeight {
            dims = "\(w) × \(h)"
        } else {
            dims = "?"
        }
        let bytes = item.originalImageFileSize.map(formatBytes) ?? "?"
        return "\(format) · \(dims) · \(bytes)"
    }

    private func computePDF(_ item: ClipboardItem) -> String {
        // Найдём PDF data, оценим pages count
        guard let rel = item.representations["com.adobe.pdf"],
              let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel))
        else {
            return "PDF"
        }
        let bytes = data.count
        // Быстрая оценка page count через CGPDFDocument
        var pages = 0
        if let provider = CGDataProvider(data: data as CFData),
           let doc = CGPDFDocument(provider) {
            pages = doc.numberOfPages
        }
        if pages > 0 {
            return "PDF · \(pages) \(pages == 1 ? "page" : "pages") · \(formatBytes(bytes))"
        }
        return "PDF · \(formatBytes(bytes))"
    }

    private func computeFiles(_ item: ClipboardItem) -> String {
        let text = item.previewText ?? ""
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let count = parts.count
        var total: Int64 = 0
        let start = Date()
        for path in parts {
            if Date().timeIntervalSince(start) > 0.05 { break }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        let label = "\(count) \(count == 1 ? "file" : "files")"
        return total > 0 ? "\(label) · \(formatBytes(Int(total))) total" : label
    }

    // MARK: helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0)) }
        return String(format: "%.2f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
    }
}
