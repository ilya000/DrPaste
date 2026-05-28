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
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleEvent(event)
            return nil  // swallow the event
        }
    }

    private func stopRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m); recorderMonitor = nil }
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
        // Hard block: combinations reserved for DrPaste's main hotkeys (⌥⌘V/C/X)
        // cannot be claimed by per-action bindings — they'd never fire anyway.
        if candidate.conflictsWithMainHotkeys {
            onStatus("This combination is reserved for the main DrPaste hotkey (⌥⌘V/C/X).")
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
