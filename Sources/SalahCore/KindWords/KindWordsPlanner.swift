import Foundation

/// Plans Kind Words notifications (roadmap/kind-words.md). Pure, like `NotificationPlanner`,
/// which merges this output with the prayer reminders.
public enum KindWordsPlanner {
    /// A daytime kind word is skipped when a prayer time is this close.
    public static let prayerGapMinutes = 45
    /// …or when another Kind Words notification is this close.
    public static let kindGapMinutes = 30

    /// Notifications for `days` local days starting today. Pause and quiet hours are applied by
    /// the caller, the same way as for prayer reminders.
    public static func plan(
        from now: Date, days: Int, config: SalahConfig, library: KindWordsLibrary = .bundled
    ) -> [PlannedNotification] {
        let k = config.kindWords
        guard k.enabled, let location = config.location else { return [] }
        let tz = location.tz
        let start = LocalDate(now, in: tz)
        var out: [PlannedNotification] = []

        for schedule in PrayerSchedule.range(from: start, days: days, location: location, settings: config.calculation) {
            let date = schedule.date
            var fixed: [PlannedNotification] = []
            func add(_ slot: String, _ fire: Date, _ title: String, _ body: String) {
                fixed.append(PlannedNotification(
                    id: identifier(date: date, slot: slot), fireDate: fire, prayer: nil, prayerTime: nil,
                    leadMinutes: 0, date: date, title: title, body: body, silent: k.silent
                ))
            }

            if k.afterPrayer {
                let pool = library.words(.afterPrayer)
                for (i, prayer) in Prayer.prayers.enumerated() {
                    guard let time = schedule.time(prayer), !pool.isEmpty else { continue }
                    let fire = time.addingTimeInterval(TimeInterval(k.afterPrayerMinutes * 60))
                    // Never ask about a prayer once the next one has begun.
                    if let next = nextTime(after: prayer, in: schedule), fire >= next { continue }
                    let label = schedule.label(prayer, jumuahRelabel: config.display.jumuahRelabel)
                    let word = pick(pool, date: date, salt: i)
                    add("after-\(prayer.rawValue)", fire, "Have you prayed \(label)?", word.notificationBody)
                }
            }

            if k.friday, date.isFriday {
                if let kahf = library.word(id: KindWordsLibrary.kahfId) {
                    add("friday-kahf", at(8 * 60, on: date, tz: tz), "It’s Friday — Al-Kahf today", kahf.notificationBody)
                }
                if let maghrib = schedule.time(.maghrib), let lastHour = library.word(id: KindWordsLibrary.lastHourId) {
                    add("friday-lasthour", maghrib.addingTimeInterval(-3600), "The last hour of Friday", lastHour.notificationBody)
                }
            }

            if k.workDuas, !(date.weekday == 1 || date.weekday == 7) {
                let starts = library.duas(.beforeWork), ends = library.duas(.afterWork)
                if let m = QuietHours.minutes(k.workStart), !starts.isEmpty {
                    add("work-start", at(m, on: date, tz: tz), "Before you begin", pick(starts, date: date, salt: 0).notificationBody)
                }
                if let m = QuietHours.minutes(k.workEnd), !ends.isEmpty {
                    add("work-end", at(m, on: date, tz: tz), "Close the day gently", pick(ends, date: date, salt: 1).notificationBody)
                }
            }

            out += fixed

            let prayerTimes = Prayer.prayers.compactMap { schedule.time($0) }
            let words = library.words(.kindWord)
            var placed = fixed.map(\.fireDate)
            var sentSalawat = false
            for (i, minute) in k.cadence.slots.enumerated() where !words.isEmpty {
                let fire = at(minute, on: date, tz: tz)
                if prayerTimes.contains(where: { abs($0.timeIntervalSince(fire)) < TimeInterval(prayerGapMinutes * 60) }) { continue }
                if placed.contains(where: { abs($0.timeIntervalSince(fire)) < TimeInterval(kindGapMinutes * 60) }) { continue }
                placed.append(fire)
                var word = pick(words, date: date, salt: i)
                // The first kind word on a Friday is the salawat reminder.
                if k.friday, date.isFriday, !sentSalawat, let salawat = library.word(id: KindWordsLibrary.salawatId) {
                    word = salawat
                    sentSalawat = true
                }
                out.append(PlannedNotification(
                    id: identifier(date: date, slot: String(format: "word-%02d%02d", minute / 60, minute % 60)),
                    fireDate: fire, prayer: nil, prayerTime: nil, leadMinutes: 0, date: date,
                    title: title(forMinute: minute), body: word.notificationBody, silent: k.silent
                ))
            }
        }
        return out.filter { $0.fireDate > now }
    }

    /// The line added to an early prayer reminder, or nil when Kind Words or this option is off.
    /// Jumu'ah gets Al-Jumu'ah 62:9.
    public static func beforePrayerLine(
        prayer: Prayer, schedule: DaySchedule, config: SalahConfig, library: KindWordsLibrary = .bundled
    ) -> String? {
        guard config.kindWords.enabled, config.kindWords.beforePrayer else { return nil }
        if prayer == .dhuhr, schedule.isFriday, let jumuah = library.word(id: KindWordsLibrary.jumuahId) {
            return jumuah.notificationBody
        }
        let pool = library.words(.beforePrayer)
        guard !pool.isEmpty else { return nil }
        let salt = Prayer.prayers.firstIndex(of: prayer) ?? 0
        return pick(pool, date: schedule.date, salt: salt).notificationBody
    }

    public static func identifier(date: LocalDate, slot: String) -> String {
        "\(NotificationPlanner.idPrefix)\(date).kind.\(slot)"
    }

    /// "Good morning", "Good afternoon"… by the slot's hour.
    public static func title(forMinute minute: Int) -> String {
        switch minute / 60 {
        case ..<12: return "Good morning"
        case 12..<15: return "A moment of calm"
        case 15..<19: return "Good afternoon"
        default: return "Rest well"
        }
    }

    /// Stable across launches and top-ups, so a re-plan never swaps the text of a pending
    /// notification. Rotates through the pool day by day.
    static func pick<T>(_ pool: [T], date: LocalDate, salt: Int) -> T {
        let n = dayNumber(date) * 3 + salt
        return pool[((n % pool.count) + pool.count) % pool.count]
    }

    static func dayNumber(_ date: LocalDate) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        return Int(date.startOfDay(in: utc).timeIntervalSince1970 / 86400)
    }

    private static func at(_ minute: Int, on date: LocalDate, tz: TimeZone) -> Date {
        let noon = date.noon(in: tz)
        return Calendar.gregorian(tz).date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: noon) ?? noon
    }

    private static func nextTime(after prayer: Prayer, in schedule: DaySchedule) -> Date? {
        guard let i = Prayer.prayers.firstIndex(of: prayer), i + 1 < Prayer.prayers.count else { return nil }
        return schedule.time(Prayer.prayers[i + 1])
    }
}
