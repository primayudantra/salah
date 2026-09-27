import AppKit
import Combine
import Foundation

/// The app's notion of "now". Ticks every second only while a Salah window is on screen
/// and the display is awake; otherwise once a minute (for the menu bar and rollovers).
@MainActor
final class Ticker: ObservableObject {
    @Published private(set) var now = Date()

    private var secondTimer: Timer?
    private var minuteTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var displayAsleep = false
    private var menuOpen = false

    /// Called after every tick, with the new time.
    var onTick: ((Date) -> Void)?

    init() {
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMode() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayAsleep = true; self?.updateMode() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayAsleep = false; self?.refresh() }
        })
        scheduleMinuteTimer()
    }

    /// Re-read the clock immediately (wake, clock or zone change).
    func refresh() {
        tick()
        scheduleMinuteTimer()
        updateMode()
    }

    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        if open { tick() }
        updateMode()
    }

    private func tick() {
        now = Date()
        onTick?(now)
    }

    private var needsSeconds: Bool {
        guard !displayAsleep else { return false }
        if menuOpen { return true }
        return NSApp.windows.contains { w in
            w.isVisible && w.canBecomeMain && w.occlusionState.contains(.visible)
        }
    }

    private func updateMode() {
        if needsSeconds {
            guard secondTimer == nil else { return }
            tick()
            // Align to the wall-clock second so the countdown and clock change together.
            let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 1.02)
            let t = Timer(fire: start, interval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            secondTimer = t
        } else {
            secondTimer?.invalidate()
            secondTimer = nil
        }
    }

    private func scheduleMinuteTimer() {
        minuteTimer?.invalidate()
        let next = Date(timeIntervalSince1970: (floor(Date().timeIntervalSince1970 / 60) + 1) * 60 + 0.05)
        let t = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.secondTimer == nil else { return }
                self.tick()
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        minuteTimer = t
    }
}
