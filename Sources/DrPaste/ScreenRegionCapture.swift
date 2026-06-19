//
//  ScreenRegionCapture.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
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

    /// Event monitors that drive the custom-drawn crosshair —
    /// `globalMouseMonitor` fires when the mouse moves over OTHER
    /// apps' windows, `localMouseMonitor` fires when the mouse moves
    /// over our own (the overlay panels). Together they cover every
    /// pixel of the screen. Both call `updateCrosshairPositions()`
    /// which pushes the global mouse coordinate down to each
    /// `CursorOverlayPanel`.
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    /// Defensive: we also push the system cursor to crosshair via
    /// the regular API in case it happens to work on the user's
    /// macOS version. Harmless if it doesn't — the custom-drawn
    /// crosshair carries the actual visual signal.
    private var cursorPushed: Bool = false

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
        startCursorEnforcement()
    }

    /// Start drawing our own crosshair on top of every cursor-overlay
    /// panel, tracking the mouse via global + local NSEvent monitors.
    /// We don't rely on `NSCursor.set()` anymore — three iterations
    /// of trying that approach all failed to reliably override the
    /// cursor over other apps' windows. The custom-drawn crosshair
    /// is fully under our control and always visible.
    ///
    /// We still call `NSCursor.crosshair.push()` as belt-and-braces:
    /// on macOS versions where it happens to work the user gets a
    /// real crosshair-shaped cursor in addition to ours; where it
    /// doesn't, no harm done.
    ///
    /// Global monitor catches events that don't reach our app —
    /// mouse moves over Safari, Finder, etc. Local monitor catches
    /// events that DO reach our app — mouse moves over our overlay
    /// panels themselves. Without both, the crosshair would freeze
    /// when the cursor crossed certain window boundaries.
    @MainActor
    private func startCursorEnforcement() {
        stopCursorEnforcement()
        NSCursor.crosshair.push()
        cursorPushed = true

        // Position the crosshair at the current mouse location
        // BEFORE attaching monitors so it appears immediately,
        // not on the next mouse move.
        updateCrosshairPositions()

        // Trigger the entrance animation on every overlay — crosshair
        // pulses to attract attention, hint pill explains the gesture.
        for overlay in cursorOverlays {
            (overlay.contentView as? CursorOverlayContentView)?
                .playEntranceAnimation()
        }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.updateCrosshairPositions() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.updateCrosshairPositions() }
            return event   // pass through; selection overlay needs drag events
        }
    }

    @MainActor
    private func stopCursorEnforcement() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    /// Push the current global mouse position down to every cursor
    /// overlay panel. Each panel decides whether it owns this point
    /// (its screen contains the cursor) and shows / hides its
    /// crosshair accordingly — so on multi-display setups only the
    /// active screen shows the crosshair.
    @MainActor
    private func updateCrosshairPositions() {
        let mouse = NSEvent.mouseLocation
        for overlay in cursorOverlays {
            overlay.setCrosshair(globalPoint: mouse)
        }
    }

    // MARK: - C1 — selection overlay

    /// Replace the cursor overlay with the selection overlay and start
    /// drawing a rectangle anchored at `point` (global Cocoa coords,
    /// bottom-left origin — what NSEvent.mouseLocation returns).
    func beginSelection(at point: NSPoint) {
        guard state == .armed else { return }
        state = .selecting
        anchorPoint = point
        // Take down the cheat sheet — once the user has committed to a
        // drag, the hint is just visual noise covering screen real
        // estate they probably want to capture.
        cheatSheet.hide()
        // Same logic for the per-cursor hint pill — user clearly
        // understood the gesture, the hint would now just clutter
        // what they're trying to capture.
        for overlay in cursorOverlays {
            (overlay.contentView as? CursorOverlayContentView)?.dismissHint()
        }

        // Build the selection overlays BELOW the cursor overlays so
        // the crosshair stays on top during the drag.
        selectionOverlays = NSScreen.screens.map { screen in
            let p = SelectionOverlayPanel(screen: screen)
            p.orderFrontRegardless()
            return p
        }
        // Re-front the cursor overlays so their crosshair sits on top
        // of the freshly-created selection overlays (both are at
        // `.screenSaver` level — z-order within a level is creation
        // order, so we have to bump the cursor overlays back up).
        cursorOverlays.forEach { $0.orderFrontRegardless() }
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
        stopCursorEnforcement()
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
    /// Cached origin of the screen this overlay covers, in global
    /// Cocoa coordinates. Used to convert global mouse position →
    /// local position when the controller forwards mouse moves.
    let screenOriginGlobal: NSPoint

    init(screen: NSScreen) {
        self.screenOriginGlobal = screen.frame.origin
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
        // Pass clicks through to the layer below (the selection overlay
        // catches drag-starts; we just draw the crosshair). The cursor
        // overlay doesn't need to receive any mouse events — the
        // controller pushes mouse position to us via `setCrosshair(...)`
        // from a global+local NSEvent monitor pair.
        self.ignoresMouseEvents = true
        let view = CursorOverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        self.contentView = view
        self.setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Update the crosshair position from a global mouse coordinate.
    /// Hides the crosshair when the mouse is on a different display.
    func setCrosshair(globalPoint: NSPoint) {
        guard let view = contentView as? CursorOverlayContentView else { return }
        let local = NSPoint(
            x: globalPoint.x - screenOriginGlobal.x,
            y: globalPoint.y - screenOriginGlobal.y
        )
        let onThisScreen = NSRect(origin: .zero, size: frame.size).contains(local)
        view.setCrosshairVisible(onThisScreen)
        if onThisScreen {
            view.updateCrosshairPosition(local)
        }
    }
}

/// Hosting view for the cursor-only overlay. Draws our OWN crosshair
/// as a CALayer that we position manually at the mouse coordinates.
///
/// Why we don't rely on system cursor APIs anymore: three iterations
/// of trying (`addCursorRect`, `NSTrackingArea + cursorUpdate`,
/// `NSCursor.crosshair.push()` + 30 Hz `.set()` hammering) all failed
/// to deliver a reliable crosshair over our screen-spanning non-key
/// non-activating overlay. The fundamental issue is that
/// `NSCursor.set()` is APP-SCOPED — when the cursor is over another
/// app's window, that app's cursor rect wins, and our background-app
/// `.set()` calls don't override it.
///
/// The actually-working approach is what macOS's own ⌘⇧4 region-
/// capture uses internally: hide your dependence on the system cursor
/// and draw your own. We don't even bother hiding the system arrow
/// (that requires `CGDisplayHideCursor` which is risky if the process
/// crashes mid-capture — cursor stays hidden until reboot). Instead
/// our crosshair sits ON TOP of the system cursor; the small visual
/// duplication is fine because the crosshair is the unmistakable
/// signal "you are in capture mode".
final class CursorOverlayContentView: NSView {
    let crosshair: CALayer
    /// Onboarding hint that appears next to the crosshair the moment
    /// capture is armed: "Click and drag to capture a region". Fades
    /// out after ~1.8 s so the user has time to read it on first use
    /// but it doesn't linger and obscure their target on subsequent
    /// captures. Also dismissed immediately when the user begins a
    /// selection drag (they clearly understood the instructions).
    let hint: CALayer

    /// Hint label content. Kept in code rather than localised so it
    /// matches the rest of DrPaste's UI (English) until / unless we
    /// add localisation.
    private static let hintText = "Click and drag to capture a region"

    override init(frame: NSRect) {
        crosshair = Self.makeCrosshairLayer()
        hint = Self.makeHintLayer(text: Self.hintText)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(hint)        // hint draws behind crosshair
        layer?.addSublayer(crosshair)   // crosshair on top
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Move the crosshair AND the hint pill to follow `localPoint`.
    /// The hint sits 14 pt to the right and 16 pt below the crosshair
    /// centre — close enough to read as "this hint belongs to that
    /// cursor", far enough not to obscure what's directly under the
    /// crosshair (the pixel the user is aiming for).
    func updateCrosshairPosition(_ localPoint: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        crosshair.position = localPoint
        let hintOffsetX: CGFloat = 14 + hint.bounds.width / 2
        let hintOffsetY: CGFloat = -16 - hint.bounds.height / 2
        hint.position = CGPoint(x: localPoint.x + hintOffsetX,
                                y: localPoint.y + hintOffsetY)
        CATransaction.commit()
    }

    /// Show / hide the crosshair — used to hide it on screens that
    /// don't currently contain the mouse (multi-display setups).
    func setCrosshairVisible(_ visible: Bool) {
        crosshair.isHidden = !visible
        // Hide the hint too on inactive screens — it's tied to the
        // crosshair as a single conceptual unit.
        hint.isHidden = !visible || hint.isHidden
    }

    /// Trigger the "you're in capture mode" entrance animation:
    /// crosshair pulses 3 times (~1.2 s total), hint is opaque
    /// throughout the pulse then fades out at the 1.8 s mark.
    /// Idempotent — re-arming after a cancel restarts the animation.
    func playEntranceAnimation() {
        crosshair.removeAnimation(forKey: "pulse")
        hint.removeAnimation(forKey: "fade")
        hint.opacity = 1.0
        hint.isHidden = false

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.40
        pulse.autoreverses = true
        pulse.repeatCount = 3
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        crosshair.add(pulse, forKey: "pulse")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 0.55
        fade.beginTime = CACurrentMediaTime() + 1.8
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        hint.add(fade, forKey: "fade")
    }

    /// Force the hint to disappear immediately. Called when the user
    /// starts a selection drag — they clearly understood, the hint
    /// would now just clutter what they're trying to capture.
    func dismissHint() {
        hint.removeAnimation(forKey: "fade")
        hint.opacity = 0
        hint.isHidden = true
    }

    /// Build the crosshair as a CALayer: two crossing lines + a small
    /// center dot. White stroke with a black shadow so the crosshair
    /// stays visible against both light and dark screen content
    /// without needing theme-awareness logic.
    private static func makeCrosshairLayer() -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Horizontal line.
        let h = CAShapeLayer()
        let hPath = CGMutablePath()
        hPath.move(to: CGPoint(x: 0, y: 12))
        hPath.addLine(to: CGPoint(x: 24, y: 12))
        h.path = hPath
        h.strokeColor = NSColor.white.cgColor
        h.lineWidth = 1.5
        h.shadowColor = NSColor.black.cgColor
        h.shadowOpacity = 0.9
        h.shadowOffset = .zero
        h.shadowRadius = 1.5
        h.frame = container.bounds
        container.addSublayer(h)

        // Vertical line.
        let v = CAShapeLayer()
        let vPath = CGMutablePath()
        vPath.move(to: CGPoint(x: 12, y: 0))
        vPath.addLine(to: CGPoint(x: 12, y: 24))
        v.path = vPath
        v.strokeColor = NSColor.white.cgColor
        v.lineWidth = 1.5
        v.shadowColor = NSColor.black.cgColor
        v.shadowOpacity = 0.9
        v.shadowOffset = .zero
        v.shadowRadius = 1.5
        v.frame = container.bounds
        container.addSublayer(v)

        // Center dot — clear gap in the middle (~3 pt) makes the
        // exact pixel-precise center visible, then a tiny white dot
        // marks it. Same convention as the system crosshair.
        let gap = CAShapeLayer()
        gap.path = CGPath(rect: CGRect(x: 9, y: 9, width: 6, height: 6), transform: nil)
        gap.fillColor = NSColor.clear.cgColor
        gap.strokeColor = NSColor.clear.cgColor
        // Use a mask to punch the gap out of the crossing lines.
        let mask = CAShapeLayer()
        let maskPath = CGMutablePath()
        maskPath.addRect(container.bounds)
        maskPath.addRect(CGRect(x: 10, y: 10, width: 4, height: 4))
        mask.path = maskPath
        mask.fillRule = .evenOdd
        mask.frame = container.bounds
        h.mask = mask
        let vMask = CAShapeLayer()
        let vMaskPath = CGMutablePath()
        vMaskPath.addRect(container.bounds)
        vMaskPath.addRect(CGRect(x: 10, y: 10, width: 4, height: 4))
        vMask.path = vMaskPath
        vMask.fillRule = .evenOdd
        vMask.frame = container.bounds
        v.mask = vMask

        // Tiny center dot inside the gap for pixel-precise feedback.
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: 11, y: 11, width: 2, height: 2), transform: nil)
        dot.fillColor = NSColor.white.cgColor
        dot.shadowColor = NSColor.black.cgColor
        dot.shadowOpacity = 0.9
        dot.shadowOffset = .zero
        dot.shadowRadius = 1.0
        dot.frame = container.bounds
        container.addSublayer(dot)

        return container
    }

    /// Build the hint pill — rounded black background with white
    /// text inside, fixed size. Anchor at centre so positioning
    /// math in `updateCrosshairPosition` doesn't have to compensate.
    private static func makeHintLayer(text: String) -> CALayer {
        let pillWidth: CGFloat = 230
        let pillHeight: CGFloat = 24
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Background — semi-opaque black pill with a thin white edge
        // for separation against bright wallpapers.
        let pill = CAShapeLayer()
        pill.path = CGPath(roundedRect: container.bounds,
                           cornerWidth: 6, cornerHeight: 6, transform: nil)
        pill.fillColor = NSColor.black.withAlphaComponent(0.78).cgColor
        pill.strokeColor = NSColor.white.withAlphaComponent(0.15).cgColor
        pill.lineWidth = 0.5
        pill.frame = container.bounds
        container.addSublayer(pill)

        // Text — CATextLayer renders top-down by default; on a
        // Cocoa-coordinate (y-up) parent we need to position the
        // text frame accounting for descender. 4 pt up from bottom
        // looks centred in a 24 pt pill with 11 pt font.
        let label = CATextLayer()
        label.string = text
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.fontSize = 11
        label.foregroundColor = NSColor.white.cgColor
        label.alignmentMode = .center
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        label.frame = CGRect(x: 8, y: 5, width: pillWidth - 16, height: 14)
        container.addSublayer(label)
        return container
    }

    /// Empty draw — the overlay is otherwise fully transparent.
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
