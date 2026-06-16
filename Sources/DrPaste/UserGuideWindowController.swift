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
final class UserGuideWindowController: NSWindowController, NSTextViewDelegate {

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

        // Intercept clicks so `drpaste://` links route to in-app destinations
        // (Settings tabs, etc.) instead of being handed to NSWorkspace.
        textView.delegate = self

        textView.textStorage?.setAttributedString(renderedGuide())

        scroll.documentView = textView
        window.contentView = scroll
    }

    /// In-document anchor target → character location in the rendered text,
    /// built while rendering. Lets the Table-of-contents links scroll instead
    /// of being handed to NSWorkspace (which fails with "can't be opened −50").
    private var anchorLocations: [String: Int] = [:]

    /// Handle clicks: in-document `#anchor` links scroll to the heading;
    /// `drpaste://` deep links route to the AppDelegate; everything else
    /// (https, mailto, …) falls through to the default handler.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url: URL? = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
        guard let url else { return false }

        // Table-of-contents anchor (fragment-only / relative URL).
        if url.scheme == nil || url.scheme == "applewebdata" || url.absoluteString.hasPrefix("#"),
           let fragment = anchorFragment(from: url, raw: link) {
            scrollToAnchor(fragment, in: textView)
            return true
        }

        if url.scheme == "drpaste" {
            return (NSApp.delegate as? AppDelegate)?.openDeepLink(url) ?? false
        }
        return false
    }

    private func anchorFragment(from url: URL, raw: Any) -> String? {
        if let frag = url.fragment, !frag.isEmpty { return frag.removingPercentEncoding ?? frag }
        if let s = raw as? String, s.hasPrefix("#") { return String(s.dropFirst()) }
        let abs = url.absoluteString
        if let hash = abs.firstIndex(of: "#") { return String(abs[abs.index(after: hash)...]) }
        return nil
    }

    private func scrollToAnchor(_ fragment: String, in textView: NSTextView) {
        guard let loc = anchorLocations[fragment],
              let lm = textView.layoutManager,
              let tc = textView.textContainer else { return }
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: loc, length: 1),
                                       actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        rect.origin.y += textView.textContainerInset.height
        // Land the heading near the top of the viewport.
        textView.scroll(NSPoint(x: 0, y: max(0, rect.minY - 8)))
    }

    /// GitHub-style heading slug: lowercase, drop punctuation / symbols, spaces
    /// and existing hyphens become hyphens. Consecutive hyphens are preserved
    /// (matches how the HELP.md TOC anchors are generated).
    static func headingSlug(_ text: String) -> String {
        var s = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber { s.append(ch) }
            else if ch == " " || ch == "-" { s.append("-") }
        }
        return s
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
            let attr = try AttributedString(markdown: source, options: options)
            // CRITICAL: `AttributedString(markdown:)` parses block structure
            // into `presentationIntent` but inserts NO newlines between blocks,
            // so headings/paragraphs/list-items render as one continuous run
            // (everything jammed together). Rebuild the string inserting a
            // separator at every block boundary.
            return blockSeparated(attr)
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

    /// Rebuild the parsed document inserting a line break at every block
    /// boundary (paragraph / heading / list-item / code-block / rule), since
    /// `AttributedString(markdown:)` carries block structure only as
    /// `presentationIntent` metadata with no actual newlines. Consecutive
    /// list items get a single break; everything else a blank line.
    private func blockSeparated(_ attr: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        anchorLocations = [:]
        var isFirst = true
        var lastIntent: PresentationIntent?
        for run in attr.runs {
            let intent = run.presentationIntent
            if !isFirst && lastIntent != intent {
                let sep = (isListItem(intent) && isListItem(lastIntent)) ? "\n" : "\n\n"
                result.append(NSAttributedString(string: sep,
                                                 attributes: [
                                                    .font: NSFont.systemFont(ofSize: 13),
                                                    .foregroundColor: NSColor.textColor
                                                 ]))
            }
            // Record the scroll target for each heading so TOC anchors work.
            if isHeader(intent), intent != lastIntent {
                let slug = Self.headingSlug(String(attr[run.range].characters))
                if !slug.isEmpty, anchorLocations[slug] == nil {
                    anchorLocations[slug] = result.length
                }
            }
            let start = result.length
            result.append(NSAttributedString(AttributedString(attr[run.range])))
            let range = NSRange(location: start, length: result.length - start)
            applyStyling(for: run, in: result, range: range)
            lastIntent = intent
            isFirst = false
        }
        return result
    }

    private func isListItem(_ intent: PresentationIntent?) -> Bool {
        guard let intent else { return false }
        return intent.components.contains { component in
            if case .listItem = component.kind { return true }
            return false
        }
    }

    private func isHeader(_ intent: PresentationIntent?) -> Bool {
        guard let intent else { return false }
        return intent.components.contains { component in
            if case .header = component.kind { return true }
            return false
        }
    }

    private func applyStyling(for run: AttributedString.Runs.Run,
                              in result: NSMutableAttributedString,
                              range: NSRange) {
        var font = NSFont.systemFont(ofSize: 13)
        var background: NSColor?

        if let intent = run.presentationIntent {
            for component in intent.components {
                switch component.kind {
                case .header(let level):
                    let size: CGFloat = {
                        switch level {
                        case 1: return 24
                        case 2: return 20
                        case 3: return 17
                        case 4: return 15
                        default: return 14
                        }
                    }()
                    font = NSFont.boldSystemFont(ofSize: size)
                case .codeBlock:
                    font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    background = NSColor.secondaryLabelColor.withAlphaComponent(0.10)
                default:
                    break
                }
            }
        }

        if let inline = run.inlinePresentationIntent, inline.contains(.code) {
            font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            background = NSColor.secondaryLabelColor.withAlphaComponent(0.10)
        }

        result.addAttributes([
            .font: font,
            .foregroundColor: NSColor.textColor
        ], range: range)
        if let background {
            result.addAttribute(.backgroundColor, value: background, range: range)
        }
    }
}
