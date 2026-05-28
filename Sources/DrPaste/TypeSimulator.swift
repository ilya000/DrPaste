//
//  TypeSimulator.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Type Slowly. Types text character-by-character through
//  CGEvent.keyboardSetUnicodeString with a small delay between keys.
//  Useful for input fields that don't accept paste, demos, screen recordings.
//

import AppKit
import Carbon.HIToolbox

/// Internal session state for an in-progress Type Slowly run.
/// Holds cancellation flag and installed event monitors.
/// `@unchecked Sendable` because we serialise access via main queue / atomic-like reads
/// of a single Bool flag; closures only mutate `cancelled` on main thread.
final class TypeSlowlySession: @unchecked Sendable {
    var cancelled: Bool = false
    var monitors: [Any] = []
    var observers: [NSObjectProtocol] = []
    let originalFrontmostPID: pid_t

    init() {
        self.originalFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }
}

enum TypeSimulator {
    /// Types text character-by-character. Each character is a discrete keyDown/keyUp pair.
    /// Cancellation flag is checked before each character.
    /// onProgress(current, total) is called after each character.
    ///
    /// #4: Auto-cancellation triggers if the user:
    ///   - presses any key (not our own synthetic markers)
    ///   - clicks any mouse button
    ///   - changes frontmost application
    ///   - switches workspace / space
    static func typeSlowly(_ text: String,
                           baseDelay: TimeInterval = 0.2,
                           jitter: Double = 0.2,
                           cancellation: @escaping () -> Bool = { false },
                           onProgress: @escaping (Int, Int) -> Void = { _, _ in },
                           completion: @escaping () -> Void = {}) {
        let chars = Array(text)
        let total = chars.count
        let source = CGEventSource(stateID: .combinedSessionState)
        let session = TypeSlowlySession()
        installCancellationMonitors(session)

        Task.detached {
            for (idx, ch) in chars.enumerated() {
                if cancellation() || session.cancelled {
                    await MainActor.run {
                        removeCancellationMonitors(session)
                        SoundFeedback.play(.pasteFailure)
                        completion()
                    }
                    return
                }

                switch ch {
                case "\n":
                    postKey(source: source, keyCode: CGKeyCode(kVK_Return))
                case "\t":
                    postKey(source: source, keyCode: CGKeyCode(kVK_Tab))
                default:
                    postUnicode(source: source, character: ch)
                }

                await MainActor.run {
                    onProgress(idx + 1, total)
                    SoundFeedback.play(.typeTick)
                }

                let factor = 1.0 + Double.random(in: -jitter...jitter)
                let delay = baseDelay * factor
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await MainActor.run {
                removeCancellationMonitors(session)
                completion()
            }
        }
    }

    /// Install global monitors that cancel typing on user activity.
    /// Must be called on main thread (NSEvent global monitors require it).
    private static func installCancellationMonitors(_ session: TypeSlowlySession) {
        // Key press monitor — filter out our own synthetic events
        let keyMon = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            let isSynthetic = event.cgEvent?.getIntegerValueField(.eventSourceUserData)
                == DrPasteSyntheticMarker
            if !isSynthetic {
                session.cancelled = true
            }
        }
        if let m = keyMon { session.monitors.append(m) }

        // Mouse clicks
        let mouseMon = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            session.cancelled = true
        }
        if let m = mouseMon { session.monitors.append(m) }

        // Frontmost app change
        let appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            let newPID = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.processIdentifier ?? 0
            if newPID != session.originalFrontmostPID {
                session.cancelled = true
            }
        }
        session.observers.append(appObserver)

        // Workspace / space change
        let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { _ in session.cancelled = true }
        session.observers.append(spaceObserver)
    }

    /// Must be called on main thread (matches NSEvent.removeMonitor expectations).
    private static func removeCancellationMonitors(_ session: TypeSlowlySession) {
        for m in session.monitors { NSEvent.removeMonitor(m) }
        for o in session.observers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        session.monitors.removeAll()
        session.observers.removeAll()
    }

    private static func postUnicode(source: CGEventSource?, character: Character) {
        let utf16 = Array(String(character).utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        utf16.withUnsafeBufferPointer { ptr in
            down?.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
            up?.keyboardSetUnicodeString(stringLength: ptr.count, unicodeString: ptr.baseAddress)
        }
        // Tag both events as synthetic so installCancellationMonitors() ignores them.
        // Without this, the global keyDown monitor sees our first typed character,
        // treats it as user activity, sets session.cancelled = true, and the very
        // next iteration aborts the typing — only one character lands in the target.
        down?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postKey(source: CGEventSource?, keyCode: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: - Type Slowly action (Backlog #7)

struct TypeSlowlyAction: ClipboardAction {
    let id = "builtin.type_slowly"
    let title = "Type Slowly"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        guard context.contains(.plain) else { return false }
        guard let text = item.previewText else { return false }
        return text.count > 0 && text.count <= 500
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard AXIsProcessTrusted() else {
            return .failed(original: item,
                          reason: "Type Slowly requires Accessibility permission",
                          recovery: .openAccessibilitySettings)
        }
        let plain = makePlainText(item)
        return .alternativeCommit(plain, style: .typeSlowly(delay: 0.2, jitter: 0.2))
    }
}
