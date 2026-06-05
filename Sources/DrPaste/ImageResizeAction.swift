//
//  ImageResizeAction.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Universal "Resize Images" action (#A14). Accepts three input
//  kinds:
//
//    • .image clip      — resizes the bytes in place
//    • .files clip      — walks the URL list, resizes any image
//                         files in place to temp copies, leaves
//                         non-image files alone (passed through).
//    • .richText clip   — walks NSAttributedString attachments,
//                         resizes each embedded image, rebuilds
//                         the rich text with the smaller attachments.
//
//  Target dimension: configurable via the descriptor parameter
//  `maxLongSide`. Default 1920. The longer side scales to the
//  target; the shorter side scales proportionally so aspect ratio
//  is preserved. **Never enlarges** — if the image's longer side
//  is already ≤ target, the image is passed through untouched.
//
//  Output format preservation: PNG → PNG, JPEG → JPEG (q=0.92),
//  HEIC → JPEG (HEIC encode is not universally supported from
//  NSBitmapImageRep), TIFF → PNG (TIFF rare on output).
//

import Foundation
import AppKit
import CoreImage

struct ImageResizeAction: ClipboardAction {
    let id = "builtin.image_resize_universal"
    let title = "Resize Images"
    let isLocal = true

    /// Max longer-side in pixels. Read from the action descriptor at
    /// runtime when this gets parameterised through #A16 (built-in
    /// editor redesign). For now, hardcoded default.
    let maxLongSide: Int

    init(maxLongSide: Int = 1920) {
        self.maxLongSide = maxLongSide
    }

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Three semantic shapes accepted:
        //   1. image clip
        //   2. files clip containing at least one image file
        //   3. richText clip containing at least one image attachment
        if context.contains(.image) { return true }
        if item.semantic == .files {
            let names = filesList(item).map { $0.lowercased() }
            return names.contains { isImageExtension($0) }
        }
        if item.semantic == .richText {
            return RichTextImageExtractor.hasEmbeddedImage(item)
        }
        return false
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        switch item.semantic {
        case .image:
            return await runImage(on: item)
        case .files:
            return await runFiles(on: item)
        case .richText:
            return await runRichText(on: item)
        default:
            return .failed(original: item,
                          reason: "Resize Images requires an image, files, or rich-text input.",
                          recovery: nil)
        }
    }

    // MARK: image path

    private func runImage(on item: ClipboardItem) async -> ApplyOutcome {
        let result: (data: Data?, fmt: String?) = await runOffMain {
            guard let img = self.loadOriginalImage(item) else { return (nil, nil) }
            let inFormat = item.imageFormat ?? self.detectFormat(for: item)
            guard let (resized, outFormat) = self.resizeImage(img, originalFormat: inFormat) else {
                return (nil, nil)
            }
            return (resized, outFormat)
        }
        guard let data = result.data, let fmt = result.fmt else {
            return .failed(original: item, reason: "Resize: couldn't read image bytes.", recovery: nil)
        }
        // Build the preview clip with the resized bytes. id / createdAt
        // are `let` on ClipboardItem and the existing helpers
        // (saveImage in ImageActions.swift, makeTextItem in Actions.swift)
        // also leave them on the original — a preview-transformation is
        // a different shape of the same logical clip.
        var copy = item
        let typeKey = fmt == "JPEG" ? "public.jpeg" : "public.png"
        let blobName = "resize-\(UUID().uuidString.prefix(8)).\(fmt == "JPEG" ? "jpg" : "png")"
        let url = AppStorage.blobsDir.appendingPathComponent(blobName)
        try? data.write(to: url)
        copy.representations = [typeKey: blobName]
        copy.typesOrdered = [typeKey]
        copy.imageFormat = fmt
        copy.originalImageFileSize = data.count
        return .preview(copy)
    }

    // MARK: files path

    private func runFiles(on item: ClipboardItem) async -> ApplyOutcome {
        let files = filesList(item)
        guard !files.isEmpty else {
            return .failed(original: item, reason: "Resize Images: no file paths in clip.", recovery: nil)
        }
        let resized: [String] = await runOffMain {
            return files.map { path -> String in
                guard self.isImageExtension(path.lowercased()) else { return path }
                let url = URL(fileURLWithPath: path)
                guard let img = NSImage(contentsOf: url) else { return path }
                let ext = url.pathExtension.lowercased()
                let inFormat: String = ["jpg", "jpeg"].contains(ext) ? "JPEG" : "PNG"
                guard let (data, outFormat) = self.resizeImage(img, originalFormat: inFormat) else {
                    return path
                }
                let outExt = outFormat == "JPEG" ? "jpg" : "png"
                let outName = url.deletingPathExtension().lastPathComponent + "-resized." + outExt
                let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(outName)
                do {
                    try data.write(to: outURL)
                    return outURL.path
                } catch {
                    return path
                }
            }
        }
        var copy = item
        copy.previewText = resized.joined(separator: ", ")
        return .preview(copy)
    }

    // MARK: rich text path

    private func runRichText(on item: ClipboardItem) async -> ApplyOutcome {
        // Walk attributed string attachments; replace each image
        // attachment with a resized PNG re-attachment. Non-image
        // runs pass through untouched.
        // The closure returns flat-RTFD `Data` (Sendable) rather than the
        // NSAttributedString itself — NSAttributedString is not Sendable on
        // macOS, so returning it across runOffMain's detached-task boundary
        // is an error under the Swift 6 language mode. We re-hydrate the
        // attributed string on the main side from the flat-RTFD bytes.
        let result: Data? = await runOffMain {
            guard let attr = self.loadAttributedString(item) else { return nil }
            let out = NSMutableAttributedString(attributedString: attr)
            var anyReplaced = false
            out.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: out.length),
                                   options: []) { value, range, _ in
                guard let attachment = value as? NSTextAttachment,
                      let fileWrapper = attachment.fileWrapper,
                      let data = fileWrapper.regularFileContents,
                      let image = NSImage(data: data) else { return }
                guard let (resized, fmt) = self.resizeImage(image, originalFormat: "PNG") else { return }
                let newName = (fileWrapper.preferredFilename ?? "image") + "-resized"
                let newWrapper = FileWrapper(regularFileWithContents: resized)
                newWrapper.preferredFilename = newName + (fmt == "JPEG" ? ".jpg" : ".png")
                let newAttachment = NSTextAttachment(fileWrapper: newWrapper)
                let replacement = NSAttributedString(attachment: newAttachment)
                out.replaceCharacters(in: range, with: replacement)
                anyReplaced = true
            }
            guard anyReplaced else { return nil }
            return try? out.data(from: NSRange(location: 0, length: out.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        }
        guard let rtfd = result,
              let attr = try? NSAttributedString(
                  data: rtfd,
                  options: [.documentType: NSAttributedString.DocumentType.rtfd],
                  documentAttributes: nil) else {
            return .failed(original: item, reason: "Resize Images: no embedded images to resize.", recovery: nil)
        }
        return .preview(makeRichTextItem(attr, from: item))
    }

    // MARK: helpers

    /// Resize keeping aspect ratio. Never enlarges. Returns the
    /// encoded data + the chosen output format string.
    private func resizeImage(_ image: NSImage, originalFormat: String) -> (Data, String)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let srcW = cg.width
        let srcH = cg.height
        let longerSide = max(srcW, srcH)
        // Never enlarge.
        guard longerSide > self.maxLongSide else {
            // Return the source bytes as-is in the original format.
            return encodeImage(cg, format: originalFormat)
        }
        let scale = Double(self.maxLongSide) / Double(longerSide)
        let dstW = max(1, Int(Double(srcW) * scale))
        let dstH = max(1, Int(Double(srcH) * scale))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let resized = ctx.makeImage() else { return nil }
        return encodeImage(resized, format: originalFormat)
    }

    private func encodeImage(_ cgImage: CGImage, format: String) -> (Data, String)? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        switch format.uppercased() {
        case "JPEG", "HEIC":
            if let d = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
                return (d, "JPEG")
            }
        default:
            if let d = rep.representation(using: .png, properties: [:]) {
                return (d, "PNG")
            }
        }
        return nil
    }

    private func detectFormat(for item: ClipboardItem) -> String {
        if item.representations["public.jpeg"] != nil { return "JPEG" }
        if item.representations["public.heic"] != nil { return "HEIC" }
        if item.representations["public.tiff"] != nil { return "TIFF" }
        return "PNG"
    }

    private func loadOriginalImage(_ item: ClipboardItem) -> NSImage? {
        let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
        for type in imageTypes {
            if let rel = item.representations[type],
               let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
               let img = NSImage(data: data) {
                return img
            }
        }
        // Fallback: thumbnail.
        if let rel = item.previewImageRel {
            return NSImage(contentsOf: AppStorage.imagesDir.appendingPathComponent(rel))
        }
        return nil
    }

    private func loadAttributedString(_ item: ClipboardItem) -> NSAttributedString? {
        for type in ["com.apple.flat-rtfd", "public.rtfd", "public.rtf"] {
            if let rel = item.representations[type],
               let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)) {
                let docType: NSAttributedString.DocumentType =
                    type.contains("rtfd") ? .rtfd : .rtf
                if let attr = try? NSAttributedString(
                    data: data,
                    options: [.documentType: docType],
                    documentAttributes: nil
                ) {
                    return attr
                }
            }
        }
        return nil
    }

    private func filesList(_ item: ClipboardItem) -> [String] {
        guard let s = item.previewText else { return [] }
        return s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func isImageExtension(_ path: String) -> Bool {
        let extensions = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
        let lower = path.lowercased()
        return extensions.contains { lower.hasSuffix("." + $0) }
    }
}
