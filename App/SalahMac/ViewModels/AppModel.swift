import AppKit
import Foundation
import OSLog
import SalahCore
import ServiceManagement

private let log = Logger(subsystem: SalahInfo.appBundleIdentifier, category: "app")

/// App state: the shared config (mirrored to disk), navigation, and notification upkeep.
@MainActor
final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case today, schedule, reminders, settings, about
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @Published var tab: Tab = .today
    @Published private(set) var config: SalahConfig = .default
    /// Set when the config file exists but can't be read. The dashboard shows a reset action.
    @Published private(set) var configError: String?
    /// A date the Today screen is previewing instead of today.
    @Published var previewDate: LocalDate?
    /// A prayer whose details replace the next-prayer display.
    @Published var detailPrayer: Prayer?
    @Published var showLocationSheet = false
    @Published private(set) var notificationAuth: NotificationScheduler.Authorization = .notDetermined
    @Published private(set) var scheduled: [PlannedNotification] = []
    @Published private(set) var loginItemMessage: String?

    let store = ConfigStore()
    let ticker = Ticker()
    let scheduler = NotificationScheduler()
    let locationProvider = LocationProvider()
    let updater = Updater()

    private var watcher: ConfigWatcher?
    private var observers: [NSObjectProtocol] = []
    private var replanTask: Task<Void, Never>?
    private var plannedDay: LocalDate?

    init() {
        loadFromDisk()
        scheduler.activate()
        watcher = ConfigWatcher(file: store.url) { [weak self] in
            MainActor.assumeIsolated { self?.loadFromDisk() }
        }
        locationProvider.onLocation = { [weak self] loc in
            self?.setLocation(loc)
        }
        ticker.onTick = { [weak self] now in self?.checkRollover(now) }
        observeSystem()
        applyAppearance()
        applyLaunchAtLogin()
        updater.start()
        Task {
            if config.reminders.enabled, config.location != nil, await scheduler.authorization() == .notDetermined {
                await scheduler.requestAuthorization()
            }
            await refreshAuthorization()
            replan()
        }
    }

    // MARK: - Derived

    var location: SavedLocation? { config.location }
    var display: DisplaySettings { config.display }
    var tz: TimeZone { config.location?.tz ?? .current }

    func clockState(at now: Date) -> PrayerClockState? {
        guard let loc = config.location, loc.isValid else { return nil }
        return PrayerClock.state(now: now, location: loc, settings: config.calculation, nowWindowMinutes: config.display.nowWindowMinutes)
    }

    func schedule(for date: LocalDate) -> DaySchedule? {
        guard let loc = config.location, loc.isValid else { return nil }
        return PrayerSchedule.for(date: date, location: loc, settings: config.calculation)
    }

    func today(at now: Date) -> LocalDate { LocalDate(now, in: tz) }

    func clock(_ date: Date) -> String {
        TimeFormatting.clock(date, in: tz, use24Hour: display.use24HourClock)
    }

    // MARK: - Config

    /// Applies a change, saves it atomically, and re-plans reminders.
    func update(_ body: (inout SalahConfig) -> Void) {
        var c = config
        body(&c)
        guard c != config else { return }
        let old = config
        config = c
        do {
            try store.save(c)
        } catch {
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
        didChange(from: old)
    }

    func setLocation(_ loc: SavedLocation) {
        update { $0.location = loc }
        showLocationSheet = false
        previewDate = nil
        detailPrayer = nil
    }

    func resetToDefaults() {
        let c = SalahConfig.default
        try? store.save(c)
        configError = nil
        let old = config
        config = c
        didChange(from: old)
    }

    /// Reloads after an external write (the CLI) or at launch.
    func loadFromDisk() {
        do {
            let c = try store.load()
            if configError != nil { log.info("Config readable again") }
            configError = nil
            guard c != config else { return }
            log.info("Config changed on disk; reloading")
            let old = config
            config = c
            didChange(from: old)
        } catch {
            log.error("Config unreadable: \(error.localizedDescription, privacy: .public)")
            configError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func didChange(from old: SalahConfig) {
        if old.display.theme != config.display.theme { applyAppearance() }
        if old.display.showMenuBarExtra != config.display.showMenuBarExtra { applyDockPolicy() }
        if old.launchAtLogin != config.launchAtLogin { applyLaunchAtLogin() }
        if old.reminders.enabled != config.reminders.enabled, config.reminders.enabled {
            Task { await ensureAuthorization() }
        }
        replan()
    }

    // MARK: - Reminders

    /// Debounced, idempotent top-up of the rolling window.
    func replan() {
        replanTask?.cancel()
        replanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            let now = Date()
            self.plannedDay = LocalDate(now, in: self.tz)
            self.scheduled = await self.scheduler.topUp(config: self.config, now: now)
            await self.refreshAuthorization()
            log.info("Reminder window topped up: \(self.scheduled.count) scheduled")
        }
    }

    func ensureAuthorization() async {
        if await scheduler.authorization() == .notDetermined {
            await scheduler.requestAuthorization()
        }
        await refreshAuthorization()
        replan()
    }

    func refreshAuthorization() async {
        notificationAuth = await scheduler.authorization()
    }

    func sendTestNotification() {
        let now = Date()
        let next = clockState(at: now)?.next
        let label = next?.label(jumuahRelabel: display.jumuahRelabel) ?? "Asr"
        let lead = next.map { config.reminders.reminder(for: $0.prayer).leadMinutes } ?? 10
        let title = NotificationPlanner.title(label: label, leadMinutes: lead == 0 ? 10 : lead)
        let body = next.flatMap { n in location.map { NotificationPlanner.body(time: n.time, location: $0, use24Hour: display.use24HourClock) } }
            ?? "Test notification"
        Task {
            _ = await scheduler.sendTest(title: title, body: body, sound: config.reminders.sound)
            await refreshAuthorization()
            replan()
        }
    }

    func pause(until date: Date?) {
        update { $0.reminders.pausedUntil = date }
    }

    // MARK: - System events

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        let refresh: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ticker.refresh()
                self?.replan()
            }
        }
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh))
        observers.append(nc.addObserver(forName: AppDelegate.reopenNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showMainWindow() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshAuthorization() }
            }
        })
    }

    /// Local midnight in the location's zone: swap the day and top up the window.
    private func checkRollover(_ now: Date) {
        let day = LocalDate(now, in: tz)
        if let plannedDay, day != plannedDay {
            self.plannedDay = day
            replan()
        }
    }

    // MARK: - Window and Dock

    /// Opens the main window. Set by views that can reach SwiftUI's `openWindow`.
    var openMainWindowAction: (() -> Void)?
    private(set) var isMainWindowOpen = false

    /// Brings back the main window, e.g. from the menu bar or when the app is opened again.
    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openMainWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func mainWindowDidOpen() {
        isMainWindowOpen = true
        applyDockPolicy()
    }

    /// Closing the window keeps Salah running in the menu bar (so reminders stay topped up);
    /// only Quit ends the app.
    func mainWindowDidClose() {
        isMainWindowOpen = false
        applyDockPolicy()
    }

    /// Dock icon while the window is open. With the window closed, Salah lives only in the
    /// menu bar — unless the menu bar item is off, in which case the Dock icon stays so the
    /// window can still be reopened.
    private func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy =
            isMainWindowOpen || !config.display.showMenuBarExtra ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    // MARK: - Appearance and login item

    private func applyAppearance() {
        switch config.display.theme {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        guard Bundle.main.bundleIdentifier != nil else {
            loginItemMessage = "Available when running Salah.app."
            return
        }
        do {
            if config.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
            loginItemMessage = service.status == .requiresApproval
                ? "Approve Salah in System Settings › General › Login Items."
                : nil
        } catch {
            loginItemMessage = "Couldn't update the login item: \(error.localizedDescription)"
        }
    }

    // MARK: - CLI install

    func installCommandLineTool() {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/salah")
        let target = "/usr/local/bin/salah"
        guard FileManager.default.isExecutableFile(atPath: source.path) else {
            alert("The command line tool isn't in this build of Salah.", info: "Build the app with scripts/build-app.sh, or see the README for a manual install.")
            return
        }
        try? FileManager.default.removeItem(atPath: target)
        if (try? FileManager.default.createSymbolicLink(atPath: target, withDestinationPath: source.path)) != nil {
            alert("Installed salah", info: "\(target) → \(source.path)")
            return
        }
        // /usr/local/bin usually needs admin rights.
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = "mkdir -p /usr/local/bin && ln -sf \(q(source.path)) \(q(target))"
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            alert("Couldn't install salah", info: (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error")
        } else {
            alert("Installed salah", info: "\(target) → \(source.path)")
        }
    }

    private func alert(_ message: String, info: String) {
        let a = NSAlert()
        a.messageText = message
        a.informativeText = info
        a.runModal()
    }
}
