//
//  TextActions.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Plain-text actions that cannot be expressed purely as transformations.
//
//  The case-conversion, sort/unique, base64/url-percent, slugify, word-count
//  family used to live here as hardcoded ClipboardAction structs. They are now
//  bundled descriptors in DefaultTransformationSeed using stable `builtin.*`
//  IDs, so all user customizations (titles, hotkeys, order, enabled) carry
//  over without remapping.
//
//  This file now hosts only Generate QR — text → image — because it produces
//  an image item rather than a pure text transformation and doesn't fit the
//  TransformationEngine model.
//

import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Generate QR (highlight feature)

struct GenerateQRAction: ClipboardAction {
    let id = "builtin.text.generate_qr"
    let title = "QR code"
    let isLocal = true
    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard context.contains(.qrEligible) else { return false }
        // #A78 — QR is for "scan this link with your phone": URLs only. On
        // arbitrary short prose a QR chip is noise, and code / JSON / tables are
        // nonsensical to encode.
        return item.semantic == .url
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

        // Save PNG to imagesDir and return an item with updated previewImageRel.
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
        // Full raw representation: PNG stored as public.png in blob storage.
        let pngRel = "\(UUID().uuidString)-qr.png.bin"
        try? png.write(to: AppStorage.blobsDir.appendingPathComponent(pngRel))
        copy.representations = ["public.png": pngRel]
        copy.typesOrdered = ["public.png"]
        return .preview(copy)
    }
}

// MARK: - Registry pack

enum TextActionsPack {
    static var all: [ClipboardAction] {
        [GenerateQRAction(),
         UnitConversionAction(),   // #A20 metric ↔ imperial
         IPALocalAction()]         // offline English → IPA (CMUdict)
    }
}
