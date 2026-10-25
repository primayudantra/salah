import AppKit
import SalahCore

/// Draws the app icon in an accent theme's colors, for the Dock while Salah runs. Same artwork as
/// scripts/make-assets.sh (crescent and a small timeline); Finder and Launchpad keep the bundled
/// red icon, since rewriting the app bundle's icon would break its code signature.
enum AppIconRenderer {
    /// Sets the Dock icon. Red is the bundled icon, so it restores that one.
    @MainActor
    static func apply(_ theme: AccentTheme) {
        // At launch the model is built before NSApplication exists; set it once it does.
        guard let app = NSApp as NSApplication? else {
            DispatchQueue.main.async { apply(theme) }
            return
        }
        app.applicationIconImage = theme == .red ? nil : image(for: theme)
    }

    static func image(for theme: AccentTheme, size: CGFloat = 512) -> NSImage {
        let (bgColor, fg) = theme.iconColors
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let s = size
            let inset = s * 0.1
            let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
            let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
            bgColor.setFill(); bg.fill()
            // crescent
            let c = NSPoint(x: rect.midX + rect.width * 0.08, y: rect.midY + rect.height * 0.08), r = rect.width * 0.26
            let moon = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            let cut = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.55, y: c.y - r * 0.8, width: 2 * r, height: 2 * r))
            NSGraphicsContext.current!.saveGraphicsState()
            moon.addClip()
            fg.setFill(); moon.fill()
            bgColor.setFill(); cut.fill()
            NSGraphicsContext.current!.restoreGraphicsState()
            // timeline dots
            let x = rect.minX + rect.width * 0.22
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: rect.minY + rect.height * 0.18))
            line.line(to: NSPoint(x: x, y: rect.maxY - rect.height * 0.18))
            line.lineWidth = max(1, s * 0.012); fg.withAlphaComponent(0.6).setStroke(); line.stroke()
            for i in 0..<5 {
                let y = rect.minY + rect.height * (0.18 + 0.16 * CGFloat(i)), d = rect.width * 0.06
                fg.setFill(); NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
            }
            return true
        }
    }
}
