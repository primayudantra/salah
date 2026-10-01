import AppKit
import SwiftUI

/// One borderless window per screen, so the card covers every display and every Space. Only the
/// screen with the mouse shows the prayer name and buttons; the others show just the dimmed blur.
@MainActor
final class FocusModeCardController {
    var onDone: (() -> Void)?
    var onSnooze: (() -> Void)?

    private var windows: [NSWindow] = []
    private var keyMonitor: Any?

    var isShowing: Bool { !windows.isEmpty }

    func show(
        prayerName: String, timeText: String, locationName: String, pills: [String],
        autoCloseMinutes: Int, reduceMotion: Bool
    ) {
        close()
        let mainScreen = Self.screenUnderMouse() ?? NSScreen.main
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hasShadow = false
            window.isReleasedWhenClosed = false

            let view = FocusModeCardView(
                prayerName: prayerName, timeText: timeText, locationName: locationName, pills: pills,
                autoCloseMinutes: autoCloseMinutes, showContent: screen == mainScreen, reduceMotion: reduceMotion,
                onDone: { [weak self] in self?.onDone?() }, onSnooze: { [weak self] in self?.onSnooze?() }
            )
            window.contentView = NSHostingView(rootView: view)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first(where: { $0.screen == mainScreen })?.makeKey()
        installKeyMonitor()
    }

    /// Rebuilds the windows for the current screen set, keeping the content showing.
    func rebuildForScreenChange(
        prayerName: String, timeText: String, locationName: String, pills: [String],
        autoCloseMinutes: Int, reduceMotion: Bool
    ) {
        guard isShowing else { return }
        show(prayerName: prayerName, timeText: timeText, locationName: locationName, pills: pills, autoCloseMinutes: autoCloseMinutes, reduceMotion: reduceMotion)
    }

    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Esc closes the card the same as Done, from any screen's window.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isShowing == true else { return event }
            if event.keyCode == 53 { // Esc
                self?.onDone?()
                return nil
            }
            return event
        }
    }

    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}

/// A translucent, blurred backdrop like the mock's `backdrop-filter: blur(30px) saturate(.8)`.
private struct DarkBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct FocusModeCardView: View {
    let prayerName: String
    let timeText: String
    let locationName: String
    let pills: [String]
    let autoCloseMinutes: Int
    let showContent: Bool
    let reduceMotion: Bool
    let onDone: () -> Void
    let onSnooze: () -> Void

    @State private var appeared = false
    @State private var clockText = ""
    private let clockTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private let onAccent = Color(red: 0.878, green: 0.212, blue: 0.306) // #E0364E
    private let fg = Color(red: 0.929, green: 0.929, blue: 0.918) // #EDEDEA
    private let dim = Color(red: 0.604, green: 0.604, blue: 0.588) // #9A9A96

    var body: some View {
        ZStack {
            DarkBlur().ignoresSafeArea()
            Color.black.opacity(0.78).ignoresSafeArea()

            if showContent {
                VStack(spacing: 0) {
                    Spacer()
                    content
                    Spacer()
                }
                .frame(maxWidth: 560)
                .offset(y: appeared || reduceMotion ? 0 : 10)

                VStack {
                    HStack {
                        Spacer()
                        Text(clockText)
                            .font(.system(size: 13)).monospacedDigit()
                            .foregroundStyle(dim.opacity(0.85))
                            .padding(.top, 20).padding(.trailing, 24)
                    }
                    Spacer()
                    Text("Press Esc to close · Closes by itself in \(autoCloseMinutes) min")
                        .font(.system(size: 12))
                        .foregroundStyle(dim.opacity(0.6))
                        .padding(.bottom, 22)
                }
            }
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            updateClock()
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.9)) { appeared = true }
            }
        }
        .onReceive(clockTimer) { _ in updateClock() }
        .focusable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("It's time for \(prayerName), \(timeText)")
    }

    private var content: some View {
        VStack(spacing: 0) {
            Text("☾").font(.system(size: 28)).foregroundStyle(onAccent)
            Text("IT'S TIME FOR")
                .font(.system(size: 12, weight: .semibold)).tracking(4.3)
                .foregroundStyle(dim)
                .padding(.top, 22)
            PixelText(prayerName.uppercased(), size: 110, spoken: prayerName)
                .foregroundStyle(fg)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.top, 14)
            Text("\(timeText) · \(locationName)")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.741, green: 0.741, blue: 0.722))
                .padding(.top, 14)
            RoundedRectangle(cornerRadius: 1)
                .fill(onAccent)
                .frame(width: 64, height: 2)
                .padding(.vertical, 27)
            if !pills.isEmpty {
                FlowPills(pills: pills, fg: fg)
                    .frame(minHeight: 28)
            }
            VStack(spacing: 14) {
                Button("Done", action: onDone)
                    .buttonStyle(CardDoneButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Closes the card")
                Button("Remind me in 5 minutes", action: onSnooze)
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(dim)
                    .underline()
            }
            .padding(.top, 34)
        }
    }

    private func updateClock() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        clockText = f.string(from: Date())
    }
}

private struct CardDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(red: 0.090, green: 0.090, blue: 0.090))
            .padding(.horizontal, 46).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.929, green: 0.929, blue: 0.918).opacity(configuration.isPressed ? 0.85 : 1))
            )
    }
}

/// Wraps pills onto new lines, centered, like the mock's `flex-wrap: wrap; justify-content: center`.
private struct FlowPills: View {
    let pills: [String]
    let fg: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(pills, id: \.self) { pill in
                Text(pill)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(red: 0.812, green: 0.812, blue: 0.792))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(fg.opacity(0.08)))
            }
        }
    }
}
