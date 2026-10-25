import AppKit
import SalahCore
import SwiftUI

/// Colors from the spec, refined for WCAG AA. Each resolves per appearance, and
/// strengthens secondary tones when Increase Contrast is on.
///
/// `timeline`, `accent`, `onAccent`, `onTimeline` and `onTimelineDim` also depend on
/// `Palette.current` (the user's chosen accent theme, Settings › Appearance). They're computed
/// properties rather than `let`s so a theme change is picked up on the next redraw — which
/// happens automatically, since changing it goes through `AppModel.update`, and every view that
/// reads `Palette.*` already observes `AppModel` and redraws when its config changes.
enum Palette {
    /// The active accent theme. Set once by `AppModel` at launch and on every config change
    /// (`didChange`), from `config.display.accentTheme`. Read on the main thread only, like the
    /// rest of this UI-layer state.
    static var current: AccentTheme = .red

    static let background = dynamic(light: 0xF3F4F1, dark: 0x121212)
    static let chrome = dynamic(light: 0xECEDE9, dark: 0x1A1B1B)
    static let display = dynamic(light: 0xE4E7E6, dark: 0x1E2020)
    static let text = dynamic(light: 0x171717, dark: 0xEDEDEA)
    /// #5E5E5C light (5.2:1), darker than the spec's #777777, which fails AA on the display.
    /// Dark secondary brightened from 0x9A9A96: too dim against the menu bar popover's translucent material.
    static let secondary = dynamic(light: 0x5E5E5C, dark: 0xBFBFBB, lightHC: 0x3A3A38, darkHC: 0xC8C8C4)
    static let highlight = dynamic(light: 0xF0F0EC, dark: 0x2A2C2C)
    static let line = Color(nsColor: NSColor(name: nil) { a in
        a.isDark ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.12)
    })
    static let dot = Color(nsColor: NSColor(name: nil) { a in
        a.isDark ? NSColor.white.withAlphaComponent(0.035) : NSColor.black.withAlphaComponent(0.045)
    })

    /// The timeline panel background (and the menu bar swatch color).
    static var timeline: Color { dynamic(light: current.hex.timelineLight, dark: current.hex.timelineDark) }
    /// Buttons, links, "now" highlights. #C21D35/#F06377 for red is brighter than the spec's
    /// #E0364E dark value, to clear AA; the other themes are tuned the same way (see AccentHex).
    static var accent: Color { dynamic(light: current.hex.accentLight, dark: current.hex.accentDark) }
    static var onAccent: Color { dynamic(light: current.hex.onAccentLight, dark: current.hex.onAccentDark) }
    /// Text on the timeline panel.
    static var onTimeline: Color { dynamic(light: current.hex.onTimelineLight, dark: current.hex.onTimelineDark) }
    /// Dimmed text on the timeline panel (Sunrise, Hijri date).
    static var onTimelineDim: Color {
        dynamic(
            light: current.hex.onTimelineDimLight, dark: current.hex.onTimelineDimDark,
            lightHC: current.hex.onTimelineLight, darkHC: current.hex.onTimelineDark
        )
    }

    static func dynamic(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let hc = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            if a.isDark { return NSColor(hex: hc ? (darkHC ?? dark) : dark) }
            return NSColor(hex: hc ? (lightHC ?? light) : light)
        })
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The hex values behind one accent theme. Light-mode text sits on the bright (light) timeline
/// color, so it's near-black; dark-mode text sits on the darkened timeline color, so it's
/// near-white — the reverse of red's original panel, which is dark-enough in both modes for
/// light text throughout. Every pairing below is checked against WCAG AA (≥4.5:1 for body text).
private struct AccentHex {
    let timelineLight, timelineDark: UInt32
    let accentLight, accentDark: UInt32
    let onAccentLight, onAccentDark: UInt32
    let onTimelineLight, onTimelineDark: UInt32
    let onTimelineDimLight, onTimelineDimDark: UInt32
}

private extension AccentTheme {
    var hex: AccentHex {
        switch self {
        case .red:
            return AccentHex(
                timelineLight: 0xA10F24, timelineDark: 0x7E0C1C,
                accentLight: 0xC21D35, accentDark: 0xF06377,
                onAccentLight: 0xFFFFFF, onAccentDark: 0x1A0508,
                onTimelineLight: 0xFBEEF0, onTimelineDark: 0xFBEEF0,
                onTimelineDimLight: 0xE7BDC3, onTimelineDimDark: 0xD8AFB5
            )
        case .sage:
            return AccentHex(
                timelineLight: 0xA8BBA3, timelineDark: 0x5C675A,
                accentLight: 0x5C675A, accentDark: 0xC2CFBF,
                onAccentLight: 0xFFFFFF, onAccentDark: 0x171717,
                onTimelineLight: 0x171717, onTimelineDark: 0xEDEDEA,
                onTimelineDimLight: 0x2D302C, onTimelineDimDark: 0xBABEB8
            )
        case .blue:
            return AccentHex(
                timelineLight: 0x66A3BF, timelineDark: 0x3F6576,
                accentLight: 0x426A7C, accentDark: 0x94BFD2,
                onAccentLight: 0xFFFFFF, onAccentDark: 0x171717,
                onTimelineLight: 0x171717, onTimelineDark: 0xEDEDEA,
                onTimelineDimLight: 0x232C30, onTimelineDimDark: 0xB0BDC1
            )
        case .olive:
            return AccentHex(
                timelineLight: 0x97A87A, timelineDark: 0x5E684C,
                accentLight: 0x5B6549, accentDark: 0xB6C2A2,
                onAccentLight: 0xFFFFFF, onAccentDark: 0x171717,
                onTimelineLight: 0x171717, onTimelineDark: 0xEDEDEA,
                onTimelineDimLight: 0x2A2D26, onTimelineDimDark: 0xBBBEB3
            )
        case .forest:
            // Black-green: a deep forest panel with light text in both modes.
            return AccentHex(
                timelineLight: 0x2F4A3A, timelineDark: 0x1C2E24,
                accentLight: 0x2F5A41, accentDark: 0x8FC1A2,
                onAccentLight: 0xFFFFFF, onAccentDark: 0x111111,
                onTimelineLight: 0xEEF2EC, onTimelineDark: 0xEEF2EC,
                onTimelineDimLight: 0xB9C7BD, onTimelineDimDark: 0xA9B8AD
            )
        case .earth:
            // Green and brown: a bark-brown panel with moss-green accents.
            return AccentHex(
                timelineLight: 0x5A4A32, timelineDark: 0x3E3324,
                accentLight: 0x5E6B3A, accentDark: 0xB7C48E,
                onAccentLight: 0xFFFFFF, onAccentDark: 0x171717,
                onTimelineLight: 0xF3EDE3, onTimelineDark: 0xF3EDE3,
                onTimelineDimLight: 0xD5C8B3, onTimelineDimDark: 0xC2B59F
            )
        case .clay:
            // Terracotta.
            return AccentHex(
                timelineLight: 0x8C4425, timelineDark: 0x6E361E,
                accentLight: 0x9A4A26, accentDark: 0xE79A76,
                onAccentLight: 0xFFFFFF, onAccentDark: 0x1A0C06,
                onTimelineLight: 0xFBF0EA, onTimelineDark: 0xFBF0EA,
                onTimelineDimLight: 0xEBC9B8, onTimelineDimDark: 0xD9B4A2
            )
        }
    }
}

/// The swatch shown in the Settings picker, in the current appearance.
extension AccentTheme {
    /// The Dock icon's background and crescent for this theme.
    var iconColors: (background: NSColor, foreground: NSColor) {
        let h = hex
        // Red keeps the shipped icon's crimson; the light themes use their darker panel tone.
        let bg: UInt32 = self == .red ? 0xA10F24 : (h.onTimelineLight == 0x171717 ? h.timelineDark : h.timelineLight)
        return (NSColor(hex: bg), NSColor(hex: h.onTimelineDark))
    }

    func swatchColor(dark: Bool) -> Color {
        let h = hex
        return Color(nsColor: NSColor(hex: dark ? h.timelineDark : h.timelineLight))
    }
}
