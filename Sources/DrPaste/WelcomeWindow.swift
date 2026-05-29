//
//  WelcomeWindow.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Welcome window shown on first launch. Lists logo, name, key features,
//  hotkeys, and a "Don't show again" checkbox plus an OK button.
//

import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private static let dontShowKey = "drpaste.welcome.dontShow"
    private var registry: ActionRegistry?
    private var window: NSWindow?

    private init() {}

    func configure(registry: ActionRegistry) {
        self.registry = registry
    }

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.dontShowKey) else { return }
        show()
    }

    func show() {
        if window == nil { buildWindow() }
        if let reg = registry, let w = window {
            let view = WelcomeView(registry: reg, onClose: { [weak self] in
                self?.window?.orderOut(nil)
            })
            w.contentViewController = NSHostingController(rootView: view)
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.title = "Welcome to \(AppBrand.name)"
        w.isReleasedWhenClosed = false
        window = w
    }
}

struct WelcomeView: View {
    @ObservedObject var registry: ActionRegistry
    let onClose: () -> Void
    @State private var dontShowAgain: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    axWarningSection
                    description
                    featuresSection
                    hotkeysSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 620)
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// #1: Show warning if Accessibility access is not granted.
    @ViewBuilder
    private var axWarningSection: some View {
        if !AXIsProcessTrusted() {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Limited Mode — Accessibility access not granted")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("DrPaste needs Accessibility permission to detect press-and-hold gestures, intercept HUD keyboard navigation, and simulate paste into the frontmost app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Without it, DrPaste runs in Limited Mode — open the HUD with ⌥⌘V and press Enter to paste (no press-and-hold).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("To enable full Gesture Mode:")
                    .font(.system(size: 12, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text("1. Open System Settings → Privacy & Security → Accessibility")
                    Text("2. Find DrPaste in the list and turn the toggle ON")
                    Text("3. Restart DrPaste")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                HStack {
                    Button("Open Accessibility Settings…") { openAXSettings() }
                    Button("Restart DrPaste") { restartApp() }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func openAXSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func restartApp() {
        let exePath = Bundle.main.executablePath ?? Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        try? process.run()
        NSApp.terminate(nil)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: AppBrand.nsIcon)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to \(AppBrand.name)")
                    .font(.system(size: 22, weight: .semibold))
                Text(AppBrand.tagline)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Version \(AppBrand.version)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(24)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is DrPaste?")
                .font(.headline)
            Text("DrPaste extends the macOS paste gesture. Press and hold ⌥⌘V — a HUD appears with your clipboard history and contextual actions. Release to paste. No separate window to manage, no toggle.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key features")
                .font(.headline)
            // Grid keeps the icon column at a fixed width so the text column
            // is perfectly aligned even when SF Symbols differ in glyph width.
            // Using SF Symbols (instead of emoji) also guarantees uniform
            // rendering across light/dark mode and font scaling.
            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 12,
                 verticalSpacing: 10) {
                featureGridRow("doc.on.clipboard.fill", Color.blue,
                               "Universal clipboard history — text, images, files, URLs, rich text")
                featureGridRow("sparkles", Color.purple,
                               "AI actions — multi-provider (Claude, GPT, Gemini, Ollama, etc.)")
                featureGridRow("wrench.and.screwdriver.fill", Color.orange,
                               "Custom transformations — regex, find/replace, prepend/append, wrap")
                featureGridRow("keyboard.fill", Color.gray,
                               "Per-action hotkeys — direct trigger without HUD")
                featureGridRow("photo.fill", Color.teal,
                               "Image actions — OCR, QR decode, resize, grayscale, rotate, ASCII art")
                featureGridRow("textformat", Color.pink,
                               "𝐅𝐚𝐧𝐜𝐲 𝐔𝐧𝐢𝐜𝐨𝐝𝐞 — paste 𝑩𝒐𝒍𝒅, 𝐼𝑡𝑎𝑙𝑖𝑐, 𝒮𝒸𝓇𝒾𝓅𝓉 anywhere (Twitter, Telegram, LinkedIn)")
                featureGridRow("globe", Color.indigo,
                               "Format converters — Rich → Markdown / HTML / Wiki, Cyrillic → Latin")
            }
        }
    }

    @ViewBuilder
    private func featureGridRow(_ icon: String,
                                _ tint: Color,
                                _ text: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hotkeys")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline,
                 horizontalSpacing: 14,
                 verticalSpacing: 8) {
                hotkeyGridRow("⌥⌘V", "Open HUD — press-and-hold, navigate with arrow keys, release to paste")
                hotkeyGridRow("⌥⌘C", "Quick Copy — like ⌘C but with sound feedback")
                hotkeyGridRow("⌥⌘X", "Cut & Replace — cut selection, choose what to paste in its place")
                hotkeyGridRow("⌥⌘S", "Append Copy — accumulate copies into one combined clipboard entry")
            }

            if !registry.config.actionHotkeys.isEmpty {
                Text("Your custom action hotkeys")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 14,
                     verticalSpacing: 8) {
                    ForEach(Array(registry.config.actionHotkeys.keys.sorted()), id: \.self) { actionID in
                        if let hk = registry.config.actionHotkeys[actionID],
                           let action = registry.actions.first(where: { $0.id == actionID }) {
                            let title = registry.displayTitle(forActionID: actionID,
                                                               defaultTitle: action.title)
                            hotkeyGridRow(hk.displayString, title)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hotkeyGridRow(_ key: String, _ description: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            // Fixed-width key badge so badges of different glyph widths
            // (⌥⌘V vs ⌥⌘E vs longer combos) all align to the same column.
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .frame(width: 64, alignment: .center)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Don't show this again", isOn: $dontShowAgain)
                .font(.system(size: 12))
            Spacer()
            Button("OK") {
                UserDefaults.standard.set(dontShowAgain, forKey: "drpaste.welcome.dontShow")
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
        .padding(16)
    }
}
