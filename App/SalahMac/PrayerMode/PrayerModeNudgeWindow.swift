import AppKit
import SwiftUI

/// A non-activating floating panel, top right of the screen with the mouse. It never steals
/// focus or interrupts whatever the user is doing on a call or in a Focus.
@MainActor
final class PrayerModeNudgeController {
    /// "Skip this time" — cancels the deferred card for this prayer. "Got it" and auto-hide are
    /// equivalent (the deferred card, if any, was already scheduled by the caller before showing).
    var onSkip: (() -> Void)?

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(prayerTimeLine: String, reasonLabel: String, bodyText: String, showSkip: Bool) {
        close()
        guard let screen = Self.screenUnderMouse() else { return }
        let size = NSSize(width: 360, height: 150)
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 14, y: screen.visibleFrame.maxY - size.height - 14)
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true

        let view = NudgeView(
            prayerTimeLine: prayerTimeLine, reasonLabel: reasonLabel, bodyText: bodyText, showSkip: showSkip,
            onDismiss: { [weak self] in self?.close() },
            onSkip: { [weak self] in self?.onSkip?(); self?.close() },
            onHoverChanged: { [weak self] hovering in self?.setAutoHidePaused(hovering) }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleAutoHide()
    }

    func close() {
        hideTimer?.invalidate(); hideTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func scheduleAutoHide() {
        hideTimer?.invalidate()
        let t = Timer(timeInterval: 15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        RunLoop.main.add(t, forMode: .common)
        hideTimer = t
    }

    private func setAutoHidePaused(_ paused: Bool) {
        if paused { hideTimer?.invalidate(); hideTimer = nil } else { scheduleAutoHide() }
    }

    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }
}

struct NudgeView: View {
    let prayerTimeLine: String
    let reasonLabel: String
    let bodyText: String
    let showSkip: Bool
    let onDismiss: () -> Void
    let onSkip: () -> Void
    let onHoverChanged: (Bool) -> Void

    private let fg = Color(red: 0.929, green: 0.929, blue: 0.918)
    private let dim = Color(red: 0.812, green: 0.812, blue: 0.792)
    private let accent = Color(red: 0.878, green: 0.212, blue: 0.306)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("☾")
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.631, green: 0.059, blue: 0.141)))
                    .foregroundStyle(fg)
                Text(prayerTimeLine).font(.system(size: 14, weight: .semibold)).foregroundStyle(fg)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(reasonLabel).font(.system(size: 11)).foregroundStyle(accent)
                }
            }
            Text(bodyText)
                .font(.system(size: 13))
                .foregroundStyle(dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                if showSkip {
                    Button("Skip this time", action: onSkip).buttonStyle(NudgeButtonStyle(primary: false))
                }
                Button("Got it", action: onDismiss).buttonStyle(NudgeButtonStyle(primary: true))
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow)
                Color.black.opacity(0.35)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onHover(perform: onHoverChanged)
        .accessibilityElement(children: .combine)
    }
}

private struct NudgeButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? Color(red: 0.090, green: 0.090, blue: 0.090) : Color(red: 0.929, green: 0.929, blue: 0.918))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(primary ? Color(red: 0.929, green: 0.929, blue: 0.918) : Color.white.opacity(configuration.isPressed ? 0.2 : 0.12))
            )
    }
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
