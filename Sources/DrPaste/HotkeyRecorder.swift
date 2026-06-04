//
//  HotkeyRecorder.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Simple recorder for assigning a hotkey to an action. Click the field, press
//  any combination, the recorder captures it. Esc cancels, Delete clears.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorderField: View {
    @Binding var hotkey: ActionHotkey?
    /// Called with a status message after a recording attempt. Empty string clears.
    /// Errors (reserved combinations) and steal warnings both flow through here.
    var onStatus: (String) -> Void = { _ in }
    /// Returns `(id, displayTitle)` of an existing binding for this hotkey, or nil.
    /// Used to build a non-blocking "stolen from X" warning — the recording itself
    /// is always accepted, conflict resolution happens at save time.
    let conflictChecker: (ActionHotkey) -> (id: String, title: String)?

    @State private var isRecording = false
    @State private var recorderMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 6) {
                        if isRecording {
                            Text("Press shortcut…")
                                .foregroundStyle(.secondary)
                        } else if let hk = hotkey {
                            Text(hk.displayString)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        } else {
                            Text("Click to record")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(minWidth: 130, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isRecording
                                  ? Color.accentColor.opacity(0.20)
                                  : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)

                if hotkey != nil {
                    Button {
                        hotkey = nil
                        stopRecording()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear hotkey")
                }
            }
            // Per-action hotkey semantics primer — shown right under
            // the recorder so users see it when they're actually
            // assigning the chord. Tap fires direct (no HUD); holding
            // ⌥⌘ after the letter opens BigHUD focused on this action.
            // Wording matches the cheat sheet's per-action chord
            // legend ("— tap run, hold preview"), so users see
            // consistent phrasing across the recorder, the cheat
            // sheet, and HELP.md.
            if hotkey != nil {
                Text("Tap to run · hold ⌥⌘ to preview in HUD")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        // Silence every other hotkey interception path so the local
        // NSEvent monitor below can actually see ⌥⌘<letter> chords.
        // Without this, EventTap (Full Gesture Mode) and Carbon's
        // system + per-action hotkeys consume those chords before they
        // reach our app's responder chain, and `addLocalMonitorForEvents`
        // never fires — making it impossible to record ⌥⌘ combos.
        // Paired with `endHotkeyRecording()` in stopRecording().
        (NSApp.delegate as? AppDelegate)?.beginHotkeyRecording()
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleEvent(event)
            return nil  // swallow the event
        }
    }

    private func stopRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m); recorderMonitor = nil }
        if isRecording {
            // Restore hotkey interception. Idempotent — only fires when
            // we actually started recording (avoids spurious re-register
            // on the .onDisappear path where stopRecording can run
            // without a prior startRecording).
            (NSApp.delegate as? AppDelegate)?.endHotkeyRecording()
        }
        isRecording = false
    }

    private func handleEvent(_ event: NSEvent) {
        let kc = event.keyCode
        // Esc — cancel without changing the binding.
        if Int(kc) == kVK_Escape {
            stopRecording()
            return
        }
        // Delete — clear the binding.
        if Int(kc) == kVK_Delete {
            hotkey = nil
            onStatus("")
            stopRecording()
            return
        }
        // Require at least one modifier to avoid catching incidental keystrokes.
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command)  { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option)   { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control)  { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift)    { mods |= UInt32(shiftKey) }
        guard mods != 0 else { return }

        let candidate = ActionHotkey(keyCode: kc, modifiers: mods)
        // Hard block: combinations reserved for DrPaste's main hotkeys.
        // Per-action bindings would never fire here — the main hotkey
        // (or in-HUD chord) intercepts the keystroke first. Name the
        // specific feature so the user knows exactly what conflicts.
        if let drFeature = candidate.drPasteReservedName {
            onStatus("⚠︎ \(candidate.displayString) is already used by DrPaste for “\(drFeature)”. Pick a different combination.")
            return
        }
        // Hard block: combinations owned by macOS itself. Even if the
        // EventTap nominally wins the keystroke, lower OS layers still
        // briefly process it (Log Out dialog flicker, Dock animation,
        // etc.) — a noisy user experience that we head off here. Tell
        // the user WHO owns the chord so they know what to avoid; the
        // recorder cancels without committing the binding.
        if let systemName = candidate.systemHotkeyName {
            onStatus("⚠︎ \(candidate.displayString) is a macOS system shortcut for “\(systemName)”. Pick a different combination.")
            return
        }
        // Auto-steal: always accept the recording. If another action holds it,
        // surface a notice so the user knows the binding will be transferred on
        // Save. Actual unbind happens in ActionEditor.save() / ActionRegistry.
        if let conflict = conflictChecker(candidate) {
            onStatus("\(candidate.displayString) will be moved from \"\(conflict.title)\" to this action when you press Save.")
        } else {
            onStatus("")
        }
        hotkey = candidate
        stopRecording()
    }
}
