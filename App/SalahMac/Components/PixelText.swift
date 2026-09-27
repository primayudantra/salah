import AppKit
import CoreText
import SwiftUI

/// The bundled Doto pixel font (SIL OFL 1.1). Used only for times, countdown and the prayer name on the display.
enum PixelFont {
    private(set) static var isAvailable = false

    /// Registers Doto from Contents/Resources/Fonts. Falls back to a monospaced system font if missing.
    static func register() {
        guard !isAvailable,
              let url = Bundle.main.url(forResource: "Doto", withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: "Doto", withExtension: "ttf")
        else { return }
        var error: Unmanaged<CFError>?
        isAvailable = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) || NSFont(name: "Doto-Black", size: 12) != nil
    }

    enum Weight { case bold, black }

    static func font(_ size: CGFloat, _ weight: Weight = .black) -> Font {
        if isAvailable {
            return .custom(weight == .black ? "Doto-Black" : "Doto-Bold", fixedSize: size)
        }
        return .system(size: size * 0.82, weight: weight == .black ? .heavy : .bold, design: .monospaced)
    }
}

/// Pixel-font text that exposes plain text to VoiceOver.
struct PixelText: View {
    let text: String
    var size: CGFloat
    var weight: PixelFont.Weight = .black
    var spoken: String?

    init(_ text: String, size: CGFloat, weight: PixelFont.Weight = .black, spoken: String? = nil) {
        self.text = text
        self.size = size
        self.weight = weight
        self.spoken = spoken
    }

    var body: some View {
        Text(text)
            .font(PixelFont.font(size, weight))
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(spoken ?? text)
    }
}

/// The display's fine dot-matrix texture, drawn from a tiny tiled image so ticks don't redraw it.
struct DottedBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle().fill(ImagePaint(image: scheme == .dark ? Self.darkTile : Self.lightTile, scale: 1))
    }

    // Built once; rebuilding per render showed up as bitmap churn on every countdown tick.
    private static let lightTile = Image(nsImage: tile(dark: false))
    private static let darkTile = Image(nsImage: tile(dark: true))

    static func tile(dark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 4, height: 4), flipped: false) { _ in
            (dark ? NSColor.white.withAlphaComponent(0.035) : NSColor.black.withAlphaComponent(0.05)).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 1.2, height: 1.2)).fill()
            return true
        }
    }
}
