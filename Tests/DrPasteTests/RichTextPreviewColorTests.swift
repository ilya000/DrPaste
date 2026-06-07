//
//  RichTextPreviewColorTests.swift
//  DrPasteTests
//
//  The HUD rich-text preview must stay readable on every theme. A clip copied
//  from an app with a white page background used to render white-on-white under
//  the dark-appearance Ocean / Dark / Vivid themes (labelColor resolves white).
//

import XCTest
import AppKit
@testable import DrPaste

final class RichTextPreviewColorTests: XCTestCase {

    func testStripsSourceBackgroundColor() {
        let attr = NSMutableAttributedString(string: "hello", attributes: [
            .foregroundColor: NSColor.white,        // source white text
            .backgroundColor: NSColor.white         // source white page bg
        ])
        let out = RichTextPreviewView.remapStaticForegroundColors(attr)
        let full = NSRange(location: 0, length: out.length)
        // No background colour survives — the themed HUD bg shows through.
        out.enumerateAttribute(.backgroundColor, in: full) { value, _, _ in
            XCTAssertNil(value, "source background colour leaked into the preview")
        }
        // Static foreground is remapped to the adaptive labelColor.
        let fg = out.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(fg, NSColor.labelColor)
    }

    func testKeepsAdaptiveForegroundButStillStripsBackground() {
        let attr = NSMutableAttributedString(string: "hi", attributes: [
            .foregroundColor: NSColor.labelColor,   // already adaptive — keep
            .backgroundColor: NSColor.yellow        // highlight — drop for readability
        ])
        let out = RichTextPreviewView.remapStaticForegroundColors(attr)
        XCTAssertEqual(out.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       NSColor.labelColor)
        XCTAssertNil(out.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }
}
