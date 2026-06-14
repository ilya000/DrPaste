//
//  AppBrand.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Single source of truth for product name, icons, version, and About credits.
//  Updating this file propagates the change throughout the UI.
//

import AppKit
import SwiftUI

enum AppBrand {
    static let name: String = "DrPaste"
    static let version: String = "0.59.0"
    static let tagline: String = "Keep your train of thought intact"

    static let githubURL = "https://github.com/ilya000/DrPaste"

    /// The ctrl8 collection — every tool by iLya Os in one place. Surfaced at the
    /// top of the About panel so users of any app can discover the others.
    static let ctrl8URL = "https://www.ctrl8.com"

    /// Color icon for the HUD header, About panel, Dock, and Cmd-Tab.
    ///
    /// Resource lookup order, first match wins:
    ///   1. NSImage(named: "AppIcon") — Asset Catalog hit (signed builds)
    ///   2. AppIcon.icns               — multi-resolution icon set
    ///   3. AppIcon@2x.png             — Retina raster
    ///   4. AppIcon.png                — single-resolution raster
    ///   5. AppIcon.svg                — vector fallback / placeholder
    ///   6. SF Symbol "doc.on.clipboard.fill" — last-resort
    static var nsIcon: NSImage {
        if let img = NSImage(named: "AppIcon") { return img }
        for ext in ["icns", "png", "svg"] {
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: name)
            ?? NSImage()
    }

    /// SwiftUI wrapper of the color icon — reuses the same NSImage lookup so
    /// HUD / Welcome / About displays are consistent with the Dock icon.
    static var icon: Image {
        Image(nsImage: nsIcon)
    }

    /// Installs the color icon as the running application's icon. Affects the
    /// About panel header and the Cmd-Tab switcher entry. Call from
    /// `applicationDidFinishLaunching`. Until DrPaste ships as a signed .app
    /// bundle with an .icns inside Contents/Resources, this is the only way
    /// the Dock can be persuaded to display the branded icon.
    static func installApplicationIcon() {
        NSApplication.shared.applicationIconImage = nsIcon
    }

    /// Template icon for the menu bar status item. Monochrome with isTemplate=true
    /// so macOS tints it to match the system appearance (black in light mode,
    /// white in dark mode, accent when the status menu is open). Tight viewBox
    /// keeps the status item at the standard width.
    ///
    /// Resource lookup order, first match wins:
    ///   1. MenuBarIcon.pdf     — preferred vector format
    ///   2. MenuBarIcon.svg     — fallback vector format (current default)
    ///   3. MenuBarIcon@2x.png  — Retina raster, picked up automatically
    ///   4. MenuBarIcon.png     — single-resolution raster fallback
    ///   5. SF Symbol "doc.on.clipboard" — last-resort placeholder
    static var menuBarIcon: NSImage {
        let img: NSImage
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let i = NSImage(contentsOf: url) {
            img = i
        } else if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg"),
                  let i = NSImage(contentsOf: url) {
            img = i
        } else if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
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

    /// Full credits block for the About panel.
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
