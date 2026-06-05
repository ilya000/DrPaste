//
//  UserGuideWindowController.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  In-app renderer for HELP.md (#240). The first attempt to wire the
//  "User Guide…" status-menu item to `NSWorkspace.open(HELP.md)`
//  depended on a third-party Markdown viewer (MacDown / Typora /
//  Marked 2 / etc.) being installed — most users don't have one, and
//  the fallback path (TextEdit) renders the file as raw markdown
//  markup, not rendered prose. This controller renders HELP.md
//  inline using macOS 12+'s built-in `NSAttributedString(markdown:)`
//  parser and displays it in a scrollable NSTextView. No external
//  dependencies, works offline, no third-party programs required.
//
//  Window is a singleton so opening the User Guide twice in a row
//  brings the existing window forward rather than stacking duplicates.
//

import AppKit

@MainActor
final class UserGuideWindowController: NSWindowController {

    static let shared = UserGuideWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DrPaste — User Guide"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        installContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func show() {
        if window?.isVisible == false {
            window?.center()
        }
        // Always activate the app so the window comes forward even
        // when DrPaste is in accessory-app mode (LSUIElement). Same
        // pattern About / Welcome windows use.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Content

    private func installContent() {
        guard let window = window else { return }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        // Allow clickable links inside the rendered Markdown.
        textView.isAutomaticLinkDetectionEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]

        textView.textStorage?.setAttributedString(renderedGuide())

        scroll.documentView = textView
        window.contentView = scroll
    }

    /// Load HELP.md from the bundle and render it as an attributed
    /// string. The bundle lookup matches AppBrand's resource recipe —
    /// `Bundle.module` (the SwiftPM resource bundle) is checked
    /// first, with a project-folder fallback for dev builds where
    /// the resource hasn't been bundled in.
    private func renderedGuide() -> NSAttributedString {
        let source = loadHelpMarkdown() ?? fallbackMessage()
        return renderMarkdown(source)
    }

    private func loadHelpMarkdown() -> String? {
        // Bundle resource (installed builds).
        if let url = Bundle.module.url(forResource: "HELP", withExtension: "md"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        // Dev build / project root.
        let candidates = [
            "/Users/ilya000/Dropbox/Claude My/DrPaste/HELP.md",
            FileManager.default.currentDirectoryPath + "/HELP.md"
        ]
        for path in candidates {
            if let s = try? String(contentsOfFile: path, encoding: .utf8) {
                return s
            }
        }
        return nil
    }

    private func fallbackMessage() -> String {
        """
        # DrPaste — User Guide

        The user guide source file could not be loaded from the bundle.

        You can read the latest version online at \(AppBrand.githubURL)/blob/main/HELP.md.
        """
    }

    /// Render Markdown source as a rich attributed string. Uses
    /// `NSAttributedString(markdown:)` with `.full` interpretation
    /// so block-level structure (headings, lists, blockquotes,
    /// horizontal rules) renders rather than degrading to inline
    /// runs. macOS 12+ ships this parser system-wide — no external
    /// library dependency.
    private func renderMarkdown(_ source: String) -> NSAttributedString {
        do {
            let options = AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible,
                languageCode: nil
            )
            var attr = try AttributedString(markdown: source, options: options)
            // Apply default font + colour across the whole document.
            // The Markdown parser produces no inline font attribute by
            // default, leaving NSTextView to pick a system font at
            // whatever size it likes. Setting an explicit base font
            // makes the document feel like a real reading surface and
            // gives headings something predictable to scale from.
            applyBaseStyling(to: &attr)
            applyHeadingStyling(to: &attr)
            applyCodeStyling(to: &attr)
            return NSAttributedString(attr)
        } catch {
            // Parser failure (shouldn't happen with .returnPartiallyParsedIfPossible
            // but cover the case) — fall back to plain text rendering.
            return NSAttributedString(
                string: source,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.textColor
                ]
            )
        }
    }

    private func applyBaseStyling(to attr: inout AttributedString) {
        let body = NSFont.systemFont(ofSize: 13)
        attr.font = body
        attr.foregroundColor = NSColor.textColor
    }

    /// Walk the document looking for heading intent runs and scale
    /// their font + add weight. AttributedString carries Markdown
    /// intents in `presentationIntent` — we recognise the
    /// header(level:) variant and pick a font size per level.
    private func applyHeadingStyling(to attr: inout AttributedString) {
        for run in attr.runs {
            guard let intent = run.presentationIntent else { continue }
            for component in intent.components {
                if case .header(let level) = component.kind {
                    let size: CGFloat = {
                        switch level {
                        case 1: return 24
                        case 2: return 20
                        case 3: return 17
                        case 4: return 15
                        default: return 14
                        }
                    }()
                    attr[run.range].font = NSFont.boldSystemFont(ofSize: size)
                }
            }
        }
    }

    /// Inline `code` and fenced code blocks get a monospaced font
    /// + faint background so they stand out from prose.
    private func applyCodeStyling(to attr: inout AttributedString) {
        for run in attr.runs {
            // Inline code carries the `inlineHTML` intent or appears
            // wrapped via `inlinePresentationIntent.code`. Test both.
            if let inline = run.inlinePresentationIntent, inline.contains(.code) {
                attr[run.range].font = NSFont.monospacedSystemFont(
                    ofSize: 12, weight: .regular
                )
                attr[run.range].backgroundColor =
                    NSColor.secondaryLabelColor.withAlphaComponent(0.10)
            }
            if let block = run.presentationIntent {
                for component in block.components {
                    if case .codeBlock = component.kind {
                        attr[run.range].font = NSFont.monospacedSystemFont(
                            ofSize: 12, weight: .regular
                        )
                    }
                }
            }
        }
    }
}
