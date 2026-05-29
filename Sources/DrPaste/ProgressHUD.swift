//
//  ProgressHUD.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Mini transient progress HUD shown when a direct-trigger action hotkey is
//  pressed. Appears immediately, displays action name + indeterminate spinner,
//  hides as soon as the action completes. For AI actions it additionally
//  surfaces provider · model · elapsed seconds so the user can tell the
//  network call is alive rather than wondering whether the app froze —
//  matches the loading state in the main HUD preview pane.
//

import AppKit
import SwiftUI

/// Mutable view state for the mini progress HUD. Lives across show / hide
/// calls so SwiftUI can keep redrawing while a tick timer pushes `elapsed`
/// updates without rebuilding the hosting view.
@MainActor
final class ProgressHUDState: ObservableObject {
    @Published var label: String = ""
    @Published var inflight: AIInflight? = nil
    @Published var elapsed: TimeInterval = 0
}

@MainActor
final class ProgressHUDController {
    static let shared = ProgressHUDController()

    private var panel: NSPanel?
    private let state = ProgressHUDState()
    private var tickTimer: Timer?

    private init() {}

    /// Show progress HUD with a label and an optional AI inflight descriptor.
    /// Idempotent — calling while visible updates the label / inflight in
    /// place. When `inflight` is provided, a 10 Hz timer drives the elapsed
    /// counter until `hide()` is called.
    func show(label: String, inflight: AIInflight? = nil) {
        state.label = label
        state.inflight = inflight
        state.elapsed = 0
        startTickIfNeeded(inflight: inflight)
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }
        // Rebuild hosting view only on first show so the @StateObject inside
        // the view tree keeps its identity across label updates.
        if panel.contentView == nil || !(panel.contentView is NSHostingView<ProgressHUDView>) {
            panel.contentView = NSHostingView(rootView: ProgressHUDView(
                state: state,
                onClose: { [weak self] in self?.hide() }
            ))
        }
        positionNearCursor(panel)
        panel.orderFrontRegardless()
    }

    /// Hide HUD immediately and stop the elapsed-tick timer.
    func hide() {
        stopTick()
        state.inflight = nil
        panel?.orderOut(nil)
    }

    private func startTickIfNeeded(inflight: AIInflight?) {
        stopTick()
        guard let inflight = inflight else { return }
        let startedAt = inflight.startedAt
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.state.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 90),
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

    /// Position the panel just above the mouse cursor on the screen
    /// containing it. Keeps the spinner inside the user's visual focus area
    /// so they don't have to glance across the display to confirm an
    /// action fired. 30 pt vertical gap so the cursor doesn't sit on top of
    /// the panel; clamped to the active screen's visibleFrame with an 8 pt
    /// margin so it never collides with the menu bar / Dock / display edge.
    private func positionNearCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
        guard let screen = screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let offsetAboveCursor: CGFloat = 30
        let margin: CGFloat = 8

        var x = mouse.x - size.width / 2
        var y = mouse.y + offsetAboveCursor    // bottom-left origin → +y is up

        x = max(visible.minX + margin,
                min(x, visible.maxX - size.width - margin))
        y = max(visible.minY + margin,
                min(y, visible.maxY - size.height - margin))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct ProgressHUDView: View {
    @ObservedObject var state: ProgressHUDState
    /// Closure invoked when the user dismisses the mini-window via the close
    /// button. Used as a safety net — even if the underlying action hangs
    /// (network stall, deadlocked URLSession, etc.) the user always has a
    /// one-click escape out of the floating panel.
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: spinner + action title + close button.
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            // AI inflight row — provider / model + ticking elapsed counter.
            if let inflight = state.inflight {
                HStack(spacing: 8) {
                    Text("\(inflight.providerLabel) · \(inflight.modelName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1fs", state.elapsed))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
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
