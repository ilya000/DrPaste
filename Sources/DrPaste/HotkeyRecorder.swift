//
//  HotkeyRecorder.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Простой recorder для назначения hotkey'я action'у (0.6.0):
//  кликни в поле → нажми любую комбинацию → она запомнилась.
//  Esc отменяет, Delete очищает.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorderField: View {
    @Binding var hotkey: ActionHotkey?
    var onConflict: (String) -> Void = { _ in }
    let conflictChecker: (ActionHotkey) -> String?    // returns conflicting action ID or nil

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
            return nil  // глотаем event
        }
    }

    private func stopRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m); recorderMonitor = nil }
        isRecording = false
    }

    private func handleEvent(_ event: NSEvent) {
        let kc = event.keyCode
        // Esc — отмена
        if Int(kc) == kVK_Escape {
            stopRecording()
            return
        }
        // Delete — очистка
        if Int(kc) == kVK_Delete {
            hotkey = nil
            stopRecording()
            return
        }
        // Требуем хотя бы один modifier — иначе случайные клавиши будут срабатывать
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command)  { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option)   { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control)  { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift)    { mods |= UInt32(shiftKey) }
        guard mods != 0 else { return }

        let candidate = ActionHotkey(keyCode: kc, modifiers: mods)
        if candidate.conflictsWithMainHotkeys {
            onConflict("This combination is reserved for the main DrPaste hotkey (⌥⌘V/C/X).")
            return
        }
        if let conflictingID = conflictChecker(candidate) {
            onConflict("This combination is already used by action: \(conflictingID).")
            return
        }
        hotkey = candidate
        stopRecording()
    }
}
