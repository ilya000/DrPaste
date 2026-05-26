//
//  ImageActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Local image actions (Backlog #3). Через Vision (OCR/QR) и Core Image (filters).
//

import Foundation
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

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
    return nil
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
        context.contains(.image)
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
        context.contains(.image)
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
    let rep = NSCIImageRep(ciImage: output)
    let result = NSImage(size: rep.size)
    result.addRepresentation(rep)
    return result
}

struct ImageGrayscaleAction: ClipboardAction {
    let id = "builtin.image_grayscale"; let title = "Grayscale"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.image)
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
        context.contains(.image)
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

struct ImageRotate90Action: ClipboardAction {
    let id = "builtin.image_rotate"; let title = "Rotate 90° CW"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.image)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item),
              let tiff = img.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImg = bitmap.cgImage else {
            return .failed(original: item, reason: "Couldn't read image", recovery: nil)
        }
        let ciImage = CIImage(cgImage: cgImg)
        let rotated = ciImage.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        let rep = NSCIImageRep(ciImage: rotated)
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        guard let saved = saveImage(result, originalItem: item) else {
            return .failed(original: item, reason: "Rotation failed", recovery: nil)
        }
        return .preview(saved)
    }
}

struct ImageResize1920Action: ClipboardAction {
    let id = "builtin.image_resize_1920"; let title = "Resize to max 1920px"; let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        context.contains(.image)
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
        context.contains(.image)
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
        context.contains(.image)
    }
    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let img = loadImage(item),
              let tiff = img.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return .failed(original: item, reason: "Strip metadata failed", recovery: nil)
        }
        // PNG не несёт EXIF, повторная конвертация удаляет metadata
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

enum ImageActionsPack {
    static var all: [ClipboardAction] {
        [
            ImageOCRAction(), ImageDecodeQRAction(),
            ImageStripMetadataAction(), ImageResize1920Action(),
            ImageCompressJPEGAction(),
            ImageGrayscaleAction(), ImageRotate90Action(), ImageInvertAction()
        ]
    }
}
