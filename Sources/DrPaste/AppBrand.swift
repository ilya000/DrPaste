//
//  AppBrand.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Единая точка правды для product name, иконок, версии и About credits.
//  Поменяй здесь — обновится во всём UI.
//

import AppKit
import SwiftUI

enum AppBrand {
    static let name: String = "DrPaste"
    static let version: String = "0.8.0"
    static let tagline: String = "Press, browse, paste — the Paste gesture, extended"

    static let githubURL = "https://github.com/ilya000/DrPaste"

    /// Цветная иконка для HUD header / About panel.
    static var nsIcon: NSImage {
        if let img = NSImage(named: "AppIcon") { return img }
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: name)
            ?? NSImage()
    }

    /// SwiftUI-обёртка для HUD header (цветная).
    static var icon: Image {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "svg"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "doc.on.clipboard.fill")
    }

    /// Template-иконка для menu bar status item (Backlog #5).
    /// Монохром, isTemplate=true → macOS сам красит под appearance.
    /// Tight viewBox без лишнего padding → стандартная ширина status item.
    static var menuBarIcon: NSImage {
        let img: NSImage
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let i = NSImage(contentsOf: url) {
            img = i
        } else if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg"),
                  let i = NSImage(contentsOf: url) {
            img = i
        } else {
            img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: name)
                ?? NSImage()
        }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }

    /// Полный credits для About panel (Backlog #6).
    static var aboutCredits: NSAttributedString {
        let body = NSMutableAttributedString()

        body.append(NSAttributedString(string: "\(tagline)\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))

        body.append(NSAttributedString(string: """
        Copyright © 2026 iLya Os.
        Licensed under GNU GPL v3.0-or-later with attribution requirement.


        """))

        // Clickable links
        appendLink(to: body, label: "Source code", url: githubURL)
        body.append(NSAttributedString(string: "\n\n"))

        body.append(NSAttributedString(string: "Acknowledgements\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
        ]))

        body.append(NSAttributedString(string: """

        DrPaste's design is inspired by Flycut, Maccy, Paste, and Raycast — \
        open clipboard utilities that paved the way for keyboard-first \
        paste UX on macOS.

        Built on Apple's AppKit, SwiftUI, Core Image, Vision, and Carbon HIToolbox.

        Thanks to the open-source community for showing what's possible.
        """))

        return body
    }

    private static func appendLink(to body: NSMutableAttributedString, label: String, url: String) {
        let str = NSMutableAttributedString(string: "\(label): \(url)")
        if let range = str.string.range(of: url) {
            let nsRange = NSRange(range, in: str.string)
            str.addAttribute(.link, value: url, range: nsRange)
            str.addAttribute(.foregroundColor, value: NSColor.linkColor, range: nsRange)
        }
        body.append(str)
    }
}
