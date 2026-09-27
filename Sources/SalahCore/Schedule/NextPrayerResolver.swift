import Foundation

public struct NextPrayer: Equatable, Sendable {
    public let prayer: Prayer
    public let time: Date
    /// True when the next prayer falls on the following local day (e.g. after Isha).
    public let isTomorrow: Bool
    /// The local day the prayer belongs to; used for the Jumu'ah label.
    public let date: LocalDate

    public func label(jumuahRelabel: Bool) -> String {
        prayer.label(isFriday: date.isFriday, jumuahRelabel: jumuahRelabel)
    }

    public func secondsRemaining(from now: Date) -> TimeInterval {
        max(0, time.timeIntervalSince(now))
    }
}

public enum NextPrayerResolver {
    /// The first prayer strictly after `now`, looking into the following days if needed.
    /// Returns nil only if no prayer can be calculated within a week (polar regions).
    public static func resolve(now: Date, location: SavedLocation, settings: CalculationSettings) -> NextPrayer? {
        let today = LocalDate(now, in: location.tz)
        for offset in 0..<7 {
            let schedule = PrayerSchedule.for(date: today.adding(days: offset), location: location, settings: settings)
            if let next = next(in: schedule, after: now, isTomorrow: offset > 0) { return next }
        }
        return nil
    }

    static func next(in schedule: DaySchedule, after now: Date, isTomorrow: Bool) -> NextPrayer? {
        for p in Prayer.prayers {
            if let t = schedule.time(p), t > now {
                return NextPrayer(prayer: p, time: t, isTomorrow: isTomorrow, date: schedule.date)
            }
        }
        return nil
    }
}

/// Everything the dashboard, menu bar and CLI need at one instant.
public struct PrayerClockState: Equatable, Sendable {
    public let now: Date
    public let today: DaySchedule
    public let next: NextPrayer?
    /// The prayer period `now` falls in, if any. Fajr's period ends at sunrise;
    /// before today's Fajr there is no current period on today's timeline.
    public let current: Prayer?
    /// Set while inside the NOW window after a prayer starts.
    public let nowPrayer: Prayer?

    public var secondsToNext: TimeInterval? { next.map { $0.secondsRemaining(from: now) } }

    /// Seconds since `nowPrayer` began.
    public var secondsSinceNow: TimeInterval? {
        guard let p = nowPrayer, let t = today.time(p) else { return nil }
        return max(0, now.timeIntervalSince(t))
    }
}

public enum PrayerClock {
    public static func state(
        now: Date, location: SavedLocation, settings: CalculationSettings, nowWindowMinutes: Int
    ) -> PrayerClockState {
        let date = LocalDate(now, in: location.tz)
        let today = PrayerSchedule.for(date: date, location: location, settings: settings)
        let next = NextPrayerResolver.resolve(now: now, location: location, settings: settings)

        var current: Prayer?
        for p in Prayer.prayers {
            if let t = today.time(p), t <= now { current = p }
        }
        if current == .fajr, let sunrise = today.time(.sunrise), now >= sunrise { current = nil }

        var nowPrayer: Prayer?
        if nowWindowMinutes > 0 {
            let window = TimeInterval(nowWindowMinutes * 60)
            for p in Prayer.prayers {
                if let t = today.time(p), t <= now, now < t.addingTimeInterval(window) { nowPrayer = p }
            }
        }
        return PrayerClockState(now: now, today: today, next: next, current: current, nowPrayer: nowPrayer)
    }
}
