//
//  RichTextPreviewView.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  NSViewRepresentable wrapper around NSTextView for full-fidelity rich text rendering.
//  SwiftUI's Text(AttributedString) loses font traits (bold/italic) and other attributes
//  when converting NSAttributedString through `\.swiftUI` scope. NSTextView renders the
//  native NSAttributedString as-is with all attributes preserved.
//

import SwiftUI
import AppKit

struct RichTextPreviewView: NSViewRepresentable {
    let attributedString: NSAttributedString
    var fontScale: CGFloat = 1.0

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainer?.lineFragmentPadding = 6
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let prepared = Self.remapStaticForegroundColors(
            scaleAttributedString(attributedString, by: fontScale)
        )
        textView.textStorage?.setAttributedString(prepared)

        // Monospaced blocks (ASCII art, code) must NOT word-wrap — a wrapped
        // line of ASCII art is unreadable. Let them extend full-width and
        // scroll horizontally instead so the columns stay intact regardless of
        // how narrow the preview pane is. Proportional rich text keeps the
        // default wrapping behaviour.
        let mono = isMonospaceDominant(prepared)
        textView.isHorizontallyResizable = mono
        scrollView.hasHorizontalScroller = mono
        if let container = textView.textContainer {
            container.widthTracksTextView = !mono
            if mono {
                container.size = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                        height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }

    /// True when the string's first character is set in a monospaced font —
    /// our ASCII-art and code-block previews are uniformly monospaced, so this
    /// one-sample check reliably distinguishes them from proportional prose.
    private func isMonospaceDominant(_ attr: NSAttributedString) -> Bool {
        guard attr.length > 0,
              let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.monoSpace)
    }

    /// Apply fontScale by multiplying every `.font` attribute's pointSize.
    private func scaleAttributedString(_ src: NSAttributedString, by scale: CGFloat) -> NSAttributedString {
        guard scale != 1.0, src.length > 0 else { return src }
        let mutable = NSMutableAttributedString(attributedString: src)
        mutable.enumerateAttribute(.font,
                                   in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            if let font = value as? NSFont {
                let scaled = NSFont(descriptor: font.fontDescriptor,
                                    size: font.pointSize * scale) ?? font
                mutable.addAttribute(.font, value: scaled, range: range)
            }
        }
        return mutable
    }

    /// RTF documents embed a fixed body color (typically black). In Dark Mode
    /// that color renders as black-on-near-black and is illegible. Replace any
    /// non-catalog (i.e. non-dynamic) foreground color with `NSColor.labelColor`
    /// so the text adapts to the system appearance. Catalog colors such as
    /// `.linkColor`, `.systemBlue`, etc. already adapt and are left alone.
    /// Ranges with no explicit `.foregroundColor` get `.labelColor` set so the
    /// text is drawn in the adaptive label color rather than NSTextView's
    /// default of `textColor` (which an upstream caller could have overridden).
    static func remapStaticForegroundColors(_ src: NSAttributedString) -> NSAttributedString {
        guard src.length > 0 else { return src }
        let mutable = NSMutableAttributedString(attributedString: src)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if let color = value as? NSColor {
                if color.type != .catalog {
                    mutable.addAttribute(.foregroundColor,
                                         value: NSColor.labelColor,
                                         range: range)
                }
            } else {
                mutable.addAttribute(.foregroundColor,
                                     value: NSColor.labelColor,
                                     range: range)
            }
        }
        // Strip the source's text / page BACKGROUND colours so the themed HUD
        // background shows through. Without this, rich text copied from an app
        // with a white page background renders a solid white box — and since the
        // foreground was just remapped to the adaptive labelColor (which is
        // WHITE under the dark-appearance Ocean / Dark / Vivid themes), that
        // produced unreadable white-on-white. A preview is for identifying a
        // clip, so dropping highlight / page fills is the right trade-off.
        mutable.removeAttribute(.backgroundColor, range: fullRange)
        return mutable
    }
}

/// Helper to load NSAttributedString from a ClipboardItem's
/// richest available representation. Priority order:
///
///   1. `com.apple.flat-rtfd` — RTFD with inline FileWrapper
///      attachments. Required to render the ⌥⌘S accumulator's
///      image+text composites correctly (RTF strips attachments,
///      HTML loses them when they were written as data: URIs but
///      the receiving end couldn't resolve them).
///   2. `public.rtf` — plain RTF, no attachments. Used when the
///      source app didn't produce RTFD (typical web copy).
///   3. `public.html` — HTML rich text. Images may be lost if the
///      source kept them external; that's the producer's fault,
///      we render whatever made it through.
enum RichTextLoader {
    static func attributedString(from item: ClipboardItem) -> NSAttributedString? {
        // 1. Flat-RTFD with attachments. `NSAttributedString(rtfd:)`
        //    accepts the flat-package Data form pasteboards use,
        //    rehydrating embedded image FileWrappers into live
        //    NSTextAttachment instances. Try BOTH RTFD UTIs — most apps
        //    publish `com.apple.flat-rtfd`, but some use `public.rtfd`; reading
        //    only the former silently dropped embedded images for those apps
        //    (the preview fell through to `public.rtf`, which has none).
        for key in ["com.apple.flat-rtfd", "public.rtfd"] {
            if let rel = item.representations[key],
               let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
               let attr = NSAttributedString(rtfd: data, documentAttributes: nil) {
                return attr
            }
        }
        // 2. Plain RTF (no attachments).
        if let rel = item.representations["public.rtf"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil) {
            return attr
        }
        // 3. HTML.
        if let rel = item.representations["public.html"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) {
            return attr
        }
        return nil
    }
}
