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
        let scaled = scaleAttributedString(attributedString, by: fontScale)
        textView.textStorage?.setAttributedString(scaled)
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
}

/// Helper to load NSAttributedString from a ClipboardItem's RTF / HTML representation.
enum RichTextLoader {
    static func attributedString(from item: ClipboardItem) -> NSAttributedString? {
        if let rel = item.representations["public.rtf"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil) {
            return attr
        }
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
