//
//  ToastController.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  Lightweight transient feedback panel anchored near the menu-bar
//  icon. Used for Append Copy session state ("Append started" /
//  "Appended", #A65), Region Capture confirmation ("Captured WxH",
//  #A66), and Screen Recording permission hints.
//
//  Design constraints:
//
//   - Non-activating panel: never steals focus from the user's
//     current app, so a toast can fire mid-gesture without breaking
//     the user's flow.
//   - Single instance: a second toast within the auto-dismiss
//     window replaces the first (keeps timing predictable for
//     rapid Append Copy presses).
//   - User can silence via Settings → General → "Show append
//     toasts" toggle (`PreferenceKeys.appendToastsEnabled`).
//

import AppKit
import SwiftUI

@MainActor
final class ToastController {

    static let shared = ToastController()

    private var panel: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    /// Show a toast with the given message + system-symbol glyph.
    /// `duration` is auto-dismiss time. Calling again before dismiss
    /// replaces the existing toast.
    ///
    /// `category` is honoured against the matching preference toggle.
    /// Pass `.essential` for permission-error / blocking toasts that
    /// should always show regardless of user preference.
    func show(message: String,
              systemImage: String,
              duration: TimeInterval = 1.5,
              category: Category = .essential) {

        // Respect the per-category mute preference. `.essential`
        // always shows.
        switch category {
        case .essential: break
        case .appendCopy:
            let on = UserDefaults.standard.object(forKey: PreferenceKeys.appendToastsEnabled) as? Bool ?? true
            guard on else { return }
        }

        dismissTimer?.invalidate()

        let view = ToastView(message: message, systemImage: systemImage)
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(x: 0, y: 0, width: 260, height: 36)

        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 36),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
            p.hasShadow = true
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel = p
        }
        panel?.contentViewController = host

        positionNearMenuBar()
        panel?.orderFrontRegardless()

        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
    }

    private func positionNearMenuBar() {
        guard let p = panel else { return }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Anchor top-right, 12pt below the menu bar, 12pt from the
        // right edge. Doesn't try to track the actual menu-bar icon
        // position (NSStatusItem button frame is unreliable on
        // multi-display setups).
        let w: CGFloat = 260
        let h: CGFloat = 36
        let x = visible.maxX - w - 12
        let y = visible.maxY - h - 12
        p.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    /// Per-category mute control. Maps each category to a
    /// `PreferenceKeys` entry the user can flip in Settings.
    enum Category {
        case essential
        case appendCopy
    }
}

private struct ToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
