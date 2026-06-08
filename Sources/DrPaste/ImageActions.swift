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
import ImageIO

/// Shared Core Image rendering context for every image action.
/// `CIContext()` is expensive to construct (allocates GPU/Metal resources,
/// loads shader caches) — building one per filter call costs measurable
/// CPU and GPU on a typical user gesture like "navigate through three
/// image actions in the HUD with arrow keys". Single static instance,
/// thread-safe per Apple's CIContext contract.
private let sharedCIContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])

/// Shared applicability check used by every image action: matches both
/// genuine image items and rich-text items that carry at least one embedded
/// image attachment, so an OCR / decode-QR / strip-metadata flow can pull
/// images out of pasted Pages / Word / Mail content.
private func imageActionApplies(item: ClipboardItem, context: ContentContext) -> Bool {
    // `.richHasImage` is set by ContextDetector when a rich clip carries an
    // embedded image, so the gate is a cheap flag check instead of re-decoding
    // the attributed string on every applicability call.
    context.contains(.image) || context.contains(.richHasImage)
}

/// Loads the **original** (full-size) image for an image transformation.
/// Priority (#A48): raw pasteboard representation > thumbnail preview.
///
/// Why this matters: `previewImageRel` is a downscaled thumbnail
/// (max 600 pt via `PreviewSynthesizer.imageRelative`) created at
/// snapshot time for fast HUD rendering. Image transformations
/// (OCR, Grayscale, Rotate, AI Watercolor) **must** operate on the
/// original bytes — running Grayscale on a 600pt thumbnail of a
/// 5K screenshot loses 95% of the data. The previous order — check
/// `previewImageRel` first — silently degraded every transformation
/// to thumbnail resolution when both were stored. Now raw
/// representations are preferred, and the thumbnail is the
/// last-resort fallback.
///
/// Use `loadPreviewImage(_:)` for HUD chrome / Settings list / any
/// place where thumbnail resolution is what's wanted.
private func loadImage(_ item: ClipboardItem) -> NSImage? {
    return loadOriginalImage(item) ?? loadPreviewImage(item)
}

/// Loads the full-size original from a raw pasteboard representation,
/// or nil if no original is stored. Image transformations use this.
private func loadOriginalImage(_ item: ClipboardItem) -> NSImage? {
    let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
    for type in imageTypes {
        if let rel = item.representations[type],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let img = NSImage(data: data) {
            return img
        }
    }
    // Rich-text embedded attachment: still original-resolution because
    // the attachment carries the source bytes.
    if item.semantic == .richText, let img = RichTextImageExtractor.firstImage(in: item) {
        return img
    }
    return nil
}

/// Loads the thumbnail preview image. Used as last-resort fallback
/// by transformations when no raw representation is stored, and as
/// the primary path by HUD chrome / Settings list.
private func loadPreviewImage(_ item: ClipboardItem) -> NSImage? {
    if let rel = item.previewImageRel {
        return NSImage(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel))
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

    /// Loads the rich-text attributed string for an item, or nil. Public so
    /// the OCR action can walk every embedded image attachment.
    static func attributed(_ item: ClipboardItem) -> NSAttributedString? {
        loadAttributedString(item)
    }

    /// Extracts an NSImage from a text attachment, or nil. Public so the OCR
    /// action can OCR each embedded image in turn.
    static func image(from attachment: NSTextAttachment) -> NSImage? {
        imageFromAttachment(attachment)
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
        // Delegate to the single robust loader (uses NSAttributedString(rtfd:)
        // for flat-RTFD / public.rtfd, which rehydrates embedded-image
        // FileWrappers reliably) so image detection matches what the preview
        // actually renders.
        RichTextLoader.attributedString(from: item)
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

/// Run heavy NSImage / Vision / CIFilter work off the main thread so the
/// HUD preview pane stays responsive while a transformation is in
/// flight. Every image action below is CPU-bound (CIFilter render,
/// VNImageRequestHandler.perform, NSBitmapImageRep encode); without
/// this hop the `await action.apply(...)` in `refreshPreview` would
/// run synchronously on the main actor and freeze the UI for the
/// full 100–500 ms a transformation takes on a typical full-resolution
/// image. Closure result must be Sendable — `ClipboardItem` and
/// `String` are; `NSImage` stays inside the closure and never
/// escapes the detached task.
///
/// Internal (not file-private) so 0.52.0 sibling files
/// (ImageResizeAction, FileToImageAction, UnitConversion) can hop
/// off-main with the same helper instead of duplicating the
/// `Task.detached(priority:operation:).value` boilerplate.
func runOffMain<T: Sendable>(
    _ work: @Sendable @escaping () -> T
) async -> T {
    await Task.detached(priority: .userInitiated, operation: work).value
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

// MARK: - In-place image transforms for rich clips

/// PNG bytes for an NSImage (via its bitmap rep).
func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) else { return nil }
    return bmp.representation(using: .png, properties: [:])
}

/// JPEG bytes for an NSImage at the given quality.
func jpegData(from image: NSImage, factor: Double) -> Data? {
    guard let tiff = image.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) else { return nil }
    return bmp.representation(using: .jpeg, properties: [.compressionFactor: factor])
}

/// Applies `transform` to EVERY embedded image of a rich clip IN PLACE,
/// returning a rich clip (flat-RTFD) with the surrounding text and other runs
/// preserved. This is what makes Rotate / Grayscale / Invert / Compress operate
/// on the picture INSIDE the rich text instead of extracting it and discarding
/// the prose. `transform` returns encoded bytes + extension, or nil to leave an
/// attachment untouched. Runs off-main; returns nil when nothing was changed.
func transformRichEmbeddedImages(
    _ item: ClipboardItem,
    _ transform: @escaping (NSImage) -> (data: Data, ext: String)?
) async -> ApplyOutcome? {
    let rtfd: Data? = await runOffMain {
        guard let attr = RichTextLoader.attributedString(from: item) else { return nil }
        let out = NSMutableAttributedString(attributedString: attr)
        var anyReplaced = false
        out.enumerateAttribute(.attachment,
                               in: NSRange(location: 0, length: out.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let img = RichTextImageExtractor.image(from: attachment),
                  let (data, ext) = transform(img) else { return }
            let base = (attachment.fileWrapper?.preferredFilename as NSString?)?.deletingPathExtension ?? "image"
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = base + "." + ext
            out.replaceCharacters(in: range, with: NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
            anyReplaced = true
        }
        guard anyReplaced else { return nil }
        return try? out.data(from: NSRange(location: 0, length: out.length),
                             documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    }
    guard let rtfd,
          let attr = try? NSAttributedString(
              data: rtfd,
              options: [.documentType: NSAttributedString.DocumentType.rtfd],
              documentAttributes: nil) else {
        return nil
    }
    return .preview(makeRichTextItem(attr, from: item))
}

// MARK: - OCR (Vision)

/// Shared text recognizer — runs VNRecognizeText on one image and returns the
/// joined lines, or nil if nothing was read. Caller hops off-main.
func recognizeText(in image: NSImage) -> String? {
    guard let cgImg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US", "ru-RU"]
    let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
    guard (try? handler.perform([request])) != nil else { return nil }
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
}

/// Builds a rich-text result item from already-serialized flat-RTFD bytes.
/// Mirrors the RTFD branch of `makeRichTextItem` but takes Data so the
/// NSAttributedString can be assembled (and OCR'd) entirely off-main.
private func makeRichItem(fromRTFD data: Data, plain: String, from item: ClipboardItem) -> ClipboardItem {
    var copy = item
    copy.semantic = .richText
    copy.previewText = plain
    let tmpName = "ocr-rich-\(UUID().uuidString).rtfd"
    try? data.write(to: AppStorage.blobsDir.appendingPathComponent(tmpName))
    copy.representations = ["com.apple.flat-rtfd": tmpName]
    copy.typesOrdered = ["com.apple.flat-rtfd"]
    copy.previewImageRel = nil
    return copy
}

struct ImageOCRAction: ClipboardAction {
    let id = "builtin.image.ocr"; let title = "Extract text (OCR)"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        // Rich text with embedded images → OCR every image IN PLACE, replacing
        // each attachment with its recognized text while keeping the
        // surrounding rich text intact. The result stays a rich clip.
        if item.semantic == .richText, RichTextImageExtractor.hasEmbeddedImage(item) {
            return await applyToRichText(item)
        }
        // Plain image clip → recognize and return plain text. Heavy Vision work
        // runs off-main so the HUD preview pane stays responsive.
        enum OCROutcome: Sendable { case ok(String); case failed(String) }
        let outcome: OCROutcome = await runOffMain {
            guard let img = loadImage(item) else {
                return .failed("Couldn't read image")
            }
            guard let text = recognizeText(in: img) else {
                return .failed("No text recognized in image")
            }
            return .ok(text)
        }
        switch outcome {
        case .ok(let text):
            // Stamp OCR provenance so "Clean OCR text" surfaces on the result
            // (#A75 kill-feature chain).
            var out = makeTextItem(text, from: item)
            out.tags.append(ContextDetector.ocrProvenanceTag)
            return .preview(out)
        case .failed(let reason):
            return .failed(original: item, reason: reason, recovery: nil)
        }
    }

    /// OCR each embedded image attachment and splice the recognized text in its
    /// place. Everything (decode → enumerate → Vision → re-serialize) happens
    /// inside the off-main closure, so the NSAttributedString never escapes and
    /// the only value crossing the boundary is Sendable Data + String.
    private func applyToRichText(_ item: ClipboardItem) async -> ApplyOutcome {
        enum RichOCR: Sendable { case ok(data: Data, text: String); case failed(String) }
        let outcome: RichOCR = await runOffMain {
            guard let attr = RichTextImageExtractor.attributed(item) else {
                return .failed("Couldn't read rich text")
            }
            let mutable = NSMutableAttributedString(attributedString: attr)
            // Collect every image-bearing attachment range up front.
            var jobs: [(NSRange, NSImage)] = []
            mutable.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
                if let a = value as? NSTextAttachment, let img = RichTextImageExtractor.image(from: a) {
                    jobs.append((range, img))
                }
            }
            guard !jobs.isEmpty else { return .failed("No images in rich text") }
            // Replace back-to-front so earlier ranges stay valid as lengths change.
            var recognizedAny = false
            for (range, img) in jobs.reversed() {
                let recognized = recognizeText(in: img)
                if let recognized, !recognized.isEmpty {
                    recognizedAny = true
                    let replacement = NSAttributedString(
                        string: recognized,
                        attributes: [.font: NSFont.systemFont(ofSize: 13)])
                    mutable.replaceCharacters(in: range, with: replacement)
                }
                // Image with no readable text: leave the attachment untouched.
            }
            guard recognizedAny else {
                return .failed("No text recognized in embedded image(s)")
            }
            let full = NSRange(location: 0, length: mutable.length)
            guard let data = try? mutable.data(
                from: full,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
                return .failed("Couldn't rebuild rich text")
            }
            return .ok(data: data, text: mutable.string)
        }
        switch outcome {
        case .ok(let data, let text):
            var out = makeRichItem(fromRTFD: data, plain: text, from: item)
            out.tags.append(ContextDetector.ocrProvenanceTag)
            return .preview(out)
        case .failed(let reason):
            return .failed(original: item, reason: reason, recovery: nil)
        }
    }
}

// MARK: - QR / barcode decode

struct ImageDecodeQRAction: ClipboardAction {
    let id = "builtin.image.decode_qr"; let title = "Decode QR"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Image clips only — decoding "the QR inside a rich document" is
        // ambiguous, and the action returns a plain payload, not a rich edit.
        context.contains(.image)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        enum QROutcome: Sendable { case ok(String); case failed(String) }
        let outcome: QROutcome = await runOffMain {
            guard let img = loadImage(item),
                  let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return .failed("Couldn't read image")
            }
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
            do { try handler.perform([request]) } catch {
                return .failed("Barcode detection failed")
            }
            let payloads = (request.results ?? []).compactMap { $0.payloadStringValue }
            guard !payloads.isEmpty else {
                return .failed("No QR or barcode detected")
            }
            return .ok(payloads.joined(separator: "\n"))
        }
        switch outcome {
        case .ok(let text):
            return .preview(makeTextItem(text, from: item))
        case .failed(let reason):
            return .failed(original: item, reason: reason, recovery: nil)
        }
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
    let context = sharedCIContext
    guard let outputCG = context.createCGImage(output, from: output.extent) else { return nil }
    let outRep = NSBitmapImageRep(cgImage: outputCG)
    let result = NSImage(size: NSSize(width: outRep.pixelsWide, height: outRep.pixelsHigh))
    result.addRepresentation(outRep)
    return result
}

struct ImageGrayscaleAction: ClipboardAction {
    let id = "builtin.image.to_grayscale"; let title = "Grayscale"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        if item.semantic == .richText {
            if let outcome = await transformRichEmbeddedImages(item, { img in
                applyFilter(CIFilter.photoEffectMono(), on: img).flatMap { pngData(from: $0).map { ($0, "png") } }
            }) { return outcome }
            return .failed(original: item, reason: "No embedded image to grayscale", recovery: nil)
        }
        let saved: ClipboardItem? = await runOffMain {
            guard let img = loadImage(item) else { return nil }
            let filter = CIFilter.photoEffectMono()
            guard let out = applyFilter(filter, on: img) else { return nil }
            return saveImage(out, originalItem: item)
        }
        guard let saved = saved else {
            return .failed(original: item, reason: "Grayscale failed", recovery: nil)
        }
        return .preview(saved)
    }
}

struct ImageInvertAction: ClipboardAction {
    let id = "builtin.image.invert_colors"; let title = "Invert colors"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        if item.semantic == .richText {
            if let outcome = await transformRichEmbeddedImages(item, { img in
                applyFilter(CIFilter.colorInvert(), on: img).flatMap { pngData(from: $0).map { ($0, "png") } }
            }) { return outcome }
            return .failed(original: item, reason: "No embedded image to invert", recovery: nil)
        }
        let saved: ClipboardItem? = await runOffMain {
            guard let img = loadImage(item) else { return nil }
            let filter = CIFilter.colorInvert()
            guard let out = applyFilter(filter, on: img) else { return nil }
            return saveImage(out, originalItem: item)
        }
        guard let saved = saved else {
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
private func rotatedImage(_ img: NSImage, radians: CGFloat) -> NSImage? {
    guard let tiff = img.tiffRepresentation,
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
    guard let outputCG = sharedCIContext.createCGImage(normalized, from: normalized.extent) else {
        return nil
    }
    let rep = NSBitmapImageRep(cgImage: outputCG)
    let result = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    result.addRepresentation(rep)
    return result
}

private func rotateImage(_ item: ClipboardItem, radians: CGFloat) -> ClipboardItem? {
    guard let img = loadImage(item),
          let rotated = rotatedImage(img, radians: radians) else { return nil }
    return saveImage(rotated, originalItem: item)
}

/// Rotate 90° clockwise (the existing built-in — keeps its stable id so
/// existing user customizations / hotkeys carry over). Title clarified to
/// say "right" since "CW" alone isn't intuitive at a glance.
struct ImageRotateRightAction: ClipboardAction {
    let id = "builtin.image.rotate_right"
    let title = "Rotate right"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        if item.semantic == .richText {
            if let outcome = await transformRichEmbeddedImages(item, { img in
                rotatedImage(img, radians: -.pi / 2).flatMap { pngData(from: $0).map { ($0, "png") } }
            }) { return outcome }
            return .failed(original: item, reason: "No embedded image to rotate", recovery: nil)
        }
        let saved: ClipboardItem? = await runOffMain {
            rotateImage(item, radians: -.pi / 2)
        }
        guard let saved = saved else {
            return .failed(original: item, reason: "Rotation failed", recovery: nil)
        }
        return .preview(saved)
    }
}

/// Rotate 90° counter-clockwise (new). Paired with the right rotation so
/// the user can quickly straighten a sideways-captured photo from either
/// direction without thinking about which way it tipped.
struct ImageRotateLeftAction: ClipboardAction {
    let id = "builtin.image.rotate_left"
    let title = "Rotate left"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        if item.semantic == .richText {
            if let outcome = await transformRichEmbeddedImages(item, { img in
                rotatedImage(img, radians: .pi / 2).flatMap { pngData(from: $0).map { ($0, "png") } }
            }) { return outcome }
            return .failed(original: item, reason: "No embedded image to rotate", recovery: nil)
        }
        let saved: ClipboardItem? = await runOffMain {
            rotateImage(item, radians: .pi / 2)
        }
        guard let saved = saved else {
            return .failed(original: item, reason: "Rotation failed", recovery: nil)
        }
        return .preview(saved)
    }
}

/// User-configurable resize target, stored per action ID so each resize action
/// can have its own longer-side limit. Backed by UserDefaults (a single scalar
/// per action) so the action structs — which have no config plumbing — can read
/// it directly in `apply`. The Settings → Edit Action sheet writes it.
enum ResizeSettings {
    // Floor of 1 px: resizing to a tiny favicon / 10 px thumbnail is a valid
    // request. The previous 16 px floor silently snapped "10" up to 16 so the
    // user could never make a genuinely small image.
    static let minSide = 1
    static let maxSide = 20000
    private static func key(_ id: String) -> String { "drpaste.image.resizeMaxLongSide.\(id)" }

    static func maxLongSide(for id: String, default def: Int = 1920) -> Int {
        let v = UserDefaults.standard.integer(forKey: key(id))
        return v >= minSide ? v : def
    }
    static func setMaxLongSide(_ v: Int, for id: String) {
        UserDefaults.standard.set(min(maxSide, max(minSide, v)), forKey: key(id))
    }
}

struct ImageCompressJPEGAction: ClipboardAction {
    let id = "builtin.image.compress_jpeg"; let title = "Compress JPEG"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        imageActionApplies(item: item, context: context)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        if item.semantic == .richText {
            if let outcome = await transformRichEmbeddedImages(item, { img in
                jpegData(from: img, factor: 0.8).map { ($0, "jpg") }
            }) { return outcome }
            return .failed(original: item, reason: "No embedded image to compress", recovery: nil)
        }
        let copy: ClipboardItem? = await runOffMain {
            guard let img = loadImage(item),
                  let tiff = img.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                return nil
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
            return copy
        }
        guard let copy = copy else {
            return .failed(original: item, reason: "JPEG compression failed", recovery: nil)
        }
        return .preview(copy)
    }
}

/// Reads privacy-relevant metadata (EXIF / GPS / camera) from raw image bytes
/// via ImageIO. Used by Strip-metadata to report exactly what it removed — both
/// in the HUD/Settings preview text and so the test panel shows the metadata
/// instead of two identical-looking images.
enum ImageMetadata {
    /// Raw bytes of the first stored image representation (preferring formats
    /// that actually carry EXIF/GPS), or the preview image as a fallback.
    static func rawData(_ item: ClipboardItem) -> Data? {
        for type in ["public.jpeg", "public.heic", "public.tiff", "public.png"] {
            if let rel = item.representations[type],
               let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)) {
                return data
            }
        }
        if let rel = item.previewImageRel,
           let data = try? Data(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel)) {
            return data
        }
        return nil
    }

    /// Short, human-readable highlights of the sensitive metadata present
    /// (GPS location, camera make/model, capture date). Empty if none.
    static func privacyHighlights(of data: Data) -> [String] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return [] }
        var out: [String] = []
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? ""
                let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? ""
                out.append(String(format: "GPS %.4f°%@ %.4f°%@", lat, latRef, lon, lonRef))
            } else {
                out.append("GPS location")
            }
        }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let camera = [tiff?[kCGImagePropertyTIFFMake] as? String,
                      tiff?[kCGImagePropertyTIFFModel] as? String]
            .compactMap { $0 }.joined(separator: " ")
        if !camera.isEmpty { out.append("Camera \(camera)") }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dt = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            out.append("Date taken \(dt)")
        }
        return out
    }

    /// True if the bytes carry PRIVACY-relevant metadata worth stripping —
    /// GPS, IPTC, EXIF capture fields, or a camera make/model. Deliberately
    /// ignores the benign TIFF resolution/orientation dictionary that ImageIO
    /// attaches to almost every encoded image (incl. plain PNGs), so we don't
    /// claim to have removed something when there was nothing sensitive.
    static func hasAny(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return false }
        if props[kCGImagePropertyGPSDictionary] != nil { return true }
        if props[kCGImagePropertyIPTCDictionary] != nil { return true }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            let capture: [CFString] = [
                kCGImagePropertyExifDateTimeOriginal,
                kCGImagePropertyExifDateTimeDigitized,
                kCGImagePropertyExifLensModel,
                kCGImagePropertyExifUserComment
            ]
            if capture.contains(where: { exif[$0] != nil }) { return true }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil {
                return true
            }
        }
        return false
    }

    /// Full human-readable report — name, format, dimensions, file size, colour
    /// info and (when present) camera / capture date / GPS / exposure. Used by
    /// the "Image info" action.
    static func report(for item: ClipboardItem) -> String? {
        guard let data = rawData(item),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        var lines: [String] = []

        let name = (iptc?[kCGImagePropertyIPTCObjectName] as? String) ?? displayName(for: item)
        lines.append("Name: \(name)")
        let format: String = {
            if let ut = CGImageSourceGetType(src) { return friendlyFormat(String(ut)) }
            return item.imageFormat ?? "—"
        }()
        lines.append("Format: \(format)")

        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? item.originalImageWidth ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? item.originalImageHeight ?? 0
        if w > 0, h > 0 { lines.append("Dimensions: \(w) × \(h) px") }
        lines.append("File size: \(formatBytes(item.originalImageFileSize ?? data.count))")

        if let depth = props[kCGImagePropertyDepth] as? Int { lines.append("Bit depth: \(depth)") }
        if let model = props[kCGImagePropertyColorModel] as? String { lines.append("Colour model: \(model)") }
        if let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            lines.append("Resolution: \(Int(dpi)) DPI")
        }
        if let alpha = props[kCGImagePropertyHasAlpha] as? Bool {
            lines.append("Transparency: \(alpha ? "yes" : "no")")
        }

        let highlights = privacyHighlights(of: data)
        var details: [String] = []
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
                details.append("ISO \(iso)")
            }
            if let f = exif[kCGImagePropertyExifFNumber] as? Double {
                details.append(String(format: "Aperture ƒ/%.1f", f))
            }
            if let exp = exif[kCGImagePropertyExifExposureTime] as? Double, exp > 0 {
                details.append("Exposure 1/\(Int((1.0 / exp).rounded())) s")
            }
            if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
                details.append(String(format: "Focal length %.0f mm", focal))
            }
        }

        let description = (tiff?[kCGImagePropertyTIFFImageDescription] as? String)
            ?? (iptc?[kCGImagePropertyIPTCCaptionAbstract] as? String)

        if highlights.isEmpty && details.isEmpty && description == nil {
            lines.append("Metadata: none (no EXIF / GPS)")
        } else {
            // Only print the "Metadata:" block when there is actual EXIF / GPS /
            // camera data — an empty header above just a Description looked broken.
            if !highlights.isEmpty || !details.isEmpty {
                lines.append("")
                lines.append("Metadata:")
                for h in highlights { lines.append("  • \(h)") }
                for d in details { lines.append("  • \(d)") }
            }
            if let description {
                lines.append("")
                lines.append("Description:")
                lines.append(description)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func displayName(for item: ClipboardItem) -> String {
        if let rel = item.representations["public.file-url"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let str = String(data: data, encoding: .utf8),
           let url = URL(string: str) {
            return url.lastPathComponent
        }
        return "Clipboard image"
    }

    private static func friendlyFormat(_ uti: String) -> String {
        switch uti {
        case "public.png":  return "PNG"
        case "public.jpeg": return "JPEG"
        case "public.heic", "public.heif": return "HEIC"
        case "public.tiff": return "TIFF"
        case "com.compuserve.gif": return "GIF"
        case "org.webmproject.webp", "public.webp": return "WebP"
        default:
            return uti.split(separator: ".").last.map { $0.uppercased() } ?? uti
        }
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        return "\(max(1, bytes / 1024)) KB"
    }
}

/// Surfaces the image's metadata as readable text — the inverse of
/// Strip-metadata. Shows name, format, dimensions, file size, colour info and
/// any embedded camera / date / GPS so you can see what an image carries.
struct ImageInfoAction: ClipboardAction {
    let id = "builtin.image.info"
    let title = "Image info"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Image clips only — reporting EXIF / dimensions / format of "a rich
        // document" is meaningless (the embedded image has no file metadata).
        context.contains(.image)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let text: String? = await runOffMain { ImageMetadata.report(for: item) }
        guard let text, !text.isEmpty else {
            return .failed(original: item, reason: "Couldn't read image info.", recovery: nil)
        }
        return .preview(makeTextItem(text, from: item))
    }
}

struct ImageStripMetadataAction: ClipboardAction {
    let id = "builtin.image.strip_metadata"; let title = "Strip metadata"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Image clips only — RTFD-embedding already drops EXIF, so this is a
        // no-op on rich, and it would otherwise extract the image and lose text.
        context.contains(.image)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let copy: ClipboardItem? = await runOffMain {
            // Read what's about to be removed BEFORE re-encoding — the NSImage
            // path below discards metadata, so inspect the original bytes.
            let highlights: [String]
            let hadMetadata: Bool
            if let raw = ImageMetadata.rawData(item) {
                highlights = ImageMetadata.privacyHighlights(of: raw)
                hadMetadata = ImageMetadata.hasAny(raw)
            } else {
                highlights = []; hadMetadata = false
            }
            guard let img = loadImage(item),
                  let tiff = img.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                return nil
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
            copy.previewText = Self.summary(highlights: highlights,
                                            hadMetadata: hadMetadata,
                                            kb: png.count / 1024)
            return copy
        }
        guard let copy = copy else {
            return .failed(original: item, reason: "Strip metadata failed", recovery: nil)
        }
        return .preview(copy)
    }

    /// Human summary of what was stripped — shown in the HUD and the Settings
    /// test panel so "remove metadata" produces a visible, explainable result
    /// rather than an image that looks identical to the input.
    static func summary(highlights: [String], hadMetadata: Bool, kb: Int) -> String {
        if !highlights.isEmpty {
            return "Removed: " + highlights.joined(separator: " · ") + "  →  now clean (\(kb) KB)"
        }
        if hadMetadata {
            return "Removed embedded metadata  →  now clean (\(kb) KB)"
        }
        return "No EXIF/GPS metadata found — this image was already clean (\(kb) KB)"
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
    let id = "builtin.image.to_ascii_art"
    let title = "ASCII art"
    let isLocal = true

    // Default column count. 40 fits comfortably in standard text fields
    // (chat messages, code comments, Twitter/X posts) where ASCII art
    // is most useful. Previously 100 — fine for terminal pastes but
    // unwieldy for inline contexts. A `maxWidth` parameter will surface
    // in #A16 (Built-in editor redesign) so users can dial it up.
    static let defaultOutWidth: Int = 40
    private static let charAspect: Double = 0.5

    // Tonal ramp, lightest → darkest. A finer 15-step ramp (vs the old 10)
    // gives smoother shading; structural edges are drawn separately with
    // directional glyphs (see `render`). Index 0 = space (lightest).
    private static let ramp: [Character] = Array(" .,:;-+=*oxX%#@")
    // Directional stroke glyphs by edge orientation bucket (y-down image
    // coordinates): 0 = horizontal "-", 1 = "\", 2 = vertical "|", 3 = "/".
    private static let edgeGlyphs: [Character] = ["-", "\\", "|", "/"]

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Image clips only — turning an embedded picture into a big ASCII block
        // inside a rich document is not a sensible in-place edit.
        context.contains(.image)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let result: String = await runOffMain {
            guard let img = loadImage(item) else { return "" }
            return Self.render(image: img, outWidth: Self.defaultOutWidth)
        }
        guard !result.isEmpty else {
            return .failed(original: item,
                           reason: "ASCII conversion produced empty output",
                           recovery: nil)
        }
        // Wrap in a monospaced NSAttributedString so the result pastes
        // into rich-text targets (Mail, Notes, Pages, Slack rich text,
        // Word) with the column alignment preserved. Plain-text targets
        // still receive the bare string via the .string representation.
        // Without the explicit monospaced font the receiving app would
        // apply its default proportional font and turn straight-edged
        // line art into wavy spaghetti.
        let attr = NSAttributedString(string: result, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        ])
        return .preview(makeRichTextItem(attr, from: item))
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
    static func render(image: NSImage, outWidth: Int = ImageToASCIIArtAction.defaultOutWidth) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else {
            return ""
        }
        let srcW = cg.width
        let srcH = cg.height
        let aspect = Double(srcH) / Double(srcW)
        let cols = max(8, outWidth)
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

        // Collect luminance per cell (top-down so the text reads in the same
        // orientation as the image — CG's bitmap origin is bottom-left).
        var lum = [Double](repeating: 0, count: rows * cols)
        for row in 0..<rows {
            let srcRow = rows - 1 - row
            for col in 0..<cols {
                lum[row * cols + col] = Double(pixels[srcRow * cols + col]) / 255.0
            }
        }

        // EXPRESSIVENESS: stretch contrast across the actual tonal range of the
        // image before mapping to glyphs. The old code applied a fixed
        // brightness cutoff tuned for white-background logos — on real photos
        // (mandrill, portraits) that crushed everything into a faint scatter of
        // dots. A robust 5th/95th-percentile stretch spreads the mid-tones over
        // the full ramp so the subject's form and texture actually read, while
        // a mild gamma lifts the mid-tones for extra punch.
        let sorted = lum.sorted()
        let lo = sorted[Int(Double(sorted.count - 1) * 0.05)]
        let hi = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let span = max(0.0001, hi - lo)

        // Stretched luminance per cell (0 = darkest … 1 = lightest), mid-lift.
        var sv = [Double](repeating: 0, count: rows * cols)
        for i in 0..<(rows * cols) {
            var s = (lum[i] - lo) / span
            s = min(1, max(0, s))
            sv[i] = pow(s, 0.85)
        }

        // STRUCTURE: Sobel edge detection. The biggest expressiveness win —
        // pure tonal ramps look like dithered noise; tracing strong contours
        // with directional glyphs (| - / \ chosen by edge orientation) makes the
        // result read as a *drawing*. Magnitude picks which cells are edges;
        // orientation picks the stroke. (Research: structure-based / Sobel ASCII
        // art — Asciimatic, img2ascii, et al.)
        @inline(__always) func sval(_ r: Int, _ c: Int) -> Double {
            sv[min(rows - 1, max(0, r)) * cols + min(cols - 1, max(0, c))]
        }
        var mags = [Double](repeating: 0, count: rows * cols)
        var glyphs = [Character](repeating: " ", count: rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                let gx = (sval(r-1, c+1) + 2*sval(r, c+1) + sval(r+1, c+1))
                       - (sval(r-1, c-1) + 2*sval(r, c-1) + sval(r+1, c-1))
                let gy = (sval(r+1, c-1) + 2*sval(r+1, c) + sval(r+1, c+1))
                       - (sval(r-1, c-1) + 2*sval(r-1, c) + sval(r-1, c+1))
                mags[r * cols + c] = (gx * gx + gy * gy).squareRoot()
                // Edge orientation = gradient direction + 90°, folded to [0, π).
                var a = atan2(gy, gx) + .pi / 2
                a = a.truncatingRemainder(dividingBy: .pi)
                if a < 0 { a += .pi }
                let seg = Int((a / .pi * 4.0).rounded()) % 4
                glyphs[r * cols + c] = edgeGlyphs[seg]
            }
        }
        // Edge threshold: the strongest ~18% of gradients, with an absolute
        // floor so flat / noisy regions never sprout stray strokes.
        let sortedMags = mags.sorted()
        let edgeThreshold = max(0.55, sortedMags[Int(Double(sortedMags.count - 1) * 0.82)])

        var grid = [[Character]](repeating: [Character](repeating: " ", count: cols),
                                  count: rows)
        let lastIdx = ramp.count - 1
        for row in 0..<rows {
            for col in 0..<cols {
                let i = row * cols + col
                if mags[i] >= edgeThreshold {
                    grid[row][col] = glyphs[i]          // structural stroke
                } else {
                    // Tonal fill: dark → dense glyph, bright → space.
                    let idx = Int(((1 - sv[i]) * Double(lastIdx)).rounded())
                    grid[row][col] = ramp[max(0, min(lastIdx, idx))]
                }
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
            ImageInfoAction(),
            ImageStripMetadataAction(),
            ImageResizeAction(maxLongSide: 1920),  // #A14 universal resize (image/files/richText)
            ImageCompressJPEGAction(),
            ImageGrayscaleAction(),
            ImageRotateRightAction(), ImageRotateLeftAction(),
            ImageInvertAction(),
            ImageToASCIIArtAction(),
            FileToImageAction()                // #A21 PDF page 1, HEIC/TIFF/BMP/GIF → PNG
        ]
    }
}
