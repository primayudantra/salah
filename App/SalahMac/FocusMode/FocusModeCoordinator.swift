import AppKit
import CoreGraphics
import Foundation
import OSLog
import SalahCore

private let log = Logger(subsystem: SalahInfo.appBundleIdentifier, category: "focus-mode")

/// Orchestrates Focus Mode: arms a timer for the next selected prayer, asks `FocusModePlanner`
/// what to do, and executes that through the busy monitor, media and Focus controllers, and the
/// card/nudge windows. The planner itself is pure and fully unit-tested; this class is the
/// integration layer around it and is covered by manual testing (see roadmap/focus-mode.md §13).
@MainActor
final class FocusModeCoordinator {
    /// A deferred card may only appear within this long after its prayer time.
    private static let prayerWindow: TimeInterval = 60 * 60
    private static let snoozeInterval: TimeInterval = 5 * 60
    private static let maxSnoozes = 3
    private static let focusPollInterval: TimeInterval = 30

    private let stateStore: FocusModeStateStore
    private let busyMonitor: BusyMonitoring
    private let media: MediaControlling
    private let focus: FocusControlling
    private let card: FocusModeCardController
    private let nudge: FocusModeNudgeController

    private var fireTimer: Timer?
    private var focusPollTimer: Timer?
    private var busy: BusyState = .free
    private var observers: [NSObjectProtocol] = []

    /// The prayer deferred waiting for the user to be free, with the pill its replay should carry.
    private var deferred: (prayer: Prayer, date: LocalDate, time: Date, note: CardNote?)?
    /// Set while the card for this prayer is on screen, so a later-fired timer can close it first.
    private var showing: (prayer: Prayer, date: LocalDate, time: Date)?

    var configProvider: (() -> SalahConfig)!
    var nowProvider: () -> Date = Date.init
    /// A one-line status for the Focus Mode screen, e.g. a denied permission. `nil` clears it.
    var onStatusMessage: ((String?) -> Void)?

    /// Default-argument expressions aren't actor-isolated even in an `@MainActor` init, so the
    /// adapters are constructed by the caller (always on the main actor) and passed in.
    init(configURL: URL, busyMonitor: BusyMonitoring, media: MediaControlling, focus: FocusControlling) {
        self.stateStore = FocusModeStateStore(configURL: configURL)
        self.busyMonitor = busyMonitor
        self.media = media
        self.focus = focus
        self.card = FocusModeCardController()
        self.nudge = FocusModeNudgeController()
        self.busyMonitor.onChange = { [weak self] state in MainActor.assumeIsolated { self?.busyDidChange(state) } }
        self.nudge.onSkip = { [weak self] in MainActor.assumeIsolated { self?.deferred = nil } }
        self.card.onDone = { [weak self] in MainActor.assumeIsolated { self?.handleDone() } }
        self.card.onSnooze = { [weak self] in MainActor.assumeIsolated { self?.handleSnooze() } }
    }

    func start() {
        busyMonitor.start()
        busy = busyMonitor.currentState()
        observeSystem()
        Task { await recoverFromCrashIfNeeded() }
        refresh()
    }

    /// Re-arms the timer and re-checks the status line. Call after config, location or date changes.
    func stop() {
        busyMonitor.stop()
        fireTimer?.invalidate()
        focusPollTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    func refresh() {
        updateStatusMessage()
        arm()
    }

    /// Turns off a Focus Salah owns and closes the card. Called on quit.
    func prepareForQuit() {
        card.close()
        nudge.close()
        let state = stateStore.load()
        if state.salahTurnedFocusOn {
            Task { _ = await focus.turnOff() }
            stateStore.update { $0.salahTurnedFocusOn = false }
        }
    }

    // MARK: - Arming

    private func arm() {
        fireTimer?.invalidate()
        guard let config = configProvider?(), let location = config.location, location.isValid, config.focusMode.enabled else { return }
        guard let next = nextSelectedOccurrence(from: nowProvider(), location: location, settings: config.calculation, prayers: config.focusMode.prayers) else { return }
        let fireAt = next.time
        let interval = max(0.5, fireAt.timeIntervalSince(nowProvider()))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(next) }
        }
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = timer
    }

    private func nextSelectedOccurrence(
        from now: Date, location: SavedLocation, settings: CalculationSettings, prayers: Set<Prayer>
    ) -> (prayer: Prayer, date: LocalDate, time: Date)? {
        guard !prayers.isEmpty else { return nil }
        let today = LocalDate(now, in: location.tz)
        for offset in 0..<8 {
            let date = today.adding(days: offset)
            let schedule = PrayerSchedule.for(date: date, location: location, settings: settings)
            for p in Prayer.prayers where prayers.contains(p) {
                if let t = schedule.time(p), t > now { return (p, date, t) }
            }
        }
        return nil
    }

    // MARK: - Firing

    private func fire(_ occurrence: (prayer: Prayer, date: LocalDate, time: Date)) {
        if let showing { close(showing, resume: false, focusOff: true) }
        evaluate(occurrence, pendingNote: nil)
        arm()
    }

    private func evaluate(_ occurrence: (prayer: Prayer, date: LocalDate, time: Date), pendingNote: CardNote?, idOverride: String? = nil) {
        guard let config = configProvider?() else { return }
        let state = stateStore.load()
        let id = idOverride ?? prayerHandledID(occurrence.date, occurrence.prayer)
        let context = FocusModeContext(
            prayer: occurrence.prayer, prayerTime: occurrence.time, now: nowProvider(), settings: config.focusMode,
            busy: busy, isScreenLocked: Self.readScreenLocked(), alreadyHandled: idOverride == nil && state.lastHandledID == id,
            salahOwnsFocus: state.salahTurnedFocusOn, pendingNote: pendingNote
        )
        let actions = FocusModePlanner.decide(context)
        guard !actions.isEmpty else { return }
        execute(actions, occurrence: occurrence, id: id)
    }

    private func execute(_ actions: [PlannedAction], occurrence: (prayer: Prayer, date: LocalDate, time: Date), id: String) {
        for action in actions {
            switch action {
            case .deferUntilUnlock:
                deferred = (occurrence.prayer, occurrence.date, occurrence.time, nil)
            case .deferUntilFree:
                deferred = (occurrence.prayer, occurrence.date, occurrence.time, noteForCurrentBusy())
            case .showNudge(let reason, let cardLater):
                presentNudge(reason: reason, occurrence: occurrence, showSkip: cardLater)
            case .pauseMedia:
                markHandled(id)
                Task { await runPauseMedia() }
            case .focusOn:
                markHandled(id)
                Task { await runFocusOn() }
            case .showCard(let note):
                markHandled(id)
                deferred = nil
                presentCard(occurrence: occurrence, note: note)
            }
        }
    }

    private func noteForCurrentBusy() -> CardNote? {
        if case .onCall = busy { return .callEnded }
        if case .focusOn = busy { return .focusEnded }
        return nil
    }

    private func markHandled(_ id: String) {
        stateStore.update { $0.lastHandledID = id }
    }

    // MARK: - Actions

    private func runPauseMedia() async {
        let paused = await media.pauseIfPlaying(MediaApp.all)
        stateStore.update { $0.pausedApps.formUnion(paused.map { $0.bundleID }) }
    }

    private func runFocusOn() async {
        guard await focus.shortcutsInstalled() else {
            onStatusMessage?("Salah Focus shortcuts not found. Add Shortcuts…")
            return
        }
        if await focus.turnOn() {
            stateStore.update { $0.salahTurnedFocusOn = true }
        } else {
            log.error("Turning Focus on failed or timed out")
        }
    }

    private func presentCard(occurrence: (prayer: Prayer, date: LocalDate, time: Date), note: CardNote?) {
        nudge.close()
        guard let config = configProvider?() else { return }
        let display = config.display
        let label = occurrence.date.isFriday && display.jumuahRelabel && occurrence.prayer == .dhuhr ? "Jumu'ah" : occurrence.prayer.name
        let tz = config.location?.tz ?? .current
        let timeText = TimeFormatting.clock(occurrence.time, in: tz, use24Hour: display.use24HourClock)
        let locationName = config.location?.name ?? ""

        var pills: [String] = []
        if let note {
            pills.append(note == .callEnded ? "Your call just ended" : "Your Focus just turned off")
        }
        if config.focusMode.pauseMedia.enabled { pills.append("Music paused") }
        if config.focusMode.focus.enabled { pills.append("Focus on") }

        showing = occurrence
        card.show(
            prayerName: label, timeText: timeText, locationName: locationName, pills: pills,
            autoCloseMinutes: config.focusMode.card.autoCloseMinutes, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        NotificationScheduler.removeDeliveredAtTimeNotification(date: occurrence.date, prayer: occurrence.prayer)
        scheduleAutoClose(occurrence)
    }

    private func presentNudge(reason: BusyReason, occurrence: (prayer: Prayer, date: LocalDate, time: Date), showSkip: Bool) {
        guard let config = configProvider?() else { return }
        let display = config.display
        let label = occurrence.date.isFriday && display.jumuahRelabel && occurrence.prayer == .dhuhr ? "Jumu'ah" : occurrence.prayer.name
        let tz = config.location?.tz ?? .current
        let timeText = TimeFormatting.clock(occurrence.time, in: tz, use24Hour: display.use24HourClock)

        let reasonLabel: String
        let bodyApp: String
        switch reason {
        case .call(let appName):
            reasonLabel = appName.map { "On a call in \($0)" } ?? "On a call"
            bodyApp = appName.map { "a call in \($0)" } ?? "a call"
        case .focus:
            reasonLabel = "Focus on"
            bodyApp = ""
        }
        let bodyText: String
        switch reason {
        case .call:
            bodyText = showSkip
                ? "You're on \(bodyApp), so Salah won't take over your screen. The card will show when your call ends."
                : "You're on \(bodyApp), so Salah won't take over your screen or pause anything."
        case .focus:
            bodyText = showSkip
                ? "You have a Focus on, so Salah won't take over your screen. The card will show when it turns off."
                : "You have a Focus on, so Salah won't take over your screen or pause anything."
        }

        if focusPollTimer == nil, case .focus = reason {
            startFocusPolling()
        }
        nudge.show(prayerTimeLine: "\(label) · \(timeText)", reasonLabel: reasonLabel, bodyText: bodyText, showSkip: showSkip)
    }

    // MARK: - Closing

    private func handleDone() {
        guard let occurrence = showing else {
            card.close() // a preview card has no `showing`; just close it
            return
        }
        guard let config = configProvider?() else { return }
        let pm = config.focusMode
        close(occurrence, resume: pm.pauseMedia.enabled && pm.pauseMedia.resumeOnDone, focusOff: pm.focus.enabled && pm.focus.turnOffOnDone)
        stateStore.update { $0.snoozeCount = 0 }
    }

    private func handleSnooze() {
        guard let occurrence = showing else {
            card.close()
            return
        }
        card.close()
        showing = nil
        let state = stateStore.update { $0.snoozeCount += 1 }
        guard state.snoozeCount <= Self.maxSnoozes, nowProvider() < occurrence.time.addingTimeInterval(Self.prayerWindow) else {
            // Snooze limit reached, or past the prayer window: stop trying for this prayer.
            return
        }
        let timer = Timer(timeInterval: Self.snoozeInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.replaySnoozed(occurrence) }
        }
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = nil // the snooze timer takes over; arm() re-establishes the next-prayer timer after
    }

    private func replaySnoozed(_ occurrence: (prayer: Prayer, date: LocalDate, time: Date)) {
        guard nowProvider() < occurrence.time.addingTimeInterval(Self.prayerWindow) else { return }
        presentCard(occurrence: occurrence, note: nil)
    }

    private func scheduleAutoClose(_ occurrence: (prayer: Prayer, date: LocalDate, time: Date)) {
        guard let minutes = configProvider?().focusMode.card.autoCloseMinutes else { return }
        let deadline = occurrence.time.addingTimeInterval(TimeInterval(minutes * 60))
        let interval = max(1, deadline.timeIntervalSince(nowProvider()))
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self, self.showing?.prayer == occurrence.prayer, self.showing?.date == occurrence.date else { return }
            self.close(occurrence, resume: false, focusOff: self.configProvider?().focusMode.focus.enabled ?? false)
        }
    }

    private func close(_ occurrence: (prayer: Prayer, date: LocalDate, time: Date), resume: Bool, focusOff: Bool) {
        card.close()
        if showing?.prayer == occurrence.prayer, showing?.date == occurrence.date { showing = nil }
        stopFocusPollingIfIdle()
        let state = stateStore.load()
        if resume, !state.pausedApps.isEmpty {
            let apps = Set(MediaApp.all.filter { state.pausedApps.contains($0.bundleID) })
            Task { await media.resume(apps) }
            stateStore.update { $0.pausedApps.removeAll() }
        }
        if focusOff, state.salahTurnedFocusOn {
            Task { _ = await focus.turnOff() }
            stateStore.update { $0.salahTurnedFocusOn = false }
        }
    }

    // MARK: - Real test run (actually pauses media / turns on Focus — unlike the previews below)

    /// Runs the real action pipeline right now, as if "Asr" were happening this second, honouring
    /// current settings and busy state. Unlike a preview, this really pauses Spotify/Apple Music
    /// and turns a Focus on — so you can check that part works without waiting for a real prayer.
    /// Uses a `test.` id that never collides with real prayer dedup, so it doesn't disturb the
    /// schedule, and does not arm or disarm the real prayer timer.
    func runRealTestNow() {
        let now = nowProvider()
        let testOccurrence = (prayer: Prayer.asr, date: LocalDate(now, in: configProvider?().location?.tz ?? .current), time: now)
        evaluate(testOccurrence, pendingNote: nil, idOverride: "test.\(UUID().uuidString)")
    }

    // MARK: - Previews (never pause media, change Focus, or mark a prayer handled)

    func previewCard(prayerName: String, timeText: String, locationName: String, pills: [String], autoCloseMinutes: Int) {
        nudge.close()
        card.show(
            prayerName: prayerName, timeText: timeText, locationName: locationName, pills: pills,
            autoCloseMinutes: autoCloseMinutes, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        showing = nil // previews never mark a real prayer as showing, so Done/snooze just close it
    }

    func previewNudge(reason: BusyReason, prayerTimeLine: String, cardLater: Bool) {
        let reasonLabel: String
        let bodyApp: String
        switch reason {
        case .call(let appName):
            reasonLabel = appName.map { "On a call in \($0)" } ?? "On a call"
            bodyApp = appName.map { "a call in \($0)" } ?? "a call"
        case .focus:
            reasonLabel = "Focus on"
            bodyApp = ""
        }
        let bodyText: String
        switch reason {
        case .call:
            bodyText = cardLater
                ? "You're on \(bodyApp), so Salah won't take over your screen. The card will show when your call ends."
                : "You're on \(bodyApp), so Salah won't take over your screen or pause anything."
        case .focus:
            bodyText = cardLater
                ? "You have a Focus on, so Salah won't take over your screen. The card will show when it turns off."
                : "You have a Focus on, so Salah won't take over your screen or pause anything."
        }
        nudge.show(prayerTimeLine: prayerTimeLine, reasonLabel: reasonLabel, bodyText: bodyText, showSkip: cardLater)
    }

    // MARK: - Busy transitions

    private func busyDidChange(_ state: BusyState) {
        let wasBusy = busy
        busy = state
        guard case .free = state else { return }
        guard let deferred else { return }
        self.deferred = nil
        guard nowProvider() < deferred.time.addingTimeInterval(Self.prayerWindow) else { return }
        // Only replay if the thing that ended matches what we deferred for.
        let note: CardNote?
        if case .onCall = wasBusy { note = .callEnded } else if case .focusOn = wasBusy { note = .focusEnded } else { note = nil }
        evaluate((deferred.prayer, deferred.date, deferred.time), pendingNote: note ?? deferred.note)
    }

    private func startFocusPolling() {
        let t = Timer(timeInterval: Self.focusPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollFocus() }
        }
        RunLoop.main.add(t, forMode: .common)
        focusPollTimer = t
    }

    private func stopFocusPollingIfIdle() {
        guard deferred == nil else { return }
        focusPollTimer?.invalidate()
        focusPollTimer = nil
    }

    private func pollFocus() {
        guard let isFocused = FocusStatusMonitor.isFocused() else { return }
        let newState: BusyState = isFocused ? .focusOn : .free
        guard newState != busy else { return }
        busyDidChange(newState)
    }

    // MARK: - System events

    private func observeSystem() {
        let nc = NotificationCenter.default, dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenDidUnlock() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildCardForScreenChange() }
        })
    }

    private func screenDidUnlock() {
        guard let deferred else { return }
        self.deferred = nil
        guard nowProvider() < deferred.time.addingTimeInterval(Self.prayerWindow) else { return }
        evaluate((deferred.prayer, deferred.date, deferred.time), pendingNote: nil)
    }

    private func rebuildCardForScreenChange() {
        guard let occurrence = showing, let config = configProvider?() else { return }
        let display = config.display
        let label = occurrence.date.isFriday && display.jumuahRelabel && occurrence.prayer == .dhuhr ? "Jumu'ah" : occurrence.prayer.name
        let tz = config.location?.tz ?? .current
        card.rebuildForScreenChange(
            prayerName: label, timeText: TimeFormatting.clock(occurrence.time, in: tz, use24Hour: display.use24HourClock),
            locationName: config.location?.name ?? "", pills: [], autoCloseMinutes: config.focusMode.card.autoCloseMinutes,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    private func updateStatusMessage() {
        guard let config = configProvider?(), config.focusMode.enabled else { onStatusMessage?(nil); return }
        if config.focusMode.focus.enabled {
            Task {
                let installed = await focus.shortcutsInstalled()
                if !installed { self.onStatusMessage?("Salah Focus shortcuts not found. Add Shortcuts…") }
            }
        }
    }

    private func recoverFromCrashIfNeeded() async {
        let state = stateStore.load()
        guard state.salahTurnedFocusOn else { return }
        log.info("Recovering: turning off a Focus left on by a previous run")
        _ = await focus.turnOff()
        stateStore.update { $0.salahTurnedFocusOn = false }
    }

    private static func readScreenLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
