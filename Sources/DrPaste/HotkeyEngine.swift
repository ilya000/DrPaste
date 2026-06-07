//
//  HotkeyEngine.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Three main hotkeys: ⌥⌘V paste (with press-and-hold), ⌥⌘C Quick Copy,
//  ⌥⌘X Cut & Replace. Three engine implementations:
//  EventTap (Full Gesture mode), Carbon (Limited mode), GlobalMonitor (debug).
//

import AppKit
import CoreGraphics
import Carbon.HIToolbox

// MARK: - Config, enums

struct HotkeyConfig {
    let pasteKeyCode: CGKeyCode      // V
    let copyKeyCode: CGKeyCode       // C
    let cutKeyCode: CGKeyCode        // X
    let appendKeyCode: CGKeyCode     // S — Sum/Append Copy (#12)
    let modifiers: CGEventFlags      // ⌥⌘

    static let `default` = HotkeyConfig(
        pasteKeyCode: CGKeyCode(kVK_ANSI_V),
        copyKeyCode: CGKeyCode(kVK_ANSI_C),
        cutKeyCode: CGKeyCode(kVK_ANSI_X),
        appendKeyCode: CGKeyCode(kVK_ANSI_S),
        modifiers: [.maskCommand, .maskAlternate]
    )
}

enum NavDirection { case up, down, left, right }

enum FontChange { case bigger, smaller, reset }

enum SummonReason {
    case paste              // ⌥⌘V — standard HUD flow.
    case cutAndReplace      // ⌥⌘X — simulated ⌘X first, then HUD, replace on commit.
}

enum HotkeyEngineKind: String {
    case eventTap = "tap"
    case carbon   = "carbon"
    case monitor  = "monitor"
}

enum BigHUDMode {
    case gesture   // Full: non-activating, release-to-commit
    case summon    // Limited: key window, Enter/click-to-commit
}

protocol HotkeyEngineDelegate: AnyObject {
    func hotkeyEngineDidSummon(reason: SummonReason)
    func hotkeyEngineDidRelease()
    func hotkeyEngineDidNavigate(_ direction: NavDirection)
    func hotkeyEngineDidCancel()
    func hotkeyEngineDidRequestFontChange(_ change: FontChange)
    func hotkeyEngineDidQuickCopy()
    func hotkeyEngineDidDeleteFocused()
    func hotkeyEngineDidAppendCopy()
    /// #A12 — ⌥⌘C was held past the 250 ms grace period (quick copy already
    /// fired). Show a decorative MiniHUD preview of what was just copied.
    func hotkeyEngineDidHoldCopyPreview()
    /// #A12 — ⌥⌘ released after a copy-hold preview, or the preview was
    /// superseded (e.g. ⌥⌘V). Dismiss the MiniHUD; the item stays in history.
    func hotkeyEngineDidEndCopyPreview()
    /// #A12 — Esc during a copy-hold preview. Revert: pop the just-copied item
    /// off the top of history and dismiss the preview.
    func hotkeyEngineDidRevertCopy()
    /// #A12 — ⌥⌘V pressed while a copy-hold preview is on screen: animate the
    /// MiniHUD into the BigHUD (it's being promoted), rather than a plain hide.
    /// Fired just before `hotkeyEngineDidSummon`.
    func hotkeyEngineDidPromoteCopyPreview()
    /// #A12 — ⌥⌘ released (bare modifier up). Used to dismiss the ⌥⌘S append
    /// preview so it behaves like the copy preview: visible while ⌥⌘ is held,
    /// gone on release. Fires on every release; the delegate no-ops when no
    /// append preview is showing.
    func hotkeyEngineDidReleaseModifiers()
    /// Fired when ⌥⌘S is pressed while the HUD is active. Drives the in-HUD
    /// clip accumulator (different code path from the outside-HUD Append Copy
    /// which goes through hotkeyEngineDidAppendCopy).
    func hotkeyEngineDidRequestHUDAccumulate()
    /// Fired when ⌥⌘Space is pressed while the HUD is active. Promotes the
    /// current action preview into a new history clip inserted just above
    /// the focused row, so the user can chain further transformations
    /// without leaving the HUD.
    func hotkeyEngineDidRequestPromotePreview()

    /// Fired when ⌥⌘⏎ is pressed while the HUD is active. Caller pastes
    /// the focused outcome into the saved target app but keeps the HUD
    /// up so the user can queue another paste. Must be a separate
    /// callback from `hotkeyEngineDidRelease` (the regular commit-and-
    /// close path) because EventTapEngine sits in front of the local
    /// NSEvent monitor — without an explicit case here, the Return
    /// keyDown gets swallowed by the catch-all `default: return nil`
    /// branch and the local monitor in AppDelegate never sees it.
    func hotkeyEngineDidRequestPasteAndKeep()
    /// Fired by EventTapEngine (Full Gesture Mode only) for per-action
    /// hotkeys with the ⌥⌘ modifier set. `holdPreview` is true when the
    /// user kept ⌥⌘ held past the 250 ms grace period after pressing
    /// the letter — caller opens the HUD focused on this action instead
    /// of running it directly. False means the user did the usual quick
    /// tap-and-release; caller runs the action immediately and pastes
    /// the result. Carbon-only engines (Limited Mode) ignore this entry
    /// point and route through `ActionHotkeyManagerDelegate` as before.
    func hotkeyEngineDidFireActionHotkey(actionID: String, holdPreview: Bool)

    // MARK: #A11 — region capture (Full Gesture Mode only)

    /// Bare ⌥⌘ has been held alone past the 250 ms grace period.
    /// Caller arms the region-capture controller so the crosshair
    /// cursor overlay appears. No other keys must have been pressed
    /// in the window — if any letter / number / mouse-down arrived
    /// inside it the engine never fires this callback.
    func hotkeyEngineDidArmRegionCapture()

    /// The user mouse-downed while region capture was armed. Caller
    /// transitions the controller from cursor-only overlay to the
    /// selection overlay anchored at `globalPoint` (Cocoa screen
    /// coordinates, bottom-left origin — matches NSEvent.mouseLocation).
    func hotkeyEngineDidBeginRegionDrag(at globalPoint: NSPoint)

    /// Mouse moved while a selection drag is in progress. Caller
    /// updates the selection rectangle to span from anchor to
    /// `globalPoint`.
    func hotkeyEngineDidUpdateRegionDrag(to globalPoint: NSPoint)

    /// Mouse released while a selection drag was in progress. Caller
    /// commits the capture (PNG → ClipboardStore → BigHUD focused on
    /// the new clip). ⌥⌘ is still being held at this point; the
    /// subsequent flagsChanged release flows through the existing
    /// hotkeyEngineDidRelease commit path so the captured image
    /// pastes into the target app.
    func hotkeyEngineDidEndRegionDrag(at globalPoint: NSPoint)

    /// Cancel — fired when ⌥⌘ is released while armed (no mouse-down
    /// happened) OR released mid-drag (user changed their mind) OR
    /// Esc is pressed during either state. Caller tears down all
    /// overlays without capturing or pasting anything.
    func hotkeyEngineDidCancelRegionCapture()
}

/// Marker for our own synthetic CGEvents — filters recursion when the engine
/// re-observes events it just posted. Written into .eventSourceUserData when
/// posting ⌘V/⌘X/⌘C.
let DrPasteSyntheticMarker: Int64 = 0x44525041535445  // "DRPASTE" ASCII

protocol HotkeyEngine: AnyObject {
    var delegate: HotkeyEngineDelegate? { get set }
    var config: HotkeyConfig { get }
    var kind: HotkeyEngineKind { get }
    var bigHUDMode: BigHUDMode { get }
    func start() -> Bool
    func stop()
    /// Pause all hotkey processing while the user is recording a new
    /// per-action hotkey in Settings. Without this, system hotkeys
    /// (⌥⌘V/C/X/S) and any already-registered per-action hotkeys would
    /// fire INSTEAD of being captured by the recorder's local NSEvent
    /// monitor — because both Carbon RegisterEventHotKey and CGEventTap
    /// intercept keyboard events at a higher level than NSEvent local
    /// monitors. Default impl is a no-op for engines that don't need
    /// to silence themselves (e.g. GlobalMonitorEngine).
    func setRecordingMode(_ enabled: Bool)
}

extension HotkeyEngine {
    func setRecordingMode(_ enabled: Bool) {}
}

// MARK: - EventTap engine

final class EventTapEngine: HotkeyEngine {
    weak var delegate: HotkeyEngineDelegate?
    let config: HotkeyConfig
    let kind: HotkeyEngineKind = .eventTap
    let bigHUDMode: BigHUDMode = .gesture

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bigHUDIsActive: Bool = false
    /// When true, `handle()` passes every event through unmodified.
    /// Toggled by AppDelegate via `setRecordingMode(_:)` while the
    /// hotkey recorder field is active in Settings so the user can
    /// actually press ⌥⌘<letter> chords without the EventTap
    /// intercepting them as system hotkeys / per-action chords /
    /// region-capture arm.
    private var recordingPassthrough: Bool = false

    /// Per-action hotkeys with the ⌥⌘ modifier set (the only combo eligible
    /// for the hold-preview flow per #A10). Keyed by CGKeyCode → actionID.
    /// Pushed by AppDelegate whenever ActionConfig changes; only ⌥⌘<letter>
    /// pairs are forwarded — other modifier combos (e.g. ⌃⇧X) keep their
    /// Carbon-only behaviour because the grace period only makes sense when
    /// the user could plausibly keep ⌥⌘ held after the chord.
    private var holdPreviewActionHotkeys: [UInt16: String] = [:]

    /// Active pending fire — set when an action-hotkey chord was intercepted
    /// and the grace timer is running. Generation ID lets a late-arriving
    /// grace-expiry callback verify it's still the current pending fire (a
    /// subsequent chord, modifier release, or HUD open could have invalidated
    /// it). All access through `pendingFireQueue` so the CGEventTap callback
    /// thread and the main-queue grace-expiry block don't race.
    private var pendingActionID: String?
    private var pendingFireGeneration: UInt64 = 0
    private let pendingFireQueue = DispatchQueue(label: "drpaste.eventtap.pendingfire")

    /// Grace period after a per-action hotkey chord during which a
    /// modifier release commits the direct-paste path. Past this point
    /// the HUD opens focused on the action instead. 250 ms is the
    /// canonical default — short enough to feel responsive when the user
    /// genuinely intended to preview, long enough that a fast tap-and-
    /// release (letter then ⌥⌘, all within ~80–150 ms) doesn't trigger
    /// the HUD as a flash of UI.
    private static let holdPreviewGracePeriod: TimeInterval = 0.25

    /// #A11 region-capture arm grace — longer than the per-action
    /// hotkey hold-preview grace by design. Two reasons:
    ///
    ///   1. The arm timer races with normal ⌥⌘<letter> tap timing.
    ///      Many users hold the modifier chord 280–350 ms before
    ///      pressing the letter — well above 250 ms. With the arm
    ///      grace at 250 ms those taps would briefly flash the
    ///      cursor overlay + cheat sheet before the letter keyDown
    ///      cancelled the arm. 400 ms eliminates that flash for
    ///      essentially every natural tap rhythm.
    ///
    ///   2. The user's intent signal is different. Per-action
    ///      hold-preview is "I pressed the letter and decided to
    ///      preview" — a continuation gesture. Region-capture arm
    ///      is "I'm going to deliberately hold modifiers ALONE to
    ///      enter capture mode" — a fresh-intent gesture. The
    ///      fresh-intent threshold can be more generous because
    ///      users who actually want capture will hold > 500 ms
    ///      anyway.
    private static let regionCaptureArmGracePeriod: TimeInterval = 0.40

    // MARK: - #A11 region capture state

    /// #A11 state machine for the region-capture gesture. Lives entirely
    /// inside the engine because every transition is driven by raw events
    /// the EventTap already sees (flagsChanged / leftMouseDown / dragged /
    /// up / Esc). AppDelegate just reacts to delegate callbacks.
    ///
    ///   idle      — no gesture in progress.
    ///   armPending — ⌥⌘ pressed alone, grace timer running. If another
    ///                key or mouse-down arrives, fall back to idle.
    ///   armed     — grace expired with ⌥⌘ still held alone. Cursor
    ///                overlay (C2) is on screen. Awaiting mouse-down.
    ///   selecting — mouse is down, rectangle is being drawn.
    private enum RegionCaptureState { case idle, armPending, armed, selecting }
    private var regionCaptureState: RegionCaptureState = .idle
    /// Generation counter for the arm-pending grace timer, same pattern
    /// as `pendingFireGeneration` — a late-arriving grace callback
    /// validates this before transitioning to .armed so a cancelled
    /// arm doesn't slip through.
    private var regionCaptureArmGeneration: UInt64 = 0
    /// Serialises access to regionCaptureState / generation across the
    /// CGEventTap callback thread and the main-queue grace-expiry block.
    private let regionCaptureQueue = DispatchQueue(label: "drpaste.eventtap.regioncapture")

    // MARK: - #A12 copy-hold preview state

    /// #A12 — ⌥⌘C hold-preview state machine, same shape as the region-capture
    /// one. `pending` = quick copy fired, grace timer running; `active` = grace
    /// expired with ⌥⌘ still held, MiniHUD preview on screen.
    private enum CopyHoldState { case idle, pending, active }
    private var copyHoldState: CopyHoldState = .idle
    private var copyHoldGeneration: UInt64 = 0
    private let copyHoldQueue = DispatchQueue(label: "drpaste.eventtap.copyhold")

    init(config: HotkeyConfig) { self.config = config }

    /// Push the current per-action hotkey config. Call from AppDelegate
    /// after ActionConfig changes. Only ⌥⌘<letter> entries are kept;
    /// other modifier combos remain Carbon-only.
    func setHoldPreviewActionHotkeys(_ map: [UInt16: String]) {
        pendingFireQueue.sync {
            self.holdPreviewActionHotkeys = map
            // Invalidate any in-flight pending fire — the config changed,
            // the previous chord might no longer map to a valid action.
            self.pendingActionID = nil
            self.pendingFireGeneration &+= 1
        }
    }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            // #A11 — region capture intercepts the left-mouse trio while
            // armed / selecting. Outside that state the events are passed
            // through unchanged (we return Unmanaged.passUnretained(event)),
            // so apps under the cursor see clicks normally.
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<EventTapEngine>.fromOpaque(refcon).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else { return false }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        self.runLoopSource = src
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        tap = nil; runLoopSource = nil; bigHUDIsActive = false
    }

    /// Force-clears bigHUDIsActive. Used as a watchdog in AppDelegate when the HUD
    /// failed to open in time.
    func resetHudActive() { bigHUDIsActive = false }

    func setRecordingMode(_ enabled: Bool) {
        recordingPassthrough = enabled
    }

    /// Current state — used for AppDelegate state-machine synchronization.
    var isHudActive: Bool { bigHUDIsActive }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Skip our own synthetic events so the tap does not re-process them
        // (e.g. our synthetic ⌘X must not be interpreted as a user-initiated ⌥⌘X).
        if event.getIntegerValueField(.eventSourceUserData) == DrPasteSyntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        // Recording mode (Settings hotkey recorder is active) — pass
        // every event through so the NSEvent local monitor in the
        // recorder can see ⌥⌘<letter> chords without us swallowing
        // them as system / per-action hotkeys.
        if recordingPassthrough {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let modsPresent = flags.contains(config.modifiers)

        if type == .keyDown {
            let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

            // #A11 — region-capture state interactions with keyDown.
            //
            // armPending: any keyDown cancels the pending arm (user
            // pressed ⌥⌘<letter>, not bare ⌥⌘) — fall through to
            // normal handling.
            //
            // armed: Esc cancels capture and swallows the key. ⌥⌘
            // system hotkeys (V/C/X/S) and per-action ⌥⌘<letter>
            // hotkeys cancel the arm AND fall through to their normal
            // path — the user changed their mind about region capture
            // and wants to use the corresponding action instead. This
            // makes the corner cheat sheet's listed hotkeys actually
            // callable from armed state without first releasing ⌥⌘.
            // Any other key is swallowed (defensive — don't leak
            // stray text input into the underlying app).
            //
            // selecting: mouse button is down, a drag is in progress.
            // Esc cancels; everything else is swallowed.
            var currentRegionState: RegionCaptureState = .idle
            regionCaptureQueue.sync { currentRegionState = self.regionCaptureState }
            switch currentRegionState {
            case .armPending:
                regionCaptureQueue.sync {
                    self.regionCaptureState = .idle
                    self.regionCaptureArmGeneration &+= 1
                }
                // Continue to normal keyDown handling — the user is
                // pressing ⌥⌘<letter>, which has its own machinery.
            case .armed:
                if Int(kc) == kVK_Escape {
                    regionCaptureQueue.sync {
                        self.regionCaptureState = .idle
                        self.regionCaptureArmGeneration &+= 1
                    }
                    DispatchQueue.main.async {
                        self.delegate?.hotkeyEngineDidCancelRegionCapture()
                    }
                    return nil
                }
                // ⌥⌘ chord — always cancel arm and pass through. We
                // don't gate on "is this a known hotkey?" because the
                // EventTap's `holdPreviewActionHotkeys` map might not
                // be fully synced (e.g. brand-new action just added in
                // Settings, or a load-order edge case where the map
                // hasn't been pushed yet). Carbon's hotkey table is
                // the authoritative source for per-action hotkeys, and
                // it's reached via the natural event-pass-through path
                // when we don't return nil. Whatever doesn't match a
                // registered hotkey goes to the underlying app — but
                // that's acceptable: if the user fired ⌥⌘<letter>
                // while armed, they clearly meant to do SOMETHING and
                // having capture mode silently eat it is worse than
                // any side-effect in the target app.
                if modsPresent {
                    regionCaptureQueue.sync {
                        self.regionCaptureState = .idle
                        self.regionCaptureArmGeneration &+= 1
                    }
                    DispatchQueue.main.async {
                        self.delegate?.hotkeyEngineDidCancelRegionCapture()
                    }
                    // Fall through — let the chord match the
                    // `if modsPresent` branch below (which handles
                    // system hotkeys + per-action map lookup) and
                    // failing that, pass to Carbon.
                    break
                }
                // Non-⌥⌘ key while armed — swallow. The user is in
                // capture mode; stray typing into background apps is
                // worse than the key silently doing nothing.
                return nil
            case .selecting:
                if Int(kc) == kVK_Escape {
                    regionCaptureQueue.sync {
                        self.regionCaptureState = .idle
                        self.regionCaptureArmGeneration &+= 1
                    }
                    DispatchQueue.main.async {
                        self.delegate?.hotkeyEngineDidCancelRegionCapture()
                    }
                    return nil
                }
                return nil
            case .idle:
                break
            }

            // #A12 — Esc during a copy-hold preview reverts the copy (pop the
            // just-added item) and swallows the key.
            if Int(kc) == kVK_Escape {
                var shouldRevert = false
                copyHoldQueue.sync {
                    if self.copyHoldState == .active {
                        self.copyHoldState = .idle
                        self.copyHoldGeneration &+= 1
                        shouldRevert = true
                    }
                }
                if shouldRevert {
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRevertCopy() }
                    return nil
                }
            }

            // #A12 — courtesy: if the user presses ⌥⌘+arrow while the copy-hold
            // MiniHUD is up, they're treating it like the BigHUD (trying to
            // navigate). Promote them straight into the BigHUD (same animated
            // transition as ⌥⌘V) and swallow the key.
            switch Int(kc) {
            case kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow:
                var promote = false
                copyHoldQueue.sync { if self.copyHoldState == .active { promote = true } }
                if promote {
                    promoteCopyHoldToBigHUD()
                    bigHUDIsActive = true
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .paste) }
                    return nil
                }
            default:
                break
            }

            if bigHUDIsActive {
                switch Int(kc) {
                case kVK_UpArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.up) }
                    return nil
                case kVK_DownArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.down) }
                    return nil
                case kVK_LeftArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.left) }
                    return nil
                case kVK_RightArrow:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.right) }
                    return nil
                case kVK_Escape:
                    bigHUDIsActive = false
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidCancel() }
                    return nil
                case kVK_Delete:           // Backspace deletes the focused history item.
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidDeleteFocused() }
                    return nil
                case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.bigger) }
                    return nil
                case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.smaller) }
                    return nil
                case kVK_ANSI_0, kVK_ANSI_Keypad0:
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.reset) }
                    return nil
                case Int(config.appendKeyCode) where modsPresent:
                    // ⌥⌘S while the HUD is up — fire the in-HUD accumulator
                    // path, distinct from the outside-HUD Append Copy flow.
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestHUDAccumulate() }
                    return nil
                case Int(config.copyKeyCode) where modsPresent:
                    // ⌥⌘C in HUD — semantically "take what I'm looking
                    // at back into the clipboard": promote the current
                    // preview into a new clipboard entry at the TOP of
                    // history (where a real Copy would land) AND
                    // refocus the HUD onto that new entry. Distinct
                    // from the outside-HUD Quick Copy flow on the
                    // same chord — there's no preview to promote when
                    // the HUD isn't open, so the no-HUD branch below
                    // routes to hotkeyEngineDidQuickCopy instead.
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestPromotePreview() }
                    return nil
                case kVK_Return where modsPresent,
                     kVK_ANSI_KeypadEnter where modsPresent:
                    // ⌥⌘⏎ — paste the focused row into the saved target
                    // app but DON'T close the HUD. Lets the user queue
                    // several pastes in a row without re-opening the
                    // HUD between each. EventTap engine has to handle
                    // this explicitly — otherwise the catch-all
                    // `default: return nil` below would swallow Return
                    // and the local NSEvent monitor in AppDelegate
                    // would never see it.
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestPasteAndKeep() }
                    return nil
                default:
                    return nil
                }
            }

            // not active
            if modsPresent {
                if kc == config.pasteKeyCode {
                    // #A12 — ⌥⌘V while a copy-hold preview is up: animate the
                    // MiniHUD into the BigHUD, then open it. (Conservative
                    // morph; the promote delegate runs before summon so the
                    // mini fades as the big appears.)
                    promoteCopyHoldToBigHUD()
                    bigHUDIsActive = true
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .paste) }
                    return nil
                }
                if kc == config.cutKeyCode {
                    bigHUDIsActive = true
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .cutAndReplace) }
                    return nil
                }
                if kc == config.copyKeyCode {
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidQuickCopy() }
                    scheduleCopyHoldPreview()   // #A12 — hold → preview
                    return nil
                }
                if kc == config.appendKeyCode {
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidAppendCopy() }
                    return nil
                }
                // #A10: per-action hotkey hold-preview path. Intercept ⌥⌘<letter>
                // chords here so Carbon never sees them — `.headInsertEventTap`
                // runs strictly before Carbon's hotkey distribution. Defer the
                // actual firing until either the modifier is released (direct
                // paste) or the grace timer expires (open HUD focused on the
                // action). The Carbon-registered hotkey in
                // `ActionHotkeyManager` stays as the fallback for Limited Mode.
                var holdPreviewActionID: String?
                pendingFireQueue.sync {
                    holdPreviewActionID = self.holdPreviewActionHotkeys[UInt16(kc)]
                }
                if let actionID = holdPreviewActionID {
                    // Settings opt-out: if the user disabled the hold-preview,
                    // fire the action immediately (like a tap) — no grace timer,
                    // no BigHUD on hold.
                    if UserDefaults.standard.bool(forKey: PreferenceKeys.actionHotkeyHoldPreviewDisabled) {
                        DispatchQueue.main.async {
                            self.delegate?.hotkeyEngineDidFireActionHotkey(actionID: actionID,
                                                                           holdPreview: false)
                        }
                    } else {
                        schedulePendingActionFire(actionID: actionID)
                    }
                    return nil
                }
            }
        }

        // #A11 — region-capture mouse handling. We only intercept (return
        // nil) when the engine is in .armed or .selecting state. Otherwise
        // mouse events are passed through unchanged so apps under the
        // cursor see clicks normally.
        if type == .leftMouseDown {
            var currentState: RegionCaptureState = .idle
            regionCaptureQueue.sync { currentState = self.regionCaptureState }
            if currentState == .armed {
                regionCaptureQueue.sync { self.regionCaptureState = .selecting }
                let global = globalPoint(from: event)
                DispatchQueue.main.async {
                    self.delegate?.hotkeyEngineDidBeginRegionDrag(at: global)
                }
                return nil
            }
            // armPending → user clicked before grace expired. Cancel the
            // pending arm so the grace callback no-ops, and let the click
            // pass through to the underlying app unmodified.
            if currentState == .armPending {
                regionCaptureQueue.sync {
                    self.regionCaptureState = .idle
                    self.regionCaptureArmGeneration &+= 1
                }
            }
        }

        if type == .leftMouseDragged {
            var currentState: RegionCaptureState = .idle
            regionCaptureQueue.sync { currentState = self.regionCaptureState }
            if currentState == .selecting {
                let global = globalPoint(from: event)
                DispatchQueue.main.async {
                    self.delegate?.hotkeyEngineDidUpdateRegionDrag(to: global)
                }
                return nil
            }
        }

        if type == .leftMouseUp {
            var currentState: RegionCaptureState = .idle
            regionCaptureQueue.sync { currentState = self.regionCaptureState }
            if currentState == .selecting {
                // The captured image is about to be inserted at the top of
                // history and the HUD opens focused on it. Mark the big
                // HUD as active so the next ⌥⌘ release flows through the
                // standard flagsChanged → hotkeyEngineDidRelease commit
                // path, identical to ⌥⌘V's gesture-mode behaviour. Reset
                // the region-capture machine to .idle (the gesture itself
                // is done; what happens next is normal HUD interaction).
                regionCaptureQueue.sync { self.regionCaptureState = .idle }
                bigHUDIsActive = true
                let global = globalPoint(from: event)
                DispatchQueue.main.async {
                    self.delegate?.hotkeyEngineDidEndRegionDrag(at: global)
                }
                return nil
            }
        }

        if type == .flagsChanged {
            // #A11 — region capture cancellation paths. If ⌥⌘ is released
            // while armed (no mouse-down happened) or while selecting
            // (mid-drag bailout), tear down the overlays and DO NOT
            // capture anything. Process this BEFORE the bigHUDIsActive
            // branch below — region-capture can be active simultaneously
            // with the big HUD only after mouse-up (where we already
            // transitioned regionCaptureState back to .idle above).
            var currentRegionState: RegionCaptureState = .idle
            regionCaptureQueue.sync { currentRegionState = self.regionCaptureState }
            if !modsPresent {
                switch currentRegionState {
                case .armed, .selecting:
                    regionCaptureQueue.sync {
                        self.regionCaptureState = .idle
                        self.regionCaptureArmGeneration &+= 1
                    }
                    DispatchQueue.main.async {
                        self.delegate?.hotkeyEngineDidCancelRegionCapture()
                    }
                    // Don't fall through to bigHUDIsActive release — the
                    // user cancelled a region capture, they didn't release
                    // a HUD-gesture modifier.
                    return Unmanaged.passUnretained(event)
                case .armPending:
                    regionCaptureQueue.sync {
                        self.regionCaptureState = .idle
                        self.regionCaptureArmGeneration &+= 1
                    }
                    // No overlay was up yet (arm didn't fire), nothing to
                    // tear down. Continue with normal flagsChanged
                    // handling — the user just did a bare ⌥⌘ tap.
                case .idle:
                    break
                }
            } else if modsPresent && currentRegionState == .idle && !bigHUDIsActive {
                // Bare ⌥⌘ press with no other state. Arm the region
                // capture grace timer. If any keyDown / mouse-down / HUD
                // open happens within the grace window, the pending arm
                // is cancelled. Otherwise the timer fires and we
                // transition to .armed (cursor overlay).
                scheduleRegionCaptureArm()
            }

            // #A12 — copy-hold preview: releasing ⌥⌘ dismisses any preview and
            // cancels a still-pending grace. Notify on ANY non-idle state (not
            // just active) so a re-copy that left an earlier preview on screen
            // can't orphan it — `hide()` is idempotent.
            if !modsPresent {
                var shouldDismiss = false
                copyHoldQueue.sync {
                    if self.copyHoldState != .idle {
                        shouldDismiss = true
                        self.copyHoldState = .idle
                        self.copyHoldGeneration &+= 1
                    }
                }
                if shouldDismiss {
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidEndCopyPreview() }
                }
                // #A12 — generic "⌥⌘ up" signal so the append preview hides on
                // release too (no-op when nothing append-y is showing).
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidReleaseModifiers() }
            }

            if bigHUDIsActive {
                if !modsPresent {
                    bigHUDIsActive = false
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRelease() }
                }
            } else {
                // No HUD active, but a per-action hotkey may be pending grace —
                // releasing ⌥⌘ within the grace window commits the direct paste.
                var pendingID: String?
                var generation: UInt64 = 0
                pendingFireQueue.sync {
                    pendingID = self.pendingActionID
                    generation = self.pendingFireGeneration
                }
                if let actionID = pendingID, !modsPresent {
                    pendingFireQueue.sync {
                        // Re-check under lock — another callback may have already
                        // consumed the pending fire.
                        if self.pendingFireGeneration == generation && self.pendingActionID != nil {
                            self.pendingActionID = nil
                            self.pendingFireGeneration &+= 1
                        } else {
                            pendingID = nil
                        }
                    }
                    if pendingID != nil {
                        DispatchQueue.main.async {
                            self.delegate?.hotkeyEngineDidFireActionHotkey(
                                actionID: actionID,
                                holdPreview: false
                            )
                        }
                    }
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Arm or re-arm the grace timer for a per-action hotkey fire. Called
    /// from inside `handle()` (CGEventTap thread). Subsequent chord presses
    /// within the grace window replace the prior pending fire — the user
    /// pressed a different hotkey, the old chord is no longer relevant.
    private func schedulePendingActionFire(actionID: String) {
        var generation: UInt64 = 0
        pendingFireQueue.sync {
            self.pendingActionID = actionID
            self.pendingFireGeneration &+= 1
            generation = self.pendingFireGeneration
        }
        // Grace expiry — fires on main queue. Re-validates generation so a
        // chord that was already consumed by a modifier-release event doesn't
        // double-fire the action.
        let deadline = DispatchTime.now() + Self.holdPreviewGracePeriod
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self else { return }
            var actionToFire: String?
            self.pendingFireQueue.sync {
                if self.pendingFireGeneration == generation,
                   let pending = self.pendingActionID {
                    actionToFire = pending
                    self.pendingActionID = nil
                    self.pendingFireGeneration &+= 1
                }
            }
            if let actionID = actionToFire {
                // Mark HUD as active so the next ⌥⌘ release flows through
                // the existing flagsChanged → hotkeyEngineDidRelease commit
                // path, exactly like ⌥⌘V's gesture-mode behaviour. Set
                // BEFORE the delegate call — the delegate may take a few
                // ms to put the panel on screen and we want any in-flight
                // release event to be handled correctly throughout.
                self.bigHUDIsActive = true
                self.delegate?.hotkeyEngineDidFireActionHotkey(
                    actionID: actionID,
                    holdPreview: true
                )
            }
        }
    }

    /// #A12 — arm the copy-hold preview grace timer after a ⌥⌘C quick copy.
    /// If the grace expires with state still `.pending` (⌥⌘ still held — a
    /// release would have reset it to `.idle`), transition to `.active` and ask
    /// the delegate to show the MiniHUD preview. Same generation-counter guard
    /// as the region-capture arm.
    private func scheduleCopyHoldPreview() {
        var generation: UInt64 = 0
        copyHoldQueue.sync {
            self.copyHoldState = .pending
            self.copyHoldGeneration &+= 1
            generation = self.copyHoldGeneration
        }
        let deadline = DispatchTime.now() + Self.holdPreviewGracePeriod
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self else { return }
            var shouldShow = false
            self.copyHoldQueue.sync {
                if self.copyHoldGeneration == generation, self.copyHoldState == .pending {
                    self.copyHoldState = .active
                    shouldShow = true
                }
            }
            if shouldShow { self.delegate?.hotkeyEngineDidHoldCopyPreview() }
        }
    }

    /// #A12 — ⌥⌘V superseded the copy-hold preview: promote it into the BigHUD.
    /// If a preview was actually on screen (`.active`), ask the delegate to
    /// ANIMATE it into the BigHUD; otherwise (`.pending`, nothing shown yet)
    /// just reset state. Safe to call from the CGEventTap thread.
    private func promoteCopyHoldToBigHUD() {
        var wasActive = false
        copyHoldQueue.sync {
            if self.copyHoldState == .active { wasActive = true }
            if self.copyHoldState != .idle {
                self.copyHoldState = .idle
                self.copyHoldGeneration &+= 1
            }
        }
        if wasActive {
            DispatchQueue.main.async { self.delegate?.hotkeyEngineDidPromoteCopyPreview() }
        }
    }

    /// #A11 — arm the region-capture grace timer. Called from inside
    /// `handle()` when ⌥⌘ is pressed alone with no other state active.
    /// If the grace expires with state still `.armPending`, transition
    /// to `.armed` and fire `hotkeyEngineDidArmRegionCapture()` so the
    /// caller raises the cursor overlay. Same generation-counter pattern
    /// as per-action hotkeys — a cancelled arm doesn't reach the
    /// delegate.
    private func scheduleRegionCaptureArm() {
        var generation: UInt64 = 0
        regionCaptureQueue.sync {
            self.regionCaptureState = .armPending
            self.regionCaptureArmGeneration &+= 1
            generation = self.regionCaptureArmGeneration
        }
        let deadline = DispatchTime.now() + Self.regionCaptureArmGracePeriod
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self else { return }
            var shouldFire = false
            self.regionCaptureQueue.sync {
                if self.regionCaptureArmGeneration == generation,
                   self.regionCaptureState == .armPending {
                    self.regionCaptureState = .armed
                    shouldFire = true
                }
            }
            if shouldFire {
                self.delegate?.hotkeyEngineDidArmRegionCapture()
            }
        }
    }

    /// Convert a CGEvent's location field to global Cocoa screen
    /// coordinates (bottom-left origin, points). CGEvent reports in
    /// CoreGraphics screen coords which are top-left origin in pixels;
    /// we flip Y around the union of all display heights so the value
    /// matches `NSEvent.mouseLocation`.
    private func globalPoint(from event: CGEvent) -> NSPoint {
        let cg = event.location
        // CGEvent.location is in points (display points), top-left origin,
        // measured from the menu-bar screen's top-left. NSScreen frames
        // are in points, bottom-left origin, with NSScreen.screens[0]
        // being the menu-bar screen. Compute the union top so the flip is
        // consistent across multi-display setups.
        let globalScreenTop = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        return NSPoint(x: cg.x, y: globalScreenTop - cg.y)
    }
}

// MARK: - Carbon engine (Limited Mode, no AX needed)

final class CarbonHotKeyEngine: HotkeyEngine {
    weak var delegate: HotkeyEngineDelegate?
    let config: HotkeyConfig
    let kind: HotkeyEngineKind = .carbon
    let bigHUDMode: BigHUDMode = .summon

    private var pasteRef: EventHotKeyRef?
    private var copyRef: EventHotKeyRef?
    private var cutRef: EventHotKeyRef?
    private var appendRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x44525053 // 'DRPS'

    init(config: HotkeyConfig) { self.config = config }

    func start() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            let engine = Unmanaged<CarbonHotKeyEngine>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard hkID.signature == engine.signature else { return noErr }
            DispatchQueue.main.async {
                switch hkID.id {
                case 1: engine.delegate?.hotkeyEngineDidSummon(reason: .paste)
                case 2: engine.delegate?.hotkeyEngineDidQuickCopy()
                case 3: engine.delegate?.hotkeyEngineDidSummon(reason: .cutAndReplace)
                case 4: engine.delegate?.hotkeyEngineDidAppendCopy()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        guard status == noErr else { return false }

        let mods = carbonModifiers(from: config.modifiers)
        let pasteOK = RegisterEventHotKey(UInt32(config.pasteKeyCode), mods,
                                           EventHotKeyID(signature: signature, id: 1),
                                           GetApplicationEventTarget(), 0, &pasteRef) == noErr
        let copyOK = RegisterEventHotKey(UInt32(config.copyKeyCode), mods,
                                         EventHotKeyID(signature: signature, id: 2),
                                         GetApplicationEventTarget(), 0, &copyRef) == noErr
        let cutOK = RegisterEventHotKey(UInt32(config.cutKeyCode), mods,
                                        EventHotKeyID(signature: signature, id: 3),
                                        GetApplicationEventTarget(), 0, &cutRef) == noErr
        _ = RegisterEventHotKey(UInt32(config.appendKeyCode), mods,
                                EventHotKeyID(signature: signature, id: 4),
                                GetApplicationEventTarget(), 0, &appendRef)
        return pasteOK || copyOK || cutOK
    }

    func stop() {
        for ref in [pasteRef, copyRef, cutRef, appendRef] {
            if let r = ref { UnregisterEventHotKey(r) }
        }
        pasteRef = nil; copyRef = nil; cutRef = nil; appendRef = nil
        if let e = eventHandler { RemoveEventHandler(e); eventHandler = nil }
    }

    private func carbonModifiers(from cgFlags: CGEventFlags) -> UInt32 {
        var m: UInt32 = 0
        if cgFlags.contains(.maskCommand)   { m |= UInt32(cmdKey) }
        if cgFlags.contains(.maskAlternate) { m |= UInt32(optionKey) }
        if cgFlags.contains(.maskControl)   { m |= UInt32(controlKey) }
        if cgFlags.contains(.maskShift)     { m |= UInt32(shiftKey) }
        return m
    }

    func setRecordingMode(_ enabled: Bool) {
        if enabled {
            // Unregister system hotkeys so they don't fire while the
            // user is recording. Keep the event handler installed —
            // we'll just re-register the hotkeys when recording ends,
            // which is cheaper than tearing down the whole engine.
            for ref in [pasteRef, copyRef, cutRef, appendRef] {
                if let r = ref { UnregisterEventHotKey(r) }
            }
            pasteRef = nil; copyRef = nil; cutRef = nil; appendRef = nil
        } else {
            // Re-register if we previously unregistered. No-op if
            // start() never ran or if hotkeys are already in place.
            let mods = carbonModifiers(from: config.modifiers)
            if pasteRef == nil {
                _ = RegisterEventHotKey(UInt32(config.pasteKeyCode), mods,
                                        EventHotKeyID(signature: signature, id: 1),
                                        GetApplicationEventTarget(), 0, &pasteRef)
            }
            if copyRef == nil {
                _ = RegisterEventHotKey(UInt32(config.copyKeyCode), mods,
                                        EventHotKeyID(signature: signature, id: 2),
                                        GetApplicationEventTarget(), 0, &copyRef)
            }
            if cutRef == nil {
                _ = RegisterEventHotKey(UInt32(config.cutKeyCode), mods,
                                        EventHotKeyID(signature: signature, id: 3),
                                        GetApplicationEventTarget(), 0, &cutRef)
            }
            if appendRef == nil {
                _ = RegisterEventHotKey(UInt32(config.appendKeyCode), mods,
                                        EventHotKeyID(signature: signature, id: 4),
                                        GetApplicationEventTarget(), 0, &appendRef)
            }
        }
    }
}

// MARK: - GlobalMonitor engine (debug only)

final class GlobalMonitorEngine: HotkeyEngine {
    weak var delegate: HotkeyEngineDelegate?
    let config: HotkeyConfig
    let kind: HotkeyEngineKind = .monitor
    let bigHUDMode: BigHUDMode = .gesture

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var bigHUDIsActive: Bool = false

    init(config: HotkeyConfig) { self.config = config }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event)
        }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event)
        }
        return keyMonitor != nil && flagsMonitor != nil
    }

    func stop() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil; flagsMonitor = nil; bigHUDIsActive = false
    }

    private func cgFlags(from ns: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if ns.contains(.command) { f.insert(.maskCommand) }
        if ns.contains(.option)  { f.insert(.maskAlternate) }
        if ns.contains(.control) { f.insert(.maskControl) }
        if ns.contains(.shift)   { f.insert(.maskShift) }
        return f
    }
    private func modsPresent(_ event: NSEvent) -> Bool {
        cgFlags(from: event.modifierFlags).contains(config.modifiers)
    }

    private func handleKey(_ event: NSEvent) {
        let kc = CGKeyCode(event.keyCode)
        if bigHUDIsActive {
            switch Int(kc) {
            case kVK_UpArrow:    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.up) }
            case kVK_DownArrow:  DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.down) }
            case kVK_LeftArrow:  DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.left) }
            case kVK_RightArrow: DispatchQueue.main.async { self.delegate?.hotkeyEngineDidNavigate(.right) }
            case kVK_Escape:
                bigHUDIsActive = false
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidCancel() }
            case kVK_Delete:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidDeleteFocused() }
            case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.bigger) }
            case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.smaller) }
            case kVK_ANSI_0, kVK_ANSI_Keypad0:
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestFontChange(.reset) }
            case kVK_Return, kVK_ANSI_KeypadEnter:
                // ⌥⌘⏎ in HUD — paste focused row, keep HUD open. Same
                // semantic as EventTapEngine; gate on modifier presence
                // so a bare ⏎ in this engine is left to the local
                // NSEvent monitor (paste-and-close).
                if modsPresent(event) {
                    DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRequestPasteAndKeep() }
                }
            default: break
            }
            return
        }
        if modsPresent(event) {
            if kc == config.pasteKeyCode {
                bigHUDIsActive = true
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .paste) }
            } else if kc == config.cutKeyCode {
                bigHUDIsActive = true
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidSummon(reason: .cutAndReplace) }
            } else if kc == config.copyKeyCode {
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidQuickCopy() }
            } else if kc == config.appendKeyCode {
                DispatchQueue.main.async { self.delegate?.hotkeyEngineDidAppendCopy() }
            }
        }
    }

    private func handleFlags(_ event: NSEvent) {
        guard bigHUDIsActive else { return }
        if !modsPresent(event) {
            bigHUDIsActive = false
            DispatchQueue.main.async { self.delegate?.hotkeyEngineDidRelease() }
        }
    }
}

// MARK: - Factory

enum HotkeyEngineFactory {
    static func make(config: HotkeyConfig) -> HotkeyEngine {
        let env = ProcessInfo.processInfo.environment["CLIPMAC_ENGINE"]?.lowercased()
            ?? ProcessInfo.processInfo.environment["DRPASTE_ENGINE"]?.lowercased()
        if let forced = env.flatMap(HotkeyEngineKind.init(rawValue:)) {
            switch forced {
            case .eventTap: return EventTapEngine(config: config)
            case .carbon:   return CarbonHotKeyEngine(config: config)
            case .monitor:  return GlobalMonitorEngine(config: config)
            }
        }
        return AXIsProcessTrusted()
            ? EventTapEngine(config: config)
            : CarbonHotKeyEngine(config: config)
    }
}
