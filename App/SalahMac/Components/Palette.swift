import AppKit
import SwiftUI

/// Colors from the spec, refined for WCAG AA. Each resolves per appearance, and
/// strengthens secondary tones when Increase Contrast is on.
enum Palette {
    static let background = dynamic(light: 0xF3F4F1, dark: 0x121212)
    static let chrome = dynamic(light: 0xECEDE9, dark: 0x1A1B1B)
    static let display = dynamic(light: 0xE4E7E6, dark: 0x1E2020)
    static let timeline = dynamic(light: 0xA10F24, dark: 0x7E0C1C)
    /// #C21D35 light (4.8:1 on display); #F06377 dark (5.3:1), brighter than the spec's #E0364E to pass AA.
    static let accent = dynamic(light: 0xC21D35, dark: 0xF06377)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1A0508)
    static let text = dynamic(light: 0x171717, dark: 0xEDEDEA)
    /// #5E5E5C light (5.2:1), darker than the spec's #777777, which fails AA on the display.
    // Dark secondary brightened from 0x9A9A96: too dim against the menu bar popover's translucent material.
    static let secondary = dynamic(light: 0x5E5E5C, dark: 0xBFBFBB, lightHC: 0x3A3A38, darkHC: 0xC8C8C4)
    static let highlight = dynamic(light: 0xF0F0EC, dark: 0x2A2C2C)
    static let onTimeline = dynamic(light: 0xFBEEF0, dark: 0xFBEEF0)
    /// Dimmed text on the red timeline: 4.8:1 light, 5.5:1 dark.
    static let onTimelineDim = dynamic(light: 0xE7BDC3, dark: 0xD8AFB5, lightHC: 0xFBEEF0, darkHC: 0xFBEEF0)
    static let line = Color(nsColor: NSColor(name: nil) { a in
        a.isDark ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.12)
    })
    static let dot = Color(nsColor: NSColor(name: nil) { a in
        a.isDark ? NSColor.white.withAlphaComponent(0.035) : NSColor.black.withAlphaComponent(0.045)
    })

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
