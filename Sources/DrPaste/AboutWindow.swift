//
//  AboutWindow.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Custom About window. NSApp.orderFrontStandardAboutPanel is too narrow and
//  cramped; this presents a separate 560x500 window with breathing room.
//

import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 560, height: 500))
        window.center()
        window.title = "About \(AppBrand.name)"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func show() {
        if let w = window, !w.isVisible {
            w.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header: icon + title + tagline + version
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: AppBrand.nsIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppBrand.name)
                        .font(.system(size: 24, weight: .semibold, design: .default))
                    Text(AppBrand.tagline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Version \(AppBrand.version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }

            // Part of the ctrl8 collection — discover the other tools
            HStack(spacing: 6) {
                Text("Part of")
                    .foregroundStyle(.secondary)
                Link("ctrl8 — www.ctrl8.com", destination: URL(string: AppBrand.ctrl8URL)!)
            }
            .font(.system(size: 12))
            .padding(.top, 16)

            Divider().padding(.vertical, 24)

            // Copyright + license + source link
            VStack(alignment: .leading, spacing: 8) {
                Text("Copyright © 2026 iLya Os.")
                Text("Licensed under the MIT License.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("Source code:")
                        .foregroundStyle(.secondary)
                    Link("github.com/ilya000/DrPaste",
                         destination: URL(string: AppBrand.githubURL)!)
                }
                .padding(.top, 4)
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 24)

            // Acknowledgements
            VStack(alignment: .leading, spacing: 12) {
                Text("Acknowledgements")
                    .font(.system(size: 13, weight: .semibold))

                Text("DrPaste's design is inspired by Flycut, Maccy, Paste, and Raycast — open clipboard utilities that paved the way for keyboard-first paste UX on macOS.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Built on Apple's AppKit, SwiftUI, Core Image, Vision, and Carbon HIToolbox.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Thanks to the open-source community.")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .lineSpacing(4)

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(width: 560, height: 500, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
