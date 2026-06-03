//
//  RegionCaptureCheatSheet.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Corner overlay shown while #A11 region capture is armed (the C2
//  crosshair cursor state). Renders the same compact B&W keyboard
//  + mouse + legend the user liked from chat, but as a live SwiftUI
//  panel pinned to the bottom-right of the active screen.
//
//  Two design goals:
//
//  • **Discoverability** — while the user holds ⌥⌘ they see at a
//    glance every action they can launch with that modifier (system
//    hotkeys ⌥⌘V/C/X/S plus any per-action ⌥⌘<letter> they've
//    configured). The keyboard highlights the relevant keys with
//    thicker stroke; the legend lists each hotkey + its action
//    title. Non-⌥⌘ user hotkeys (⌃⇧X, fn+letter, etc.) are filtered
//    out — they can't fire from this state by definition, so they'd
//    just be noise.
//
//  • **Capture friendliness** — the moment the user moves the cursor
//    near the panel, it fades to ~15 % opacity so it doesn't block
//    the rectangle they're trying to draw. As the cursor moves away
//    it fades back in. 30 Hz polling timer driven by NSEvent
//    .mouseLocation — cheap, robust, no event-system entanglement.
//
//  Counterpart: ScreenRegionCapture.swift — owns this controller
//  alongside the cursor and selection overlays for the gesture.
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Data model

/// One per-action user hotkey to display in the cheat sheet legend.
/// Only ⌥⌘<letter> entries are passed in — anything else is filtered
/// upstream by the AppDelegate before reaching the controller.
struct RegionCaptureUserHotkey: Identifiable, Equatable {
    var id: String { letter }
    let letter: String        // e.g. "T" — single character, will be drawn highlighted on the keyboard
    let title: String         // human-readable action title
}

// MARK: - Controller

@MainActor
final class RegionCaptureCheatSheetController {
    /// Closure pulled at show() time so the cheat sheet always
    /// reflects current registry state. Injected by AppDelegate.
    var hotkeysProvider: (() -> [RegionCaptureUserHotkey])?

    private var panel: NSPanel?
    private var fadeTimer: Timer?
    /// Fade opacity targets. 1.0 = fully visible, 0.15 = cursor is
    /// inside the proximity rectangle so panel almost vanishes.
    private static let activeAlpha: CGFloat = 1.0
    private static let dimmedAlpha: CGFloat = 0.15
    /// Distance from panel edge (in points) at which the cheat sheet
    /// starts fading. Generous enough that the user doesn't need to
    /// be precise about avoiding it.
    private static let proximityMargin: CGFloat = 80

    init() {}

    /// Show the cheat sheet anchored to the bottom-right of the
    /// screen containing the mouse cursor. Idempotent — calling
    /// while visible rebuilds the content (cheap) and re-positions.
    ///
    /// Honours the Settings → General "Show keyboard cheat sheet
    /// on ⌥⌘ hold" toggle: when the user has disabled it (key
    /// `drpaste.cheatSheet.disabled = true`), this is a no-op.
    /// Region-capture itself still works — only the corner panel
    /// is suppressed.
    func show() {
        if UserDefaults.standard.bool(forKey: "drpaste.cheatSheet.disabled") {
            return
        }
        let hotkeys = hotkeysProvider?() ?? []
        let view = RegionCaptureCheatSheetView(userHotkeys: hotkeys)
        if panel == nil {
            buildPanel()
        }
        guard let panel = panel else { return }
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(NSSize(width: 410, height: 250))
        positionInCorner(panel)
        panel.alphaValue = Self.activeAlpha
        panel.orderFrontRegardless()
        startFadeTimer()
    }

    /// Hide the panel and stop the proximity-fade timer.
    func hide() {
        stopFadeTimer()
        panel?.orderOut(nil)
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 250),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .screenSaver         // same level as the cursor + selection overlays
        p.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                .ignoresCycle, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        // Critical — clicks must pass THROUGH the cheat sheet to the
        // selection overlay below so the user can start a drag inside
        // the cheat sheet's rectangle. The panel is informational,
        // never interactive.
        p.ignoresMouseEvents = true
        // Pick up the user's Settings → Appearance choice so the
        // cheat sheet matches the rest of the chrome.
        p.subscribeToAppTheme()
        panel = p
    }

    /// Pin the panel to the bottom-right corner of the screen
    /// containing the mouse cursor, clamped to `visibleFrame`
    /// (excludes menu bar + Dock). 24 pt margin.
    private func positionInCorner(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
        guard let s = screen else { return }
        let visible = s.visibleFrame
        let margin: CGFloat = 24
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.minY + margin
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Proximity fade

    private func startFadeTimer() {
        stopFadeTimer()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFade() }
        }
        RunLoop.main.add(t, forMode: .common)
        fadeTimer = t
    }

    private func stopFadeTimer() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    /// Check mouse position vs panel frame (expanded by `proximityMargin`)
    /// and animate alpha if the target differs from current. NSAnimation
    /// gives a smooth ~120 ms transition rather than a snap.
    private func updateFade() {
        guard let panel = panel, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let proximity = panel.frame.insetBy(dx: -Self.proximityMargin,
                                            dy: -Self.proximityMargin)
        let target: CGFloat = proximity.contains(mouse) ? Self.dimmedAlpha : Self.activeAlpha
        guard abs(panel.alphaValue - target) > 0.02 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = target
        }
    }
}

// MARK: - SwiftUI view

/// The cheat-sheet body: compact keyboard with DrPaste-relevant keys
/// emphasised, a small mouse pictogram above the arrow cluster with
/// the left button shown pressed (signals the in-progress capture
/// gesture), and a two-column legend below. Layout coordinates are
/// scaled-down versions of the SVG widget shown in chat — same style,
/// smaller frame to fit a corner overlay.
struct RegionCaptureCheatSheetView: View {
    let userHotkeys: [RegionCaptureUserHotkey]

    /// All letters that should be drawn highlighted on the keyboard:
    /// system hotkeys (V/C/X/S) plus any user-defined ⌥⌘<letter>.
    private var highlightedLetters: Set<String> {
        var set: Set<String> = ["V", "C", "X", "S"]
        for hk in userHotkeys { set.insert(hk.letter.uppercased()) }
        return set
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KeyboardCanvas(highlightedLetters: highlightedLetters)
                .frame(width: 374, height: 100)
            legend
        }
        .padding(18)
        .frame(width: 410, height: 250, alignment: .topLeading)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow, blending: .behindWindow)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var legend: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left column: built-in DrPaste hotkeys that fire from
            // armed state (we let ⌥⌘V/C/X/S cancel the arm and run
            // their normal flow — see EventTapEngine).
            VStack(alignment: .leading, spacing: 4) {
                cheatRow(combo: "⌥⌘ + drag", title: "capture region", emphasized: true)
                cheatRow(combo: "⌥⌘V", title: "open BigHUD")
                cheatRow(combo: "⌥⌘C", title: "quick copy")
                cheatRow(combo: "⌥⌘X", title: "cut & replace")
                cheatRow(combo: "⌥⌘S", title: "append copy")
                cheatRow(combo: "⌥⌘⏎", title: "paste & keep HUD")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: user-defined per-action ⌥⌘<letter>
            // hotkeys. Cap at 5 lines to keep the corner panel
            // bounded; surplus collapses into a "+ N more" line.
            VStack(alignment: .leading, spacing: 4) {
                if userHotkeys.isEmpty {
                    cheatRow(combo: "⌥⌘ + <letter>", title: "your custom actions appear here", muted: true)
                } else {
                    ForEach(Array(userHotkeys.prefix(5))) { hk in
                        cheatRow(combo: "⌥⌘\(hk.letter)", title: hk.title)
                    }
                    if userHotkeys.count > 5 {
                        cheatRow(combo: "", title: "+ \(userHotkeys.count - 5) more in Settings", muted: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One legend row — fixed-width combo on the left so titles
    /// line up across rows. Emphasised rows (the in-progress
    /// gesture) get primary color; everything else uses
    /// secondary. Muted rows are tertiary for hints.
    @ViewBuilder
    private func cheatRow(combo: String, title: String,
                          emphasized: Bool = false, muted: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(combo)
                .font(.system(size: 11, weight: emphasized ? .semibold : .medium, design: .monospaced))
                .foregroundColor(emphasized ? .primary : .secondary)
                .frame(width: 80, alignment: .leading)
            Text(title)
                .font(.system(size: 11, weight: emphasized ? .medium : .regular))
                .foregroundColor(emphasized ? .primary
                                 : muted ? Color.secondary.opacity(0.6)
                                 : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Keyboard canvas

/// Compact 60 % Mac-keyboard rendition, B&W contours only. Same style
/// the user signed off on in chat (saved to preferences.md). Keys
/// listed in `highlightedLetters` get a 1.5 pt stroke; everything
/// else stays at 0.5 pt for the inactive background.
private struct KeyboardCanvas: View {
    let highlightedLetters: Set<String>

    // Scale factor relative to the original SVG coordinate space
    // (680 pt wide, ~140 pt tall for the keyboard area). 0.7 keeps
    // labels legible at corner-overlay size.
    private static let scale: CGFloat = 0.7
    private static let originX: CGFloat = 60       // matches SVG left margin

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Row 1 — Esc + numbers + Delete
            keyOutline(x: 60, y: 20, w: 40, h: 20, label: "esc", thick: true, fontSize: 11, bold: true)
            ForEach(0..<10) { i in
                let x: CGFloat = 104 + CGFloat(i) * 30
                let label = String((i + 1) % 10)
                keyOutline(x: x, y: 20, w: 26, h: 20, label: label, thick: false, fontSize: 10)
            }
            keyOutline(x: 404, y: 20, w: 26, h: 20, label: "−", thick: true, fontSize: 11, bold: true)
            keyOutline(x: 434, y: 20, w: 26, h: 20, label: "=", thick: true, fontSize: 11, bold: true)
            keyOutline(x: 464, y: 20, w: 46, h: 20, label: "delete", thick: false, fontSize: 9)

            // Row 2 — Tab + Q row
            keyOutline(x: 60, y: 44, w: 40, h: 22, label: "tab", thick: false, fontSize: 9)
            letterRow(letters: ["Q","W","E","R","T","Y","U","I","O","P"], xStart: 104, y: 44)
            keyOutline(x: 404, y: 44, w: 26, h: 22, label: "[", thick: false, fontSize: 10)
            keyOutline(x: 434, y: 44, w: 26, h: 22, label: "]", thick: false, fontSize: 10)
            keyOutline(x: 464, y: 44, w: 46, h: 22, label: "\\", thick: false, fontSize: 10)

            // Row 3 — Caps + A row + Return
            keyOutline(x: 60, y: 70, w: 50, h: 22, label: "caps", thick: false, fontSize: 9)
            letterRow(letters: ["A","S","D","F","G","H","J","K","L"], xStart: 114, y: 70)
            keyOutline(x: 384, y: 70, w: 26, h: 22, label: ";", thick: false, fontSize: 10)
            keyOutline(x: 414, y: 70, w: 26, h: 22, label: "'", thick: false, fontSize: 10)
            // Return is a working key once BigHUD opens (paste +
            // close in Limited Mode; paste-and-keep with ⌥⌘ held
            // in Gesture Mode) — draw it highlighted so the user
            // doesn't read it as inert chrome.
            keyOutline(x: 444, y: 70, w: 66, h: 22, label: "⏎", thick: true, fontSize: 12, bold: true)

            // Row 4 — Shift + Z row + Shift
            keyOutline(x: 60, y: 96, w: 64, h: 22, label: "shift", thick: false, fontSize: 9)
            letterRow(letters: ["Z","X","C","V","B","N","M"], xStart: 128, y: 96)
            keyOutline(x: 338, y: 96, w: 26, h: 22, label: ",", thick: false, fontSize: 10)
            keyOutline(x: 368, y: 96, w: 26, h: 22, label: ".", thick: false, fontSize: 10)
            keyOutline(x: 398, y: 96, w: 26, h: 22, label: "/", thick: false, fontSize: 10)
            keyOutline(x: 428, y: 96, w: 82, h: 22, label: "shift", thick: false, fontSize: 9)

            // Row 5 — modifier row (with ⌥ ⌘ space ⌘ ⌥ always highlighted)
            keyOutline(x: 60, y: 122, w: 34, h: 22, label: "fn", thick: false, fontSize: 9)
            keyOutline(x: 98, y: 122, w: 34, h: 22, label: "ctrl", thick: false, fontSize: 9)
            keyOutline(x: 136, y: 122, w: 40, h: 22, label: "⌥", thick: true, fontSize: 12, bold: true)
            keyOutline(x: 180, y: 122, w: 48, h: 22, label: "⌘", thick: true, fontSize: 12, bold: true)
            keyOutline(x: 232, y: 122, w: 172, h: 22, label: "", thick: true)
            keyOutline(x: 408, y: 122, w: 48, h: 22, label: "⌘", thick: true, fontSize: 12, bold: true)
            keyOutline(x: 460, y: 122, w: 40, h: 22, label: "⌥", thick: true, fontSize: 12, bold: true)

            // Arrow cluster
            keyOutline(x: 510, y: 122, w: 22, h: 22, label: "←", thick: true, fontSize: 12, bold: true)
            keyOutline(x: 536, y: 110, w: 22, h: 12, label: "↑", thick: true, fontSize: 11, bold: true)
            keyOutline(x: 536, y: 122, w: 22, h: 22, label: "↓", thick: true, fontSize: 12, bold: true)
            keyOutline(x: 562, y: 122, w: 22, h: 22, label: "→", thick: true, fontSize: 12, bold: true)

            // Mouse pictogram above arrow cluster
            mousePictogram()
        }
        // The keyboard's original SVG span is x=60..584 (524 wide),
        // y=20..144 (124 tall). After scaling and origin shift the
        // local coordinate space is (524 × 124) * 0.7 ≈ 367 × 87.
        // Frame slightly larger so mouse pictogram (y=44 in original)
        // fits.
        .frame(width: (584 - 60) * Self.scale, height: 144 * Self.scale, alignment: .topLeading)
    }

    /// Render a letter row (Q, A, or Z) with each letter checked
    /// against `highlightedLetters` and drawn thick if a match.
    @ViewBuilder
    private func letterRow(letters: [String], xStart: CGFloat, y: CGFloat) -> some View {
        ForEach(0..<letters.count, id: \.self) { i in
            let letter = letters[i]
            let x = xStart + CGFloat(i) * 30
            keyOutline(
                x: x, y: y, w: 26, h: 22, label: letter,
                thick: highlightedLetters.contains(letter),
                fontSize: highlightedLetters.contains(letter) ? 11 : 10,
                bold: highlightedLetters.contains(letter)
            )
        }
    }

    /// Single key as a rounded rectangle outline with a centered label.
    /// Coordinates are in original SVG units; scaled and offset at draw time.
    @ViewBuilder
    private func keyOutline(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                            label: String, thick: Bool,
                            fontSize: CGFloat = 10, bold: Bool = false) -> some View {
        let sx = (x - Self.originX) * Self.scale
        let sy = y * Self.scale
        let sw = w * Self.scale
        let sh = h * Self.scale
        ZStack {
            RoundedRectangle(cornerRadius: 3 * Self.scale, style: .continuous)
                .strokeBorder(Color.primary, lineWidth: thick ? 1.5 : 0.5)
                .frame(width: sw, height: sh)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: fontSize * Self.scale * 1.4,
                                  weight: bold ? .medium : .regular))
                    .foregroundColor(.primary)
            }
        }
        .frame(width: sw, height: sh)
        .position(x: sx + sw / 2, y: sy + sh / 2)
    }

    /// Mouse pictogram — body outline thin, left button outlined
    /// thick to signal "left button pressed = capture in progress".
    /// Coordinates match the SVG (x=529..565, y=44..100).
    @ViewBuilder
    private func mousePictogram() -> some View {
        MouseShape()
            .stroke(Color.primary, lineWidth: 0.5)
            .frame(width: 36 * Self.scale, height: 56 * Self.scale)
            .position(
                x: (547 - Self.originX) * Self.scale,
                y: 72 * Self.scale
            )
        MouseLeftButtonShape()
            .stroke(Color.primary, lineWidth: 1.5)
            .frame(width: 18 * Self.scale, height: 20 * Self.scale)
            .position(
                x: (538 - Self.originX) * Self.scale,
                y: 54 * Self.scale
            )
        // Cable nub above the mouse
        Rectangle()
            .fill(Color.primary)
            .frame(width: 0.5, height: 4 * Self.scale)
            .position(
                x: (547 - Self.originX) * Self.scale,
                y: 42 * Self.scale
            )
    }
}

/// Rounded mouse body — wider at the bottom, slightly narrower at
/// the top where the buttons sit. Drawn in the local 36×56 box.
private struct MouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let topR: CGFloat = w * 0.25
        let botR: CGFloat = w * 0.45
        p.move(to: CGPoint(x: topR, y: 0))
        p.addLine(to: CGPoint(x: w - topR, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: topR),
                       control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - botR))
        p.addQuadCurve(to: CGPoint(x: w / 2, y: h),
                       control: CGPoint(x: w, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - botR),
                       control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: topR))
        p.addQuadCurve(to: CGPoint(x: topR, y: 0),
                       control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        // Horizontal divider between buttons and body, ~36 % down.
        let dividerY = h * 0.36
        p.move(to: CGPoint(x: 0, y: dividerY))
        p.addLine(to: CGPoint(x: w, y: dividerY))
        // Vertical divider between the two buttons.
        p.move(to: CGPoint(x: w / 2, y: 0))
        p.addLine(to: CGPoint(x: w / 2, y: dividerY))
        return p
    }
}

/// Outline of just the left button — overlaid on top of the body
/// with a thicker stroke to indicate the button is depressed.
private struct MouseLeftButtonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let topR: CGFloat = w * 0.5
        p.move(to: CGPoint(x: topR, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: topR))
        p.addQuadCurve(to: CGPoint(x: topR, y: 0),
                       control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}
