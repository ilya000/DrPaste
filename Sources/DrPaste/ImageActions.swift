//
//  ImageActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Local image actions. Uses Vision (OCR / QR detection) and Core Image filters.
//

import Foundation
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Shared applicability check used by every image action: matches both
/// genuine image items and rich-text items that carry at least one embedded
/// image attachment, so an OCR / decode-QR / strip-metadata flow can pull
/// images out of pasted Pages / Word / Mail content.
private func imageActionApplies(item: ClipboardItem, context: ContentContext) -> Bool {
    context.contains(.image) || RichTextImageExtractor.hasEmbeddedImage(item)
}

private func loadImage(_ item: ClipboardItem) -> NSImage? {
    if let rel = item.previewImageRel {
        return NSImage(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel))
    }
    let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
    for type in imageTypes {
        if let rel = item.representations[type],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let img = NSImage(data: data) {
            return img
        }
    }
    // Rich text fallback: pull the first embedded image (NSTextAttachment) out
    // of any RTF / RTFD / HTML representation.
    if item.semantic == .richText, let img = RichTextImageExtractor.firstImage(in: item) {
        return img
    }
    return nil
}

/// Detects whether a rich-text item carries at least one embedded image and
/// extracts that image on demand. The detection result is cached by item ID so
/// `isApplicable` calls (run many times during HUD navigation) stay cheap.
enum RichTextImageExtractor {
    private static var hasImageCache: [UUID: Bool] = [:]
    private static let cacheLock = NSLock()

    /// Cheap predicate suitable for `isApplicable`. Decodes the attributed
    /// string once per item and caches the answer.
    static func hasEmbeddedImage(_ item: ClipboardItem) -> Bool {
        guard item.semantic == .richText else { return false }
        cacheLock.lock()
        if let cached = hasImageCache[item.id] { cacheLock.unlock(); return cached }
        cacheLock.unlock()

        let result = loadAttributedString(item).map { containsImageAttachment($0) } ?? false
        cacheLock.lock()
        hasImageCache[item.id] = result
        cacheLock.unlock()
        return result
    }

    /// Returns the first image found inside the rich-text attachments, or nil.
    static func firstImage(in item: ClipboardItem) -> NSImage? {
        guard let attr = loadAttributedString(item) else { return nil }
        var found: NSImage? = nil
        attr.enumerateAttribute(.attachment,
                                in: NSRange(location: 0, length: attr.length)) { value, _, stop in
            guard let attachment = value as? NSTextAttachment else { return }
            if let img = imageFromAttachment(attachment) {
                found = img
                stop.pointee = true
            }
        }
        return found
    }

    /// Drops the cached answer for an item — call when an item is removed from
    /// history so the cache doesn't grow unbounded across long sessions.
    static func invalidate(_ id: UUID) {
        cacheLock.lock(); hasImageCache.removeValue(forKey: id); cacheLock.unlock()
    }

    // MARK: - Helpers

    private static func loadAttributedString(_ item: ClipboardItem) -> NSAttributedString? {
        if let rel = item.representations["public.rtfd"] ?? item.representations["com.apple.flat-rtfd"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(data: data,
                                              options: [.documentType: NSAttributedString.DocumentType.rtfd],
                                              documentAttributes: nil) {
            return attr
        }
        if let rel = item.representations["public.rtf"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(data: data,
                                              options: [.documentType: NSAttributedString.DocumentType.rtf],
                                              documentAttributes: nil) {
            return attr
        }
        if let rel = item.representations["public.html"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(data: data,
                                              options: [.documentType: NSAttributedString.DocumentType.html,
                                                        .characterEncoding: String.Encoding.utf8.rawValue],
                                              documentAttributes: nil) {
            return attr
        }
        return nil
    }

    private static func containsImageAttachment(_ attr: NSAttributedString) -> Bool {
        var hit = false
        attr.enumerateAttribute(.attachment,
                                in: NSRange(location: 0, length: attr.length)) { value, _, stop in
            if let a = value as? NSTextAttachment, imageFromAttachment(a) != nil {
                hit = true
                stop.pointee = true
            }
        }
        return hit
    }

    private static func imageFromAttachment(_ attachment: NSTextAttachment) -> NSImage? {
        if let img = attachment.image { return img }
        if let data = attachment.fileWrapper?.regularFileContents,
           let img = NSImage(data: data) {
            return img
        }
        if let contents = attachment.contents, let img = NSImage(data: contents) {
            return img
        }
        return nil
    }
}

private func saveImage(_ image: NSImage, originalItem: ClipboardItem) -> ClipboardItem? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
    let name = "\(UUID().uuidString)-img.png"
    let rawName = "\(UUID().uuidString)-img.png.bin"
    try? png.write(to: AppStorage.imagesDir.appendingPathComponent(name))
    try? png.write(to: AppStorage.blobsDir.appendingPathComponent(rawName))
    var copy = originalItem
    copy.semantic = .image
    copy.previewImageRel = name
    copy.representations = ["public.png": rawName]
    copy.typesOrdered = ["public.png"]
    copy.previewText = "Image \(png.count / 1024) KB"
    return copy
}

// MARK: - OCR (Vision)

struct ImageOCRAction: ClipboardAction {
    let id = "builtin.image_ocr"; let title = "Extract text (OCR)"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item),
              let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .failed(original: item, reason: "Couldn't read image", recovery: nil)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "ru-RU"]
        let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .failed(original: item, reason: "OCR failed: \(error.localizedDescription)", recovery: nil)
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else {
            return .failed(original: item, reason: "No text recognized in image", recovery: nil)
        }
        return .preview(makeTextItem(lines.joined(separator: "\n"), from: item))
    }
}

// MARK: - QR / barcode decode

struct ImageDecodeQRAction: ClipboardAction {
    let id = "builtin.image_decode_qr"; let title = "Decode QR / barcode"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item),
              let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .failed(original: item, reason: "Couldn't read image", recovery: nil)
        }
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
        do { try handler.perform([request]) } catch {
            return .failed(original: item, reason: "Barcode detection failed", recovery: nil)
        }
        let payloads = (request.results ?? []).compactMap { $0.payloadStringValue }
        guard !payloads.isEmpty else {
            return .failed(original: item, reason: "No QR or barcode detected", recovery: nil)
        }
        return .preview(makeTextItem(payloads.joined(separator: "\n"), from: item))
    }
}

// MARK: - Filters

private func applyFilter(_ filter: CIFilter, on image: NSImage) -> NSImage? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let cgImg = bitmap.cgImage else { return nil }
    let ciImage = CIImage(cgImage: cgImg)
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    guard let output = filter.outputImage else { return nil }

    // Render explicitly via CIContext so the filter actually applies to pixels.
    // NSCIImageRep is lazy and can drop effects at some backing scale factors.
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let outputCG = context.createCGImage(output, from: output.extent) else { return nil }
    let outRep = NSBitmapImageRep(cgImage: outputCG)
    let result = NSImage(size: NSSize(width: outRep.pixelsWide, height: outRep.pixelsHigh))
    result.addRepresentation(outRep)
    return result
}

struct ImageGrayscaleAction: ClipboardAction {
    let id = "builtin.image_grayscale"; let title = "Grayscale"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item) else {
            return .failed(original: item, reason: "Couldn't read image", recovery: nil)
        }
        let filter = CIFilter.photoEffectMono()
        guard let out = applyFilter(filter, on: img),
              let saved = saveImage(out, originalItem: item) else {
            return .failed(original: item, reason: "Grayscale failed", recovery: nil)
        }
        return .preview(saved)
    }
}

struct ImageInvertAction: ClipboardAction {
    let id = "builtin.image_invert"; let title = "Invert colors"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item) else {
            return .failed(original: item, reason: "Couldn't read image", recovery: nil)
        }
        let filter = CIFilter.colorInvert()
        guard let out = applyFilter(filter, on: img),
              let saved = saveImage(out, originalItem: item) else {
            return .failed(original: item, reason: "Invert failed", recovery: nil)
        }
        return .preview(saved)
    }
}

/// Shared rotation primitive used by both directions. Positive angle =
/// counter-clockwise (Core Graphics convention). After transform, the image
/// extent has a non-zero origin; we translate it back to (0, 0) before
/// rasterizing so the saved PNG has a tight bounding box and no spurious
/// transparent border.
private func rotateImage(_ item: ClipboardItem, radians: CGFloat) -> ClipboardItem? {
    guard let img = loadImage(item),
          let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let cgImg = bitmap.cgImage else {
        return nil
    }
    let ciImage = CIImage(cgImage: cgImg)
    let rotated = ciImage.transformed(by: CGAffineTransform(rotationAngle: radians))
    let normalized = rotated.transformed(
        by: CGAffineTransform(translationX: -rotated.extent.origin.x,
                              y: -rotated.extent.origin.y)
    )
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let outputCG = context.createCGImage(normalized, from: normalized.extent) else {
        return nil
    }
    let rep = NSBitmapImageRep(cgImage: outputCG)
    let result = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    result.addRepresentation(rep)
    return saveImage(result, originalItem: item)
}

/// Rotate 90° clockwise (the existing built-in — keeps its stable id so
/// existing user customizations / hotkeys carry over). Title clarified to
/// say "right" since "CW" alone isn't intuitive at a glance.
struct ImageRotateRightAction: ClipboardAction {
    let id = "builtin.image_rotate"
    let title = "Rotate right (90° CW)"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let saved = rotateImage(item, radians: -.pi / 2) else {
            return .failed(original: item, reason: "Rotation failed", recovery: nil)
        }
        return .preview(saved)
    }
}

/// Rotate 90° counter-clockwise (new). Paired with the right rotation so
/// the user can quickly straighten a sideways-captured photo from either
/// direction without thinking about which way it tipped.
struct ImageRotateLeftAction: ClipboardAction {
    let id = "builtin.image_rotate_left"
    let title = "Rotate left (90° CCW)"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let saved = rotateImage(item, radians: .pi / 2) else {
            return .failed(original: item, reason: "Rotation failed", recovery: nil)
        }
        return .preview(saved)
    }
}

struct ImageResize1920Action: ClipboardAction {
    let id = "builtin.image_resize_1920"; let title = "Resize to max 1920px"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item) else {
            return .failed(original: item, reason: "Couldn't read image", recovery: nil)
        }
        let size = img.size
        let maxSide = max(size.width, size.height)
        guard maxSide > 1920 else {
            return .failed(original: item, reason: "Already ≤ 1920px", recovery: nil)
        }
        let scale = 1920 / maxSide
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: newSize)
        result.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSize),
                 from: .zero, operation: .copy, fraction: 1.0)
        result.unlockFocus()
        guard let saved = saveImage(result, originalItem: item) else {
            return .failed(original: item, reason: "Resize failed", recovery: nil)
        }
        return .preview(saved)
    }
}

struct ImageCompressJPEGAction: ClipboardAction {
    let id = "builtin.image_compress_jpeg"; let title = "Compress to JPEG 80%"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item),
              let tiff = img.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return .failed(original: item, reason: "JPEG compression failed", recovery: nil)
        }
        let name = "\(UUID().uuidString)-c.jpg"
        let rawName = "\(UUID().uuidString)-c.jpg.bin"
        try? jpeg.write(to: AppStorage.imagesDir.appendingPathComponent(name))
        try? jpeg.write(to: AppStorage.blobsDir.appendingPathComponent(rawName))
        var copy = item
        copy.semantic = .image
        copy.previewImageRel = name
        copy.representations = ["public.jpeg": rawName]
        copy.typesOrdered = ["public.jpeg"]
        copy.previewText = "JPEG \(jpeg.count / 1024) KB"
        return .preview(copy)
    }
}

struct ImageStripMetadataAction: ClipboardAction {
    let id = "builtin.image_strip_meta"; let title = "Strip EXIF / metadata"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item),
              let tiff = img.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return .failed(original: item, reason: "Strip metadata failed", recovery: nil)
        }
        // PNG does not carry EXIF; the re-encode strips any metadata.
        let name = "\(UUID().uuidString)-clean.png"
        let rawName = "\(UUID().uuidString)-clean.png.bin"
        try? png.write(to: AppStorage.imagesDir.appendingPathComponent(name))
        try? png.write(to: AppStorage.blobsDir.appendingPathComponent(rawName))
        var copy = item
        copy.semantic = .image
        copy.previewImageRel = name
        copy.representations = ["public.png": rawName]
        copy.typesOrdered = ["public.png"]
        copy.previewText = "Image \(png.count / 1024) KB (no metadata)"
        return .preview(copy)
    }
}

// MARK: - ASCII art

/// Renders the image as a monospaced ASCII-art block by downsampling to a
/// character grid, converting each cell's average luminance to a glyph from
/// a darkness gradient. Local and deterministic — no AI, no network call.
/// For best results in fixed-width terminals / Discord code blocks, use the
/// result wrapped in a code fence (the "Wrap in code block" action chains
/// nicely after this one via ⌥⌘Space).
struct ImageToASCIIArtAction: ClipboardAction {
    let id = "builtin.image_ascii_art"
    let title = "ASCII art"
    let isLocal = true

    // Wider character → cell aspect compensates for the fact that monospace
    // characters are roughly twice as tall as they are wide; using a 2:1
    // sampling ratio keeps the rendered art visually proportional.
    private static let outWidth: Int = 100
    private static let charAspect: Double = 0.5

    // Gradient from "transparent" (whitespace) → "fully filled". Order
    // determines the brightness mapping (index 0 = lightest, last = darkest).
    private static let ramp: [Character] = Array(" .:-=+*#%@")

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item) else {
            return .failed(original: item, reason: "Couldn't read image", recovery: nil)
        }
        let result = Self.render(image: img)
        guard !result.isEmpty else {
            return .failed(original: item, reason: "ASCII conversion produced empty output", recovery: nil)
        }
        return .preview(makeTextItem(result, from: item))
    }

    /// Pure renderer — split out so it's testable.
    ///
    /// Pipeline:
    ///   1. Rasterize to an 8-bit grayscale buffer at the target grid.
    ///   2. Apply a "background" threshold — pixels above the brightness cap
    ///      become space, NOT the lightest gradient glyph. This stops light
    ///      backgrounds (white, pastel) from being painted as a sea of dots.
    ///   3. Map remaining (foreground) values across the ramp with the
    ///      lightest dot reserved for near-background tones so the visible
    ///      content has clear separation from the canvas.
    ///   4. Auto-crop to the bounding box of non-space cells so the result
    ///      tightly frames the subject and doesn't waste rows on empty
    ///      borders. Critical for cartoon / logo / icon source images,
    ///      which are typically padded with whitespace.
    static func render(image: NSImage) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else {
            return ""
        }
        let srcW = cg.width
        let srcH = cg.height
        let aspect = Double(srcH) / Double(srcW)
        let cols = outWidth
        let rows = max(1, Int(Double(cols) * aspect * charAspect))

        // Render scaled grayscale image into an 8-bit single-channel buffer
        // so we can read luminance per cell directly without per-pixel
        // CIContext queries.
        var pixels = [UInt8](repeating: 0, count: cols * rows)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels,
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: cols,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return ""
        }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))

        // Build a 2D char grid first so auto-crop can scan it efficiently.
        var grid = [[Character]](repeating: [Character](repeating: " ", count: cols),
                                  count: rows)
        let lastIdx = ramp.count - 1
        // Brightness above this threshold is treated as background → space.
        // Tuned against typical light backgrounds (white, mint, beige, gray
        // page chrome). Increases foreground-vs-background contrast and
        // makes auto-crop tight against the subject.
        let backgroundCutoff: Double = 0.78
        for row in 0..<rows {
            // Bitmap origin is bottom-left in Core Graphics; iterate top-down
            // so the resulting text reads in the same orientation as the image.
            let srcRow = rows - 1 - row
            for col in 0..<cols {
                let v = Double(pixels[srcRow * cols + col]) / 255.0
                if v >= backgroundCutoff {
                    // Background — leave as space (initial value).
                    continue
                }
                // Foreground range remapped to (1..lastIdx). Index 0 (space)
                // is reserved for background only, so visible content always
                // has at least minimum density and never blends with bg.
                let norm = (backgroundCutoff - v) / backgroundCutoff
                let idx = max(1, min(lastIdx, Int((norm * Double(lastIdx)).rounded())))
                grid[row][col] = ramp[idx]
            }
        }

        // Auto-crop to bounding box of non-space cells.
        var top = 0
        while top < rows && grid[top].allSatisfy({ $0 == " " }) { top += 1 }
        guard top < rows else { return "" }    // empty image
        var bottom = rows - 1
        while bottom > top && grid[bottom].allSatisfy({ $0 == " " }) { bottom -= 1 }
        var left = cols
        var right = -1
        for r in top...bottom {
            for c in 0..<cols where grid[r][c] != " " {
                if c < left  { left = c }
                if c > right { right = c }
            }
        }
        guard left <= right else { return "" }

        // Emit the cropped region.
        var output = ""
        output.reserveCapacity((bottom - top + 1) * (right - left + 2))
        for r in top...bottom {
            for c in left...right {
                output.append(grid[r][c])
            }
            output.append("\n")
        }
        return output
    }
}

enum ImageActionsPack {
    static var all: [ClipboardAction] {
        [
            ImageOCRAction(), ImageDecodeQRAction(),
            ImageStripMetadataAction(), ImageResize1920Action(),
            ImageCompressJPEGAction(),
            ImageGrayscaleAction(),
            ImageRotateRightAction(), ImageRotateLeftAction(),
            ImageInvertAction(),
            ImageToASCIIArtAction()
        ]
    }
}
