import Foundation

/// A reminder the app should schedule. Pure data; the app maps it to `UNNotificationRequest`.
public struct PlannedNotification: Equatable, Hashable, Sendable {
    /// Deterministic: `salah.<yyyy-MM-dd>.<prayer>.<leadMinutes>`, or
    /// `salah.<yyyy-MM-dd>.kind.<slot>` for Kind Words.
    public let id: String
    public let fireDate: Date
    /// Nil for Kind Words.
    public let prayer: Prayer?
    public let prayerTime: Date?
    public let leadMinutes: Int
    public let date: LocalDate
    public let title: String
    public let body: String
    /// Delivered without sound, whatever the reminder sound is.
    public var silent: Bool = false
}

public enum NotificationPlanner {
    public static let idPrefix = "salah."
    public static let defaultDays = 3
    /// macOS keeps at most 64 pending requests per app; stay well under it.
    public static let maxPending = 48

    public static func identifier(date: LocalDate, prayer: Prayer, leadMinutes: Int) -> String {
        "\(idPrefix)\(date).\(prayer.rawValue).\(leadMinutes)"
    }

    /// Plans reminders, plus Kind Words when it's on, for `days` local days starting today.
    /// Entries in the past, inside quiet hours, or before the pause ends are left out entirely
    /// (never scheduled then suppressed).
    public static func plan(from now: Date, days: Int = defaultDays, config: SalahConfig) -> [PlannedNotification] {
        guard let location = config.location else { return [] }
        let r = config.reminders
        let cal = Calendar.gregorian(location.tz)
        let all = prayerReminders(from: now, days: days, config: config, location: location)
            + KindWordsPlanner.plan(from: now, days: days, config: config)
        let out = all.filter { item in
            guard item.fireDate > now else { return false }
            if let until = r.pausedUntil, item.fireDate < until { return false }
            let c = cal.dateComponents([.hour, .minute], from: item.fireDate)
            return !r.quietHours.contains(minuteOfDay: c.hour! * 60 + c.minute!)
        }
        .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(out.prefix(maxPending))
    }

    private static func prayerReminders(from now: Date, days: Int, config: SalahConfig, location: SavedLocation) -> [PlannedNotification] {
        guard config.reminders.enabled else { return [] }
        let r = config.reminders
        let start = LocalDate(now, in: location.tz)
        var out: [PlannedNotification] = []

        for schedule in PrayerSchedule.range(from: start, days: days, location: location, settings: config.calculation) {
            for prayer in Prayer.prayers {
                let reminder = r.reminder(for: prayer)
                guard reminder.enabled, let time = schedule.time(prayer) else { continue }
                let label = schedule.label(prayer, jumuahRelabel: config.display.jumuahRelabel)
                for lead in reminder.leads {
                    let fire = time.addingTimeInterval(TimeInterval(-lead * 60))
                    var text = body(time: time, location: location, use24Hour: config.display.use24HourClock)
                    if lead > 0, let line = KindWordsPlanner.beforePrayerLine(prayer: prayer, schedule: schedule, config: config) {
                        text += "\n" + line
                    }
                    out.append(PlannedNotification(
                        id: identifier(date: schedule.date, prayer: prayer, leadMinutes: lead),
                        fireDate: fire, prayer: prayer, prayerTime: time, leadMinutes: lead, date: schedule.date,
                        title: title(label: label, leadMinutes: lead), body: text
                    ))
                }
            }
        }
        return out
    }

    /// "Asr in 10 minutes" or "Time for Asr".
    public static func title(label: String, leadMinutes: Int) -> String {
        leadMinutes > 0 ? "\(label) in \(leadMinutes) minutes" : "Time for \(label)"
    }

    /// "4:05 PM · Singapore"
    public static func body(time: Date, location: SavedLocation, use24Hour: Bool) -> String {
        "\(TimeFormatting.clock(time, in: location.tz, use24Hour: use24Hour)) · \(location.name)"
    }
}
