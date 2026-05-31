//
//  AppTheme.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Preset color schemes — Fantastical-style appearance picker. Five
//  curated themes the user can flip between in Settings → General:
//
//    • Auto  — follows system day/night appearance (DrPaste's default
//              since 0.2.0). Identical to what the app shipped with
//              before the theme picker.
//    • Light — forced light always, ignoring system Dark Mode.
//    • Dark  — forced dark always, ignoring system Light Mode.
//    • Vivid — high-contrast saturated palette on a dark base. Orange
//              accent, vivid teal highlights — easy to scan at speed.
//    • Soft  — bright pastel palette on a light base. Soft lavender
//              accent, mint highlights — same chromatic richness as
//              Vivid but gentler on the eyes.
//
//  Theme persistence uses UserDefaults; ThemeManager broadcasts a
//  notification on change so every panel can refresh its appearance
//  in place without app restart.
//

import AppKit
import SwiftUI

// MARK: - Theme model

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case auto
    case light
    case dark
    case vivid
    case soft
    case ocean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:  return "Auto"
        case .light: return "Light"
        case .dark:  return "Dark"
        case .vivid: return "Vivid"
        case .soft:  return "Soft"
        case .ocean: return "Ocean"
        }
    }

    /// One-line caption shown below the picker. Tells the user what
    /// effect picking this theme will have.
    var caption: String {
        switch self {
        case .auto:
            return "Follows your system appearance — light during the day, dark at night."
        case .light:
            return "Always light, regardless of system Dark Mode."
        case .dark:
            return "Always dark, regardless of system Light Mode."
        case .vivid:
            return "High-contrast saturated palette on a dark base — easy to scan at speed."
        case .soft:
            return "Bright pastel palette on a light base — same chromatic richness as Vivid, gentler on the eyes."
        case .ocean:
            return "Bright tropical cyan-teal base with hot coral accents — cool, energetic, distinct from the warm Vivid / Soft pair."
        }
    }

    /// AppKit appearance to install on every DrPaste panel. `nil` means
    /// inherit from the system. Vivid sits on .darkAqua, Soft on .aqua —
    /// the custom palette adjustments layer ON TOP of the base.
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        case .vivid: return NSAppearance(named: .darkAqua)
        case .soft:  return NSAppearance(named: .aqua)
        case .ocean: return NSAppearance(named: .darkAqua)   // cool palette sits well on dark
        }
    }

    // MARK: Custom palette overrides

    /// Primary accent color — buttons, selection ring, action-chip
    /// emphasis. Auto/Light/Dark inherit the system accent (whatever
    /// the user picked in System Settings → Appearance). Vivid and
    /// Soft override with their own signature hue, saturated enough
    /// to read as "this is a themed app, not just a tinted system
    /// chrome".
    var accentColor: Color? {
        switch self {
        case .auto, .light, .dark: return nil
        case .vivid: return Color(red: 1.00, green: 0.50, blue: 0.10)   // electric orange
        case .soft:  return Color(red: 0.82, green: 0.42, blue: 0.65)   // dusty rose-purple
        case .ocean: return Color(red: 1.00, green: 0.42, blue: 0.36)   // hot coral
        }
    }

    /// Color for the BigHUD ⌥⌘S accumulator carrier highlight. The
    /// existing hardcoded green works fine on Auto/Light/Dark; Vivid
    /// and Soft replace it for tonal cohesion with the rest of the
    /// theme.
    var accumulatorAccent: Color? {
        switch self {
        case .auto, .light, .dark: return nil
        case .vivid: return Color(red: 0.15, green: 0.95, blue: 0.78)   // electric teal
        case .soft:  return Color(red: 0.45, green: 0.78, blue: 0.62)   // sage mint
        case .ocean: return Color(red: 1.00, green: 0.85, blue: 0.20)   // golden yellow
        }
    }

    /// Border color for the HUD outer rounded-rectangle. Auto/Light/Dark
    /// get the existing barely-visible primary stroke; Vivid and Soft
    /// get a glowing accent-coloured border that frames the panel and
    /// reinforces the theme identity at the chrome edge.
    var hudBorderColor: Color {
        switch self {
        case .auto, .light, .dark: return Color.primary.opacity(0.08)
        case .vivid: return Color(red: 1.00, green: 0.50, blue: 0.10).opacity(0.60)
        case .soft:  return Color(red: 0.82, green: 0.42, blue: 0.65).opacity(0.45)
        case .ocean: return Color(red: 0.00, green: 0.78, blue: 0.80).opacity(0.65)
        }
    }

    /// Border line width. Auto/Light/Dark use a hairline (0.5 pt);
    /// Vivid/Soft/Ocean use a thicker stroke (1.5 pt) so the accent
    /// edge reads as deliberate framing rather than a hairline
    /// artifact.
    var hudBorderWidth: CGFloat {
        switch self {
        case .auto, .light, .dark:    return 0.5
        case .vivid, .soft, .ocean:   return 1.5
        }
    }

    // MARK: Thumbnail palette (Settings picker preview)

    /// Three-color palette used by the Settings thumbnail to give
    /// users an at-a-glance preview of the theme. Index 0 = background,
    /// 1 = mid-tone (rows / chips), 2 = accent (selection / highlight).
    var thumbnailPalette: (background: Color, midtone: Color, accent: Color) {
        switch self {
        case .auto:
            // Half light, half dark — communicates "follows system".
            return (Color(white: 0.93), Color(white: 0.55), Color(white: 0.18))
        case .light:
            return (Color(white: 0.97), Color(white: 0.72), Color(white: 0.30))
        case .dark:
            return (Color(white: 0.13), Color(white: 0.35), Color(white: 0.78))
        case .vivid:
            // Match the actual HUD: deep plum background, electric
            // orange midtones, electric teal accent.
            return (
                Color(red: 0.16, green: 0.05, blue: 0.26),
                Color(red: 1.00, green: 0.50, blue: 0.10),
                Color(red: 0.15, green: 0.95, blue: 0.78)
            )
        case .soft:
            // Warm cream background, dusty rose-purple midtones, sage
            // mint accent — matches the HUD gradient palette.
            return (
                Color(red: 0.99, green: 0.95, blue: 0.96),
                Color(red: 0.82, green: 0.42, blue: 0.65),
                Color(red: 0.45, green: 0.78, blue: 0.62)
            )
        case .ocean:
            // Bright tropical: cyan-teal background, hot coral
            // midtones, golden accent — matches the HUD's Ocean
            // gradient.
            return (
                Color(red: 0.05, green: 0.45, blue: 0.55),
                Color(red: 1.00, green: 0.42, blue: 0.36),
                Color(red: 1.00, green: 0.85, blue: 0.20)
            )
        }
    }

    /// Special-case: Auto's thumbnail renders two halves (light + dark)
    /// instead of a single background, signalling "this one switches".
    var isSplitThumbnail: Bool { self == .auto }
}

// MARK: - Theme background fill

/// Renders the theme-specific background overlay that sits on top of
/// the system VisualEffect blur. Auto/Light/Dark are transparent (the
/// system blur is the chrome). Vivid is a deep indigo→plum vertical
/// gradient at ~85 % opacity that nearly buries the system blur and
/// makes the theme dominate. Soft is a warm cream→pale-lavender
/// gradient at ~78 % — same domination, much lighter palette.
///
/// Using a real `LinearGradient` rather than a single tinted color
/// is the trick that finally makes Vivid / Soft look like distinct
/// themes rather than "Dark with a slightly orange overlay".
struct ThemeBackgroundFill: View {
    let theme: AppTheme

    var body: some View {
        switch theme {
        case .auto, .light, .dark:
            Color.clear
        case .vivid:
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.08, green: 0.03, blue: 0.22).opacity(0.92),
                          location: 0.0),
                    .init(color: Color(red: 0.22, green: 0.06, blue: 0.32).opacity(0.88),
                          location: 0.6),
                    .init(color: Color(red: 0.35, green: 0.10, blue: 0.20).opacity(0.85),
                          location: 1.0),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        case .soft:
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 1.00, green: 0.96, blue: 0.94).opacity(0.82),
                          location: 0.0),
                    .init(color: Color(red: 0.98, green: 0.93, blue: 0.97).opacity(0.78),
                          location: 0.55),
                    .init(color: Color(red: 0.94, green: 0.92, blue: 0.99).opacity(0.80),
                          location: 1.0),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        case .ocean:
            // Bright tropical — cyan / turquoise / deep teal vertical
            // gradient. High saturation, very different chromatic
            // territory from the warm Vivid (orange-on-plum) and the
            // pastel Soft (cream-to-lavender).
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.07, green: 0.62, blue: 0.78).opacity(0.88),
                          location: 0.0),
                    .init(color: Color(red: 0.04, green: 0.48, blue: 0.65).opacity(0.86),
                          location: 0.55),
                    .init(color: Color(red: 0.03, green: 0.32, blue: 0.48).opacity(0.88),
                          location: 1.0),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Manager

/// Singleton that tracks the active theme, persists it, and broadcasts
/// `appThemeDidChange` so every panel can re-apply its appearance
/// without an app restart.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let defaultsKey = "drpaste.appearance.theme"

    @Published private(set) var current: AppTheme

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
                  ?? AppTheme.auto.rawValue
        self.current = AppTheme(rawValue: raw) ?? .auto
    }

    /// Change the active theme. Persists to UserDefaults and broadcasts
    /// `appThemeDidChange` synchronously so panels update before the
    /// Settings sheet animates the picker selection.
    func setTheme(_ theme: AppTheme) {
        guard theme != current else { return }
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: .appThemeDidChange, object: nil)
    }

    /// Apply the current theme's NSAppearance override to a window.
    /// Called both at panel construction time and on theme-change
    /// notifications. Safe to call on any NSWindow; `appearance = nil`
    /// restores the system default.
    func applyAppearance(to window: NSWindow) {
        window.appearance = current.nsAppearance
    }
}

extension Notification.Name {
    static let appThemeDidChange = Notification.Name("drpaste.appearance.themeDidChange")
}

// MARK: - NSWindow convenience

extension NSWindow {
    /// Apply the current app theme to this window AND subscribe to
    /// `appThemeDidChange` so it re-applies whenever the user picks
    /// a different theme in Settings. Call once in the window's init.
    ///
    /// Idempotent — repeated calls remove the previous observer
    /// before re-adding, so it's safe to invoke from `subscribeToAppTheme()`
    /// helpers that may run more than once (e.g. if a panel is rebuilt).
    @MainActor
    func subscribeToAppTheme() {
        NotificationCenter.default.removeObserver(
            self,
            name: .appThemeDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(NSWindow.applyDrPasteAppTheme),
            name: .appThemeDidChange,
            object: nil
        )
        ThemeManager.shared.applyAppearance(to: self)
    }

    /// Selector target for the theme-change notification. Hops to
    /// MainActor before touching ThemeManager (the notification
    /// posts on whatever thread `setTheme` was called from — always
    /// main in practice, but the hop is cheap insurance).
    @objc func applyDrPasteAppTheme() {
        Task { @MainActor in
            ThemeManager.shared.applyAppearance(to: self)
        }
    }
}

// MARK: - SwiftUI thumbnail (used by Settings picker)

/// Mini rendering of a BigHUD-shaped pane in the theme's palette.
/// Three colored "row" capsules + a row of "action chip" rectangles,
/// laid out at 110×70 pt — same proportional shape as the real BigHUD
/// but small enough to fit four-up in a horizontal row.
struct ThemeThumbnail: View {
    let theme: AppTheme
    let selected: Bool

    // Six themes need to fit in a single horizontal row inside the
    // Settings sheet (~580 pt content width). At 110×70 the previous
    // size, six thumbnails + 5 × 14 pt gaps = 730 pt — overflow. At
    // 78×52 with 8 pt gaps the row fits in ~508 pt with breathing
    // room and the thumbnails still read clearly.
    private static let size = CGSize(width: 78, height: 52)
    private static let cornerRadius: CGFloat = 7

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                background
                content
                    .padding(5)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: selected ? 2.0 : 0.5
                    )
            )

            Text(theme.displayName)
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
        }
    }

    @ViewBuilder
    private var background: some View {
        let palette = theme.thumbnailPalette
        if theme.isSplitThumbnail {
            // Auto: split half light / half dark.
            HStack(spacing: 0) {
                Color(white: 0.95)
                Color(white: 0.18)
            }
        } else if theme == .vivid {
            // Match the HUD's actual gradient — deep plum at top,
            // warmer purple-red at bottom.
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.04, blue: 0.24),
                    Color(red: 0.36, green: 0.12, blue: 0.22),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if theme == .soft {
            // Match the HUD: warm cream top → pale lavender bottom.
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.96, blue: 0.94),
                    Color(red: 0.94, green: 0.92, blue: 0.99),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if theme == .ocean {
            // Match the HUD: bright cyan top → deep teal bottom.
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.65, blue: 0.80),
                    Color(red: 0.03, green: 0.32, blue: 0.48),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            palette.background
        }
    }

    private var content: some View {
        let palette = theme.thumbnailPalette
        // Compact rendering tuned for the 78×52 thumbnail. Sizes
        // scaled to ~0.6× the previous layout so the mini-HUD still
        // reads as "header + rows + action bar" without the
        // elements colliding inside the smaller frame.
        return VStack(alignment: .leading, spacing: 3) {
            // Header — three traffic-light dots.
            HStack(spacing: 2) {
                Circle().fill(Color.red.opacity(0.55)).frame(width: 3, height: 3)
                Circle().fill(Color.yellow.opacity(0.55)).frame(width: 3, height: 3)
                Circle().fill(Color.green.opacity(0.55)).frame(width: 3, height: 3)
                Spacer(minLength: 0)
            }
            // Three "row" capsules — first row gets the accent stripe
            // (mimics a selected/highlighted history clip).
            VStack(alignment: .leading, spacing: 1.5) {
                ForEach(0..<3) { i in
                    HStack(spacing: 2) {
                        if i == 0 {
                            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                                .fill(palette.accent)
                                .frame(width: 1.5, height: 4)
                        } else {
                            Color.clear.frame(width: 1.5, height: 4)
                        }
                        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                            .fill(palette.midtone.opacity(0.55))
                            .frame(width: [40, 32, 46][i], height: 3)
                    }
                }
            }
            Spacer(minLength: 0)
            // Action chips row.
            HStack(spacing: 1.5) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(palette.midtone.opacity(0.45))
                        .frame(width: 11, height: 4)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
