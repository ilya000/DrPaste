//
//  TextActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Local actions для plain text (Backlog #4).
//  Включает ★ Generate QR — text → image через CIQRCodeGenerator.
//

import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Case transformations

struct TitleCaseAction: ClipboardAction {
    let id = "builtin.title_case"
    let title = "Title Case"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let s = (item.previewText ?? "").capitalized
        return .preview(makeTextItem(s, from: item))
    }
}

struct SentenceCaseAction: ClipboardAction {
    let id = "builtin.sentence_case"
    let title = "Sentence case"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let s = item.previewText ?? ""
        let lower = s.lowercased()
        var out = ""
        var capitalizeNext = true
        for ch in lower {
            if capitalizeNext, ch.isLetter {
                out.append(Character(ch.uppercased()))
                capitalizeNext = false
            } else {
                out.append(ch)
                if ch == "." || ch == "!" || ch == "?" { capitalizeNext = true }
            }
        }
        return .preview(makeTextItem(out, from: item))
    }
}

struct CamelCaseAction: ClipboardAction {
    let id = "builtin.camel_case"
    let title = "camelCase"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let parts = (item.previewText ?? "")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !parts.isEmpty else { return .preview(item) }
        let first = parts[0].lowercased()
        let rest = parts.dropFirst().map { $0.lowercased().capitalized }
        return .preview(makeTextItem(first + rest.joined(), from: item))
    }
}

struct SnakeCaseAction: ClipboardAction {
    let id = "builtin.snake_case"
    let title = "snake_case"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let parts = (item.previewText ?? "").split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
        return .preview(makeTextItem(parts.joined(separator: "_"), from: item))
    }
}

struct KebabCaseAction: ClipboardAction {
    let id = "builtin.kebab_case"
    let title = "kebab-case"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let parts = (item.previewText ?? "").split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
        return .preview(makeTextItem(parts.joined(separator: "-"), from: item))
    }
}

// MARK: - Line operations

struct SortLinesAction: ClipboardAction {
    let id = "builtin.sort_lines"
    let title = "Sort lines"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.multiline)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let sorted = (item.previewText ?? "").split(separator: "\n").sorted().joined(separator: "\n")
        return .preview(makeTextItem(sorted, from: item))
    }
}

struct UniqueLinesAction: ClipboardAction {
    let id = "builtin.unique_lines"
    let title = "Unique lines"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.multiline)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        var seen = Set<String>()
        var result: [String] = []
        for line in (item.previewText ?? "").split(separator: "\n").map(String.init) {
            if !seen.contains(line) { seen.insert(line); result.append(line) }
        }
        return .preview(makeTextItem(result.joined(separator: "\n"), from: item))
    }
}

// MARK: - Encoding

struct Base64EncodeAction: ClipboardAction {
    let id = "builtin.base64_encode"
    let title = "Base64 encode"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let data = (item.previewText ?? "").data(using: .utf8) else { return .preview(item) }
        return .preview(makeTextItem(data.base64EncodedString(), from: item))
    }
}

struct Base64DecodeAction: ClipboardAction {
    let id = "builtin.base64_decode"
    let title = "Base64 decode"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard context.contains(.plain), let s = item.previewText else { return false }
        return Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let s = (item.previewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: s), let decoded = String(data: data, encoding: .utf8) else {
            return .failed(original: item, reason: "Not valid base64", recovery: nil)
        }
        return .preview(makeTextItem(decoded, from: item))
    }
}

struct URLEncodeAction: ClipboardAction {
    let id = "builtin.url_encode"
    let title = "URL encode"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let encoded = (item.previewText ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return .preview(makeTextItem(encoded, from: item))
    }
}

struct URLDecodeAction: ClipboardAction {
    let id = "builtin.url_decode"
    let title = "URL decode"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain) && (item.previewText ?? "").contains("%")
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let decoded = (item.previewText ?? "").removingPercentEncoding ?? (item.previewText ?? "")
        return .preview(makeTextItem(decoded, from: item))
    }
}

struct SlugifyAction: ClipboardAction {
    let id = "builtin.slugify"
    let title = "Slugify"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let s = (item.previewText ?? "").lowercased()
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? ""
        let parts = s.split { !$0.isLetter && !$0.isNumber }
        return .preview(makeTextItem(parts.joined(separator: "-"), from: item))
    }
}

// MARK: - Info

struct WordCountAction: ClipboardAction {
    let id = "builtin.word_count"
    let title = "Word / char count"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.plain)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let s = item.previewText ?? ""
        let words = s.split { $0.isWhitespace }.count
        let chars = s.count
        let lines = s.split(separator: "\n").count
        let info = "\(words) words, \(chars) characters, \(lines) lines"
        return .preview(makeTextItem(info, from: item))
    }
}

// MARK: - ★ Generate QR (highlight feature, Backlog #4)

struct GenerateQRAction: ClipboardAction {
    let id = "builtin.generate_qr"
    let title = "Generate QR code"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.qrEligible)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let text = item.previewText, !text.isEmpty,
              let data = text.data(using: .utf8) else {
            return .failed(original: item, reason: "Empty text", recovery: nil)
        }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else {
            return .failed(original: item, reason: "QR generation failed", recovery: nil)
        }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        // Сохраняем PNG в imagesDir и возвращаем item с обновлённым previewImageRel
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return .failed(original: item, reason: "QR encoding failed", recovery: nil)
        }
        let name = "\(UUID().uuidString)-qr.png"
        let url = AppStorage.imagesDir.appendingPathComponent(name)
        try? png.write(to: url)

        var copy = item
        copy.semantic = .image
        copy.previewText = "QR (\(text.count) chars)"
        copy.previewImageRel = name
        // Полный raw представления: PNG как public.png в blob storage
        let pngRel = "\(UUID().uuidString)-qr.png.bin"
        try? png.write(to: AppStorage.blobsDir.appendingPathComponent(pngRel))
        copy.representations = ["public.png": pngRel]
        copy.typesOrdered = ["public.png"]
        return .preview(copy)
    }
}

// MARK: - Registry helper

enum TextActionsPack {
    static var all: [ClipboardAction] {
        [
            TitleCaseAction(), SentenceCaseAction(),
            CamelCaseAction(), SnakeCaseAction(), KebabCaseAction(),
            SortLinesAction(), UniqueLinesAction(),
            Base64EncodeAction(), Base64DecodeAction(),
            URLEncodeAction(), URLDecodeAction(),
            SlugifyAction(), WordCountAction(),
            GenerateQRAction()
        ]
    }
}
