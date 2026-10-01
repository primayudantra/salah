import Foundation

/// Why Salah is holding off: on a call, or in a Focus.
public enum BusyReason: Equatable, Sendable {
    case call(appName: String?)
    case focus
}

/// What the busy monitor currently reports.
public enum BusyState: Equatable, Sendable {
    case free
    case onCall(appName: String?)
    case focusOn
}

/// Why the card, when it finally shows, carries a "just ended" pill.
public enum CardNote: String, Equatable, Codable, Sendable {
    case callEnded
    case focusEnded
}

/// One thing the app should do, in the order the planner returns them.
public enum PlannedAction: Equatable, Sendable {
    case pauseMedia
    case focusOn
    case showCard(note: CardNote?)
    case showNudge(reason: BusyReason, cardLater: Bool)
    case deferUntilUnlock
    case deferUntilFree
}

/// Everything the planner needs to decide what happens for one prayer, at one instant.
public struct FocusModeContext: Equatable, Sendable {
    public let prayer: Prayer
    public let prayerTime: Date
    public let now: Date
    public let settings: FocusModeSettings
    public let busy: BusyState
    public let isScreenLocked: Bool
    /// Already ran the at-time actions for this prayer (dedup key `<date>.<prayer>`).
    public let alreadyHandled: Bool
    /// Salah itself turned on the currently-active Focus; that Focus doesn't count as "busy".
    public let salahOwnsFocus: Bool
    /// Set only when replaying a deferred card after a call or Focus ended; carries its pill.
    public let pendingNote: CardNote?

    public init(
        prayer: Prayer, prayerTime: Date, now: Date, settings: FocusModeSettings, busy: BusyState,
        isScreenLocked: Bool, alreadyHandled: Bool, salahOwnsFocus: Bool, pendingNote: CardNote? = nil
    ) {
        self.prayer = prayer
        self.prayerTime = prayerTime
        self.now = now
        self.settings = settings
        self.busy = busy
        self.isScreenLocked = isScreenLocked
        self.alreadyHandled = alreadyHandled
        self.salahOwnsFocus = salahOwnsFocus
        self.pendingNote = pendingNote
    }

    /// How late `now` is relative to prayer time; negative before it.
    var lateness: TimeInterval { now.timeIntervalSince(prayerTime) }
}

/// The single pure decision function for Focus Mode. Everything about what to do at prayer
/// time is decided here, with no side effects, so it is exhaustively unit-testable.
public enum FocusModePlanner {
    /// Actions are skipped once a trigger is more than this late (e.g. the Mac was asleep).
    public static let lateThreshold: TimeInterval = 10 * 60

    public static func decide(_ ctx: FocusModeContext) -> [PlannedAction] {
        let s = ctx.settings
        guard s.enabled, s.prayers.contains(ctx.prayer), !ctx.alreadyHandled, s.hasAnyAction else {
            return []
        }
        if ctx.isScreenLocked {
            return [.deferUntilUnlock]
        }

        if case .onCall(let appName) = ctx.busy {
            return busyActions(.call(appName: appName), settings: s)
        }
        if case .focusOn = ctx.busy, s.whenBusy.focusIsBusy, !ctx.salahOwnsFocus {
            return busyActions(.focus, settings: s)
        }

        let isLate = ctx.lateness > lateThreshold
        let withinAutoCloseWindow = ctx.now < ctx.prayerTime.addingTimeInterval(TimeInterval(s.card.autoCloseMinutes * 60))

        var actions: [PlannedAction] = []
        if !isLate {
            if s.pauseMedia.enabled { actions.append(.pauseMedia) }
            if s.focus.enabled { actions.append(.focusOn) }
        }
        if s.card.enabled, !isLate || withinAutoCloseWindow {
            actions.append(.showCard(note: ctx.pendingNote))
        }
        return actions
    }

    private static func busyActions(_ reason: BusyReason, settings s: FocusModeSettings) -> [PlannedAction] {
        let cardLater = s.card.enabled && s.whenBusy.onCall == .nudgeThenCard
        var actions: [PlannedAction] = [.showNudge(reason: reason, cardLater: cardLater)]
        if cardLater { actions.append(.deferUntilFree) }
        return actions
    }
}
