//
//  ProgressHUD.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Mini transient progress HUD shown when a direct-trigger action hotkey is pressed.
//  Appears immediately, displays action name + indeterminate spinner, hides as soon
//  as the action completes. Used for actions that may take noticeable time
//  (AI calls, image transformations).
//

import AppKit
import SwiftUI

@MainActor
final class ProgressHUDController {
    static let shared = ProgressHUDController()

    private var panel: NSPanel?
    private var label: String = ""

    private init() {}

    /// Show progress HUD with given label. Idempotent — calling while visible updates the label.
    func show(label: String) {
        self.label = label
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }
        panel.contentView = NSHostingView(rootView: ProgressHUDView(label: label))
        centerOnActiveScreen(panel)
        panel.orderFrontRegardless()
    }

    /// Hide HUD immediately.
    func hide() {
        panel?.orderOut(nil)
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.hidesOnDeactivate = false
        panel = p
    }

    private func centerOnActiveScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + 120
        )
        panel.setFrameOrigin(origin)
    }
}

struct ProgressHUDView: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 280, height: 64)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow, blending: .behindWindow)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
