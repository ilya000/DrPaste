//
//  AppendAccumulator.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  ⌥⌘S Append Copy — merge clips on the system pasteboard so a
//  sequence of presses accumulates into a single composite clip.
//
//  Strategy (rich-text accumulator + files-strict path):
//
//    • If the FIRST clip in the session is a file/URL list, the
//      session is locked to file-mode. Subsequent presses must
//      also produce files; anything else is rejected with a
//      failure sound and the accumulator is left untouched.
//
//    • Otherwise the accumulator is an NSAttributedString. Plain
//      text, rich text, and images all naturally compose:
//        — plain text appends as an unstyled run
//        — rich text appends with its attributes preserved (RTFD)
//        — images append as NSTextAttachment instances (PNG,
//          downscaled to max 1920px on the longer side so the
//          pasteboard blob doesn't explode after 5–6 screenshots)
//
//    • Pasteboard write order matches macOS's "best representation
//      first" convention: RTFD (lossless, attachments preserved) →
//      RTF (no attachments) → HTML (web targets, images embedded
//      as data: URIs) → plain text (last-resort fallback,
//      attachments dropped). Target apps pick whichever they
//      understand best.
//

import AppKit

enum AppendAccumulator {

    // MARK: - Read

    /// Largest dimension we keep when embedding an image into the
    /// rich-text accumulator. A few stitched 4K screenshots add up
    /// to tens of megabytes of pasteboard payload very quickly;
    /// 1920 keeps quality acceptable while the blob stays sane.
    static let maxImageDimension: CGFloat = 1920

    /// Snapshot whatever the pasteboard currently holds as an
    /// `NSAttributedString` for merge purposes. Tries every richness
    /// tier in order — RTFD first so attachments survive, then RTF,
    /// HTML, plain text, and finally a raw image (which becomes a
    /// single-attachment attributed string).
    static func readAttributed(from pb: NSPasteboard) -> NSAttributedString? {
        // RTFD with attachments.
        if let data = pb.data(forType: .rtfd),
           let s = NSAttributedString(rtfd: data, documentAttributes: nil) {
            return s
        }
        // Plain RTF (no attachments).
        if let data = pb.data(forType: .rtf),
           let s = NSAttributedString(rtf: data, documentAttributes: nil) {
            return s
        }
        // HTML (browser rich-text copy).
        if let data = pb.data(forType: .html),
           let s = NSAttributedString(html: data, documentAttributes: nil) {
            return s
        }
        // Image — single attachment.
        if let img = NSImage(pasteboard: pb) {
            return attributedString(forImage: img)
        }
        // Plain text fallback.
        if let str = pb.string(forType: .string) {
            return NSAttributedString(string: str)
        }
        return nil
    }

    /// Build an attributed string consisting of one inline image
    /// attachment, downscaled to fit within `maxImageDimension` on
    /// the longer side. Used both when seeding the accumulator
    /// from an image clip and when appending images to an existing
    /// text accumulator.
    ///
    /// IMPORTANT: must construct via `NSTextAttachment(fileWrapper:)`
    /// with a real PNG `FileWrapper`, NOT via `attachmentCell =
    /// NSTextAttachmentCell(imageCell:)`. The cell-based form
    /// renders correctly on screen but the RTFD encoder silently
    /// emits an empty placeholder for it, so when we round-trip
    /// the merged accumulator through the pasteboard the image
    /// drops out and the next ⌥⌘S sees an empty `prevAttr` (or a
    /// text-only one). The fileWrapper form is the only path that
    /// survives RTFD `attr.rtfd(from:documentAttributes:)`.
    static func attributedString(forImage src: NSImage) -> NSAttributedString {
        let resized = downscale(src, maxSide: maxImageDimension)
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            // Encoding failed — fall back to an empty attributed
            // string. Caller continues to merge whatever else is
            // around it; we lose just this one image rather than
            // crash the whole append.
            return NSAttributedString()
        }
        let wrapper = FileWrapper(regularFileWithContents: pngData)
        wrapper.preferredFilename = "image-\(UUID().uuidString.prefix(8)).png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        return NSAttributedString(attachment: attachment)
    }

    /// Vendor downscale — only shrinks, never upscales. Re-encodes
    /// to PNG so the embedded blob is a single deterministic format
    /// (RTFD doesn't care, but predictable size accounting matters
    /// when several images stack up in one accumulator).
    ///
    /// #A47 — Migrated from NSImage.lockFocus → ImageRenderer.downscale
    /// (CGContext-backed). Background-thread safe; pixel-deterministic
    /// across Retina / non-Retina displays.
    static func downscale(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        return ImageRenderer.downscale(image, maxSide: maxSide)
    }

    // MARK: - Append

    /// Append `new` to `existing` with a newline separator (skipped
    /// when `existing` is empty). The newline keeps stacked clips
    /// visually distinct when pasted into a rich-text editor.
    static func append(_ new: NSAttributedString,
                       to existing: NSAttributedString) -> NSAttributedString {
        let combined = NSMutableAttributedString(attributedString: existing)
        if combined.length > 0 {
            combined.append(NSAttributedString(string: "\n"))
        }
        combined.append(new)
        return combined
    }

    // MARK: - Write

    /// Write the accumulator out as the richest pasteboard payload
    /// we can manage: RTFD (attachments preserved) → RTF (no
    /// attachments) → HTML (browser-friendly, images inlined as
    /// data: URIs) → plain text. macOS picks the best one the
    /// target app advertises support for.
    static func write(_ attr: NSAttributedString, to pb: NSPasteboard) {
        pb.clearContents()
        let range = NSRange(location: 0, length: attr.length)

        // RTFD — primary, supports attachments.
        if let rtfd = attr.rtfd(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]) {
            pb.setData(rtfd, forType: .rtfd)
        }
        // Plain RTF — fallback for apps that take RTF but not RTFD.
        // Attachments are stripped automatically by the encoder.
        if let rtf = attr.rtf(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf
        ]) {
            pb.setData(rtf, forType: .rtf)
        }
        // HTML — browser rich-text editors. Images inlined as
        // data: URIs so the receiving app doesn't need to fetch
        // anything separately. `data(from:documentAttributes:)`
        // is throwing; failures are non-fatal here (we still
        // wrote RTFD/RTF/plain text above) so we swallow with try?.
        if let html = try? attr.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.html
        ]) {
            pb.setData(html, forType: .html)
        }
        // Plain text — last-resort fallback. Attachments drop out
        // (NSAttributedString.string substitutes 0xFFFC at each
        // attachment position; we strip those so plain-text targets
        // don't see garbage characters).
        let plain = attr.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        pb.setString(plain, forType: .string)
    }

    /// Files-only merge path — keeps the file-mode accumulator
    /// strict. Returns the combined URL list, or nil if the new
    /// snapshot doesn't carry files.
    static func mergeFiles(previous: [URL], pasteboard pb: NSPasteboard) -> [URL]? {
        guard let new = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !new.isEmpty else {
            return nil
        }
        return previous + new
    }

    // MARK: - Image-file bridging

    /// File extensions that we treat as "image files" for the
    /// purpose of the cross-track bridge (files → rich-text when
    /// the file IS visually an image, rich-text → files when the
    /// incoming files are all images).  Kept as a static set so
    /// the lookup is O(1) — checked once per URL on every append.
    /// HEIC included because that's the default screenshot format
    /// on recent iPhones; SVG omitted because NSImage doesn't
    /// render it natively.
    static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "heif", "webp"
    ]

    /// True if the URL's path extension matches a known image
    /// format. Case-insensitive. Used to decide whether a file
    /// can legitimately be re-interpreted as an inline image
    /// attachment.
    static func isImageURL(_ url: URL) -> Bool {
        imageFileExtensions.contains(url.pathExtension.lowercased())
    }

    /// Convert a list of image-file URLs into an attributed
    /// string of inline NSTextAttachment instances (one per
    /// file, separated by newlines). Returns nil if no URL
    /// produced a loadable NSImage (corrupt files, permission
    /// problems, etc.). Each successful image is downscaled and
    /// PNG-encoded by `attributedString(forImage:)` so the
    /// resulting RTFD round-trips correctly.
    static func attributedString(forImageFiles files: [URL]) -> NSAttributedString? {
        let composed = NSMutableAttributedString()
        for url in files {
            guard let image = NSImage(contentsOf: url) else { continue }
            if composed.length > 0 {
                composed.append(NSAttributedString(string: "\n"))
            }
            composed.append(attributedString(forImage: image))
        }
        return composed.length > 0 ? composed : nil
    }

    // MARK: - ClipboardItem bridge (HUD accumulator)

    /// Convert a stored ClipboardItem into the richest
    /// `NSAttributedString` we can produce. Used by the in-HUD
    /// ⌥⌘S accumulator so merging history rows preserves rich
    /// formatting and inline images instead of flattening
    /// everything to `previewText`. Priority:
    ///
    ///   1. RTFD / RTF / HTML if any rich representation lives
    ///      in the item's blob storage (delegates to
    ///      RichTextLoader).
    ///   2. Image thumbnail or full image blob if the item is
    ///      an image clip — wrapped in a single inline
    ///      `NSTextAttachment`.
    ///   3. `previewText` as a last-resort plain string.
    static func attributedString(from item: ClipboardItem) -> NSAttributedString {
        if let rich = RichTextLoader.attributedString(from: item) {
            return rich
        }
        if let imageRel = item.previewImageRel,
           let img = NSImage(contentsOf: AppStorage.imagesDir.appendingPathComponent(imageRel)) {
            return attributedString(forImage: img)
        }
        // Probe representations for a raw image blob (the
        // previewImageRel above is the thumbnail; for some
        // items the full image may be hiding in representations
        // under public.png/jpeg/tiff without a thumbnail).
        for type in ["public.png", "public.jpeg", "public.tiff", "public.heic"] {
            guard let rel = item.representations[type],
                  let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
                  let img = NSImage(data: data) else { continue }
            return attributedString(forImage: img)
        }
        return NSAttributedString(string: item.previewText ?? "")
    }
}
