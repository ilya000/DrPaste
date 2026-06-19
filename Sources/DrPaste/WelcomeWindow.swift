//
//  WelcomeWindow.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Welcome window shown on first launch. Lists logo, name, key features,
//  hotkeys, and a "Don't show again" checkbox plus an OK button.
//
//  #241 — POLICY: Keep this window FOCUSED. The structure is:
//    1. Logo + name + tagline
//    2. 4 core basics:
//         • Press-and-hold ⌥⌘V
//         • Append Copy ⌥⌘S
//         • Quick Copy ⌥⌘C
//         • Region capture ⌥⌘+drag
//    3. AX permission CTA (when not yet granted)
//    4. Per-action hotkey hint section (when user has set any)
//    5. "Don't show again" + OK
//
//  Do NOT add:
//    • Per-feature deep-dive panels (those belong in HELP.md /
//      User Guide window)
//    • Provider setup steps (Settings → AI handles that)
//    • Marketing copy beyond the tagline
//    • Changelog highlights — Welcome is for first-launch
//      orientation, not version-difference education
//
//  If a feature warrants in-product introduction, surface it
//  contextually in BigHUD / MiniHUD / Settings rather than
//  growing this window. The 4-basics rule keeps the screen
//  scannable in under 5 seconds.
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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
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
                VStack(alignment: .leading, spacing: 22) {
                    axWarningSection
                    workflowsSection
                    philosophySection
                    primaryHotkeySection
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
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

    // Hero — the product promise, not a feature list. (#welcome-redesign)
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: AppBrand.nsIcon)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text("Copy anything.\nKeep your train of thought intact.")
                    .font(.system(size: 21, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("DrPaste lives in the gap between “copy” and “paste” — so what reaches the cursor arrives already in the right form.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    // Short workflow stories — sells the product far better than a feature dump.
    private var workflowsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            workflowRow("keyboard.fill", .blue,
                        "Paste without breaking focus",
                        "Clipboard → Type Slowly → terminals, password fields, remote apps, anywhere")
            workflowRow("text.viewfinder", .teal,
                        "Copy text without cleanup",
                        "Screenshot → Extract Text (OCR) → Paste clean text")
            workflowRow("link", .green,
                        "Share links without garbage",
                        "Tracking URL → Clean URL → Share")
            workflowRow("wand.and.stars", .purple,
                        "Move meaning, not formatting",
                        "Rich Text ↔ Markdown · Translate · Fix grammar · Summarize")
            workflowRow("bubble.left.and.bubble.right.fill", .pink,
                        "Stand out in chats & social",
                        "Selected in Discord → 𝐁𝐨𝐥𝐝 · 𝐼𝑡𝑎𝑙𝑖𝑐 · 𝒮𝒸𝓇𝒾𝓅𝓉 — Unicode that pastes anywhere")
        }
    }

    @ViewBuilder
    private func workflowRow(_ icon: String, _ tint: Color,
                             _ title: String, _ example: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(example)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // Positioning: the clipboard is a pause in thought — DrPaste removes it.
    private var philosophySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The clipboard is where thought breaks")
                .font(.system(size: 13, weight: .semibold))
            Text("Wrong formatting, broken layout, tracking links, OCR cleanup, rich text where plain text is needed. DrPaste removes that interruption — instead of stopping to ask “how do I fix this paste?”, you stay in flow.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    // The ONE hotkey to learn first. Everything else is discovered later
    // (menu-bar hints, the ⌥⌘-hold overlay).
    private var primaryHotkeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("⌥⌘V")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                Text("Hold to open DrPaste")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text("More gestures and shortcuts appear while holding ⌥⌘.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
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
