//
//  ScreenRegionCapture.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  #A11 — screen-region capture into clipboard history via ⌥⌘ + mouse drag.
//
//  Two stages of UI, one continuous gesture:
//
//  • C2 cursor overlay — full-screen transparent NSPanel per display, with
//    addCursorRect(.crosshair) over its entire frame. Shown after a 250 ms
//    grace period of bare ⌥⌘ hold (the EventTap engine arms this via
//    `arm()`). Purely a visual signal — the screen content underneath is
//    unmodified. Dismissed on ⌥⌘ release (`cancel()`) or replaced by the
//    selection overlay when the user mouse-downs (`beginSelection`).
//
//  • C1 selection overlay — full-screen transparent NSPanel per display,
//    with a 35 % black dim layer punched out where the selection rectangle
//    is, a 1 pt accent stroke around the rectangle, and a live "WxH"
//    dimensions readout near the cursor. The rectangle clamps to whichever
//    screen the mouse is currently on (cross-display drags become single-
//    screen captures at release time). Renders via CALayer for 120 Hz
//    smoothness on ProMotion displays.
//
//  Capture: CGWindowListCreateImage with the selection rect at full
//  resolution. ScreenCaptureKit would be the modern path but adds async
//  setup overhead that isn't worth it for a one-shot rectangle grab;
//  CGWindowList is synchronous and lossless. Result is a CGImage → PNG
//  Data, handed to ClipboardStore via `addCapturedImage`.
//
//  Permission model: Screen Recording is requested by macOS the first
//  time CGWindowListCreateImage is asked for pixels outside the calling
//  app's own windows. The first capture attempt triggers the system
//  prompt; subsequent denials surface as a nil result and an inline
//  failure (handled by the caller).
//
//  Counterpart: BigHUD.swift (the press-and-hold browser the capture is
//  handed off to once mouse-up fires).
//

import AppKit
import CoreGraphics

@MainActor
final class ScreenRegionCaptureController {
    /// Completion callback fired when the user finishes a drag.
    /// `nil` means the capture failed (permission denied, zero-size rect,
    /// or capture API returned nothing) — caller plays a failure sound.
    /// On success: PNG `Data` plus the captured screen rect in global
    /// (top-left origin) Cocoa coordinates so the caller can record the
    /// `sourceApp` whose window was topmost under it.
    var onCapture: ((Data?, NSRect) -> Void)?

    /// Fired when the user cancels (⌥⌘ released without mouse-down, or
    /// Esc, or ⌥⌘ released mid-drag). No capture happens, no clip is
    /// stored. Caller dismisses any other transient UI it had up.
    var onCancel: (() -> Void)?

    /// One cursor-only overlay per display, kept around for the lifetime
    /// of the armed state. Replaced by the selection overlay below the
    /// moment the user mouse-downs.
    private var cursorOverlays: [CursorOverlayPanel] = []

    /// Selection overlay panels — one per display, but only the one on
    /// the screen containing the current mouse position renders a visible
    /// rectangle. Others stay transparent (so the dim layer covers all
    /// screens uniformly even if the user drifts across).
    private var selectionOverlays: [SelectionOverlayPanel] = []

    /// Corner cheat-sheet panel with the keyboard + mouse + legend.
    /// Shown alongside the cursor overlay while armed. Hidden the
    /// instant the user begins a selection drag — once they've
    /// committed to capturing a rectangle they no longer need the
    /// hint and the panel would just take up screen real estate.
    let cheatSheet = RegionCaptureCheatSheetController()

    private var anchorPoint: NSPoint?         // mouse-down location (global Cocoa coords)

    enum State { case idle, armed, selecting }
    private(set) var state: State = .idle

    init() {}

    // MARK: - C2 — cursor overlay

    /// Show the crosshair-cursor overlay on every connected display.
    /// Called by the EventTap engine after its 250 ms grace timer
    /// expires with ⌥⌘ still held alone. Also raises the corner
    /// cheat sheet so the user sees the available ⌥⌘ hotkeys.
    func arm() {
        guard state == .idle else { return }
        state = .armed
        cursorOverlays = NSScreen.screens.map { screen in
            let p = CursorOverlayPanel(screen: screen)
            p.orderFrontRegardless()
            return p
        }
        cheatSheet.show()
    }

    // MARK: - C1 — selection overlay

    /// Replace the cursor overlay with the selection overlay and start
    /// drawing a rectangle anchored at `point` (global Cocoa coords,
    /// bottom-left origin — what NSEvent.mouseLocation returns).
    func beginSelection(at point: NSPoint) {
        guard state == .armed else { return }
        state = .selecting
        anchorPoint = point
        // Take down the cursor-only overlays — the selection overlays own
        // the cursor rect from here on (also crosshair) and have their own
        // dim + rect rendering.
        cursorOverlays.forEach { $0.orderOut(nil) }
        cursorOverlays.removeAll()
        // Take down the cheat sheet too — once the user has committed to a
        // drag, the hint is just visual noise covering screen real estate
        // they probably want to capture.
        cheatSheet.hide()

        selectionOverlays = NSScreen.screens.map { screen in
            let p = SelectionOverlayPanel(screen: screen)
            p.orderFrontRegardless()
            return p
        }
        updateSelection(to: point)
    }

    /// Update the rectangle to span from the anchor to `point`. Caller
    /// passes the live mouse location on every `.leftMouseDragged` event.
    func updateSelection(to point: NSPoint) {
        guard state == .selecting, let anchor = anchorPoint else { return }
        let rect = NSRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x),
            height: abs(point.y - anchor.y)
        )
        for panel in selectionOverlays {
            panel.updateSelection(globalRect: rect)
        }
    }

    /// Mouse-up. If the rectangle is non-trivially sized (≥ 4×4 to filter
    /// stray clicks), capture and fire `onCapture`. Otherwise treat as a
    /// cancel.
    func endSelection(at point: NSPoint) {
        guard state == .selecting, let anchor = anchorPoint else { return }
        let rect = NSRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x),
            height: abs(point.y - anchor.y)
        )
        tearDown()
        if rect.width < 4 || rect.height < 4 {
            onCancel?()
            return
        }
        let data = ScreenRegionCaptureController.capturePNG(globalRect: rect)
        onCapture?(data, rect)
    }

    /// Dismiss all overlays without capturing anything. Called on ⌥⌘
    /// release while armed (user changed their mind before mouse-down),
    /// ⌥⌘ release mid-drag (user changed their mind during drag), or
    /// Esc at any point.
    func cancel() {
        guard state != .idle else { return }
        tearDown()
        onCancel?()
    }

    private func tearDown() {
        cursorOverlays.forEach { $0.orderOut(nil) }
        cursorOverlays.removeAll()
        selectionOverlays.forEach { $0.orderOut(nil) }
        selectionOverlays.removeAll()
        cheatSheet.hide()
        anchorPoint = nil
        state = .idle
    }

    // MARK: - Capture API

    /// Capture pixels under `globalRect` (Cocoa coords, bottom-left
    /// origin, in points). Returns PNG `Data` at the device's full
    /// resolution, or nil on permission denial / API failure.
    ///
    /// Uses CGWindowListCreateImage with `.optionOnScreenOnly` so windows
    /// belonging to other apps are captured but our own overlay panels
    /// are excluded — the overlays were torn down before this call, but
    /// belt-and-braces.
    nonisolated static func capturePNG(globalRect: NSRect) -> Data? {
        // CGWindowListCreateImage takes a CGRect in screen coordinates
        // (top-left origin, in points). Cocoa screens are bottom-left
        // origin. Convert: flip Y around the union of all screen frames'
        // max Y. macOS treats the menu-bar screen's top-left as origin
        // for window rects.
        let globalScreenTop = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        let cgRect = CGRect(
            x: globalRect.minX,
            y: globalScreenTop - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )

        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }

        // Convert CGImage → PNG Data.
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - C2 cursor-only overlay

/// Fully transparent NSPanel covering a single display, with addCursorRect
/// over its entire bounds setting the cursor to `.crosshair`. Does not
/// draw anything visible — the screen content under it is unchanged. The
/// cursor swap is the only signal that the panel is up.
@MainActor
final class CursorOverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        // The panel must accept mouse-moved events for the content view's
        // NSTrackingArea to fire `cursorUpdate`. Without this AppKit
        // silently drops cursor-update events on non-key / non-activating
        // panels and the crosshair never appears.
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        let view = CursorOverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        self.contentView = view
        self.setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view for the cursor-only overlay. Uses an NSTrackingArea
/// with `.cursorUpdate + .activeAlways` instead of the simpler
/// `addCursorRect` because the latter doesn't reliably fire on
/// non-key / non-activating panels — AppKit treats them as "inactive"
/// and silently drops the cursor rect registration. The tracking-area
/// path with `.activeAlways` bypasses that check, and the explicit
/// `NSCursor.crosshair.set()` inside `cursorUpdate` is the same call
/// macOS's own ⌘⇧4 region-capture uses.
final class CursorOverlayContentView: NSView {
    private var trackingArea: NSTrackingArea?

    /// AppKit invokes `updateTrackingAreas` on view-frame changes and
    /// window-visibility changes. Rebuild from scratch every time so
    /// we never end up with a stale rect on resize.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    /// Belt-and-braces — some macOS releases skip the first
    /// `cursorUpdate` call after `orderFrontRegardless` on a
    /// non-activating panel. Setting the cursor again on every
    /// mouseMoved event guarantees the crosshair appears immediately
    /// without waiting for the user to wiggle the mouse across a
    /// tracking-area boundary.
    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    /// Empty draw — the overlay is fully transparent.
    override func draw(_ dirtyRect: NSRect) {}

    /// Eat mouse-down/dragged/up — CGEventTap at session level has
    /// already intercepted these when we're armed, but if for some
    /// reason an event slips through we don't want the panel itself
    /// to interpret it. No-op handlers prevent default behaviour
    /// like attempting to bring the panel to key state.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

// MARK: - C1 selection overlay

/// Transparent NSPanel with a 35 % black dim layer punched out where the
/// selection rectangle is, plus a 1 pt accent stroke and a "WxH" readout
/// near the cursor. One per display; only the panel whose screen contains
/// the selection rect draws the rect — others stay fully dimmed so the
/// "you are selecting" signal covers every monitor uniformly.
@MainActor
final class SelectionOverlayPanel: NSPanel {
    private let contentLayerView: SelectionOverlayContentView

    init(screen: NSScreen) {
        let frame = screen.frame
        self.contentLayerView = SelectionOverlayContentView(
            frame: NSRect(origin: .zero, size: frame.size),
            screenOriginGlobal: frame.origin
        )
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = false
        self.contentView = contentLayerView
        self.setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Push the new selection rect (global Cocoa coords). The view
    /// converts to local coords and decides whether to draw a rect or
    /// stay fully dimmed.
    func updateSelection(globalRect: NSRect) {
        contentLayerView.updateSelection(globalRect: globalRect)
    }
}

/// CALayer-backed view for the selection overlay. Dim layer is a CAShape
/// with even-odd fill rule — outer rect (screen bounds) filled black,
/// inner rect (selection) is a hole. Stroke layer draws the rectangle
/// outline. Text layer renders "WxH" near the cursor.
final class SelectionOverlayContentView: NSView {
    private let dimLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private let dimensionsLayer = CATextLayer()
    private let screenOriginGlobal: NSPoint

    init(frame: NSRect, screenOriginGlobal: NSPoint) {
        self.screenOriginGlobal = screenOriginGlobal
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.masksToBounds = true

        // Dim layer — 35 % black over the whole screen, will be reshaped
        // with a hole around the selection on every update.
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
        let initialPath = CGMutablePath()
        initialPath.addRect(bounds)
        dimLayer.path = initialPath
        layer?.addSublayer(dimLayer)

        // Stroke layer — 1 pt accent outline. Initially empty.
        strokeLayer.strokeColor = NSColor.controlAccentColor.cgColor
        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.lineWidth = 1
        layer?.addSublayer(strokeLayer)

        // Dimensions readout — small monospace "WxH" near the cursor.
        dimensionsLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        dimensionsLayer.fontSize = 11
        dimensionsLayer.foregroundColor = NSColor.white.cgColor
        dimensionsLayer.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        dimensionsLayer.alignmentMode = .center
        dimensionsLayer.cornerRadius = 4
        dimensionsLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        dimensionsLayer.isHidden = true
        layer?.addSublayer(dimensionsLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// Update visuals to reflect the new selection rect (global coords).
    /// Disables implicit CALayer animations so the dim/rect/readout
    /// follow the cursor without interpolation lag.
    func updateSelection(globalRect: NSRect) {
        // Convert global → local for THIS screen.
        let localRect = NSRect(
            x: globalRect.minX - screenOriginGlobal.x,
            y: globalRect.minY - screenOriginGlobal.y,
            width: globalRect.width,
            height: globalRect.height
        )
        let intersect = localRect.intersection(bounds)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Dim mask — punch a hole around the selection.
        let path = CGMutablePath()
        path.addRect(bounds)
        if !intersect.isEmpty {
            path.addRect(intersect)
        }
        dimLayer.path = path

        // Stroke — only draw if the selection touches this screen.
        if intersect.isEmpty {
            strokeLayer.path = nil
            dimensionsLayer.isHidden = true
        } else {
            // Inset by 0.5 pt so the 1 pt stroke aligns to the pixel grid.
            let strokeRect = intersect.insetBy(dx: 0.5, dy: 0.5)
            let strokePath = CGPath(rect: strokeRect, transform: nil)
            strokeLayer.path = strokePath

            // Dimensions readout — show actual pixel dimensions (multiply
            // by backing scale so the user sees the true capture size).
            let scale = window?.screen?.backingScaleFactor ?? 1
            let pxW = Int(globalRect.width * scale)
            let pxH = Int(globalRect.height * scale)
            dimensionsLayer.string = "\(pxW) × \(pxH)"
            let readoutSize = CGSize(width: 90, height: 18)
            // Anchor below-right of the selection so it doesn't obscure
            // the bottom-right corner of the rect itself. Clamp to screen.
            var x = intersect.maxX + 6
            var y = intersect.minY - 22
            if x + readoutSize.width > bounds.maxX - 4 {
                x = intersect.maxX - readoutSize.width
            }
            if y < bounds.minY + 4 {
                y = intersect.maxY + 6
            }
            dimensionsLayer.frame = CGRect(origin: CGPoint(x: x, y: y), size: readoutSize)
            dimensionsLayer.isHidden = false
        }

        CATransaction.commit()
    }
}
