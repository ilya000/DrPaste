//
//  ImageRenderer.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Shared CGContext-based image rendering helpers (#A47).
//
//  Replaces the legacy `NSImage.lockFocus()` path which is:
//    • Main-thread only (deadlocks any background-task caller).
//    • Backing-scale fragile (output dimensions follow the focused
//      view's contentsScale, not the requested pixel size).
//    • Locked to the current NSGraphicsContext stack semantics
//      (unsafe under nested redraws).
//
//  CGContext is:
//    • Thread-safe (no global graphics-context stack).
//    • Pixel-deterministic (we ask for integer pixel dimensions and
//      get exactly those bytes).
//    • Colour-space deterministic (sRGB by default, no display
//      profile sneaking in).
//
//  All four legacy lockFocus call sites (ImageActions saveImage,
//  ClipboardModel makeThumbnail, AppendAccumulator downscale, the
//  PDF page 1 renderer in FileToImageAction, and the synthesised
//  sample images in ActionTestSamples) now route through this file.
//

import AppKit
import CoreImage

enum ImageRenderer {

    /// Downscale an NSImage to a target longer-side dimension while
    /// preserving aspect ratio. Never enlarges. Returns the source
    /// image untouched when it's already at or below the target.
    /// Uses Lanczos-equivalent interpolation (CGContext's high
    /// quality setting) so text-heavy images stay legible.
    ///
    /// - Parameters:
    ///   - image: source NSImage. Must have a backing representation
    ///     that produces a CGImage (NSImages backed solely by an
    ///     NSCustomImageRep block return nil and the source is
    ///     passed through).
    ///   - maxSide: target longer-side in points (== pixels for
    ///     the deterministic output). Common values: 600 (thumbnail),
    ///     1920 (universal resize), 2048 (AI upload preflight).
    static func downscale(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        guard longSide > maxSide else { return image }
        let ratio = maxSide / longSide
        let dstW = max(1, Int(floor(size.width * ratio)))
        let dstH = max(1, Int(floor(size.height * ratio)))
        guard let cg = image.cgImage(forProposedRect: nil,
                                     context: nil,
                                     hints: nil) else {
            // Fall back to the source — CIImage path could handle
            // this but it's a long tail (NSImage with only a custom
            // drawing block) we don't otherwise produce.
            return image
        }
        return drawCGImage(cg, targetWidth: dstW, targetHeight: dstH)
            ?? image
    }

    /// Draw an existing CGImage into a fresh sRGB-backed bitmap of
    /// the requested pixel size and return the result wrapped in an
    /// NSImage. The wrapped image carries a single bitmap
    /// representation whose pixelsWide / pixelsHigh exactly match the
    /// requested dimensions — pasteboards round-trip the bytes
    /// without surprise resamples.
    static func drawCGImage(_ source: CGImage,
                            targetWidth: Int,
                            targetHeight: Int) -> NSImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                      ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0,
                                    width: targetWidth,
                                    height: targetHeight))
        guard let out = ctx.makeImage() else { return nil }
        let pointSize = NSSize(width: targetWidth, height: targetHeight)
        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = pointSize
        let nsImage = NSImage(size: pointSize)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    /// Encode an NSImage as PNG `Data`. Returns nil only when the
    /// source has no CGImage representation (extremely rare —
    /// custom-drawing-block-only NSImages).
    static func pngData(from image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil,
                                     context: nil,
                                     hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    /// Synthesise a fresh sRGB-backed NSImage by drawing into a
    /// transient CGContext. Replaces the `NSImage(size:)` +
    /// `lockFocus()` + `draw(...)` + `unlockFocus()` recipe with a
    /// thread-safe path. The caller's closure receives a CGContext
    /// flipped to "top-left origin" semantics — matching the
    /// NSGraphicsContext that `lockFocus` produced — so existing
    /// drawing code (NSAttributedString.draw, NSImage.draw, etc.)
    /// can be moved over without coordinate-system math.
    ///
    /// - Parameters:
    ///   - size: output pixel size.
    ///   - opaque: when true, the bitmap has no alpha channel and
    ///     the background is pre-filled white. Use for screenshots
    ///     / photo content where transparency doesn't apply.
    ///     When false (default), the background is transparent and
    ///     the caller is responsible for filling it.
    ///   - draw: closure invoked with a CGContext positioned in
    ///     top-left origin (NSGraphicsContext-compatible).
    static func render(size: NSSize,
                       opaque: Bool = false,
                       draw: (CGContext) -> Void) -> NSImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                      ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = opaque
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.interpolationQuality = .high
        if opaque {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // Bridge the CGContext into an NSGraphicsContext stack so
        // existing draw(in:) code that expects a focused graphics
        // context (NSImage.draw, NSAttributedString.draw,
        // NSBezierPath, ...) still works. The flipped-y NSImage
        // coordinate space is applied automatically.
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let out = ctx.makeImage() else { return nil }
        let nsImage = NSImage(size: NSSize(width: width, height: height))
        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = NSSize(width: width, height: height)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
