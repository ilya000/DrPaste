//
//  FileToImageAction.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Extract an image from a single-file `.files` clip (#A21).
//
//  Scope (intentionally narrow per user spec):
//
//    • PDF                → render page 1 at 2× scale as PNG
//    • HEIC / HEIF        → re-encode bytes as PNG
//    • TIFF / BMP / GIF   → re-encode bytes as PNG
//
//  Multi-page PDFs only emit page 1. Multi-file clips are
//  intentionally rejected — the user spec asked for "first page
//  / simple cases only". Video / archive / unknown formats are
//  inapplicable (action chip disabled).
//

import Foundation
import AppKit
import PDFKit

struct FileToImageAction: ClipboardAction {
    let id = "builtin.files.extract_image"
    let title = "Extract image"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard item.semantic == .files else { return false }
        let paths = filesList(item)
        guard paths.count == 1 else { return false }
        let lower = paths[0].lowercased()
        return supportedExtensions.contains { lower.hasSuffix("." + $0) }
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let paths = filesList(item)
        guard let path = paths.first else {
            return .failed(original: item,
                           reason: "Extract image: empty files list.",
                           recovery: nil)
        }
        let lower = path.lowercased()
        let result: (Data?, String?) = await runOffMain {
            let url = URL(fileURLWithPath: path)
            if lower.hasSuffix(".pdf") {
                return self.extractPDFFirstPage(url)
            } else {
                return self.reencodeAsPNG(url)
            }
        }
        guard let data = result.0, let fmt = result.1 else {
            return .failed(original: item,
                           reason: "Extract image: couldn't read \(URL(fileURLWithPath: path).lastPathComponent).",
                           recovery: nil)
        }
        return .preview(makeImageItem(data: data, format: fmt, from: item))
    }

    // MARK: PDF first page

    private func extractPDFFirstPage(_ url: URL) -> (Data?, String?) {
        guard let doc = PDFDocument(url: url) else { return (nil, nil) }
        guard let page = doc.page(at: 0) else { return (nil, nil) }
        let bounds = page.bounds(for: .mediaBox)
        // 2× scale = high-DPI render. Good balance between size and quality
        // for typical PDFs (US Letter / A4 → ~1700×2200 px).
        let scale: CGFloat = 2
        let pixelSize = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        // #A47 — Use ImageRenderer.render (CGContext-backed) so the
        // PDF page draws into a thread-safe, pixel-deterministic
        // bitmap. The closure receives a CGContext flipped to the
        // NSGraphicsContext stack convention that `page.draw(...)`
        // expects, so the existing draw call stays unchanged.
        guard let image = ImageRenderer.render(size: pixelSize, opaque: true,
                                               draw: { ctx in
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        }) else { return (nil, nil) }
        return (ImageRenderer.pngData(from: image), "PNG")
    }

    // MARK: re-encode HEIC / TIFF / BMP / GIF as PNG

    private func reencodeAsPNG(_ url: URL) -> (Data?, String?) {
        guard let image = NSImage(contentsOf: url) else { return (nil, nil) }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (nil, nil)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return (nil, nil) }
        return (data, "PNG")
    }

    // MARK: writing

    private func makeImageItem(data: Data, format: String, from item: ClipboardItem) -> ClipboardItem {
        // id / createdAt are `let` — preview-transformation reuses
        // the source clip's identity (matches saveImage / makeTextItem).
        var copy = item
        copy.semantic = .image
        let blobName = "extract-\(UUID().uuidString.prefix(8)).png"
        try? data.write(to: AppStorage.blobsDir.appendingPathComponent(blobName))
        // Codex #5 — also write a preview image. The HUD renders the thumbnail
        // from previewImageRel; without it the extracted image showed a blank
        // placeholder. (We also clear any inherited file-icon thumbnail.)
        let previewName = "extract-preview-\(UUID().uuidString.prefix(8)).png"
        try? data.write(to: AppStorage.imagesDir.appendingPathComponent(previewName))
        copy.representations = ["public.png": blobName]
        copy.typesOrdered = ["public.png"]
        copy.previewImageRel = previewName
        copy.imageFormat = format
        copy.originalImageFileSize = data.count
        return copy
    }

    private func filesList(_ item: ClipboardItem) -> [String] {
        // Codex sweep — read the real file references via the shared helper.
        clipFilePaths(item)
    }

    private let supportedExtensions: Set<String> = [
        "pdf",
        "heic", "heif",
        "tiff", "tif",
        "bmp",
        "gif"
    ]
}
