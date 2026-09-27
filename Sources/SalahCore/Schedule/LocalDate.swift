import Foundation

/// A calendar day in a specific location's time zone, independent of the machine's zone.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local calendar day containing `date` in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let c = Calendar.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Parses "YYYY-MM-DD".
    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        // Reject impossible dates like 2026-02-30.
        let cal = Calendar.gregorian(TimeZone(identifier: "UTC")!)
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d)),
              cal.component(.day, from: date) == d else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var components: DateComponents { DateComponents(year: year, month: month, day: day) }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Local midnight at the start of this day.
    public func startOfDay(in timeZone: TimeZone) -> Date {
        Calendar.gregorian(timeZone).date(from: components)!
    }

    /// Local noon; stable for weekday and Hijri lookups even on DST transition days.
    public func noon(in timeZone: TimeZone) -> Date {
        var c = components
        c.hour = 12
        return Calendar.gregorian(timeZone).date(from: c)!
    }

    public func adding(days: Int) -> LocalDate {
        let utc = TimeZone(identifier: "UTC")!
        let d = Calendar.gregorian(utc).date(byAdding: .day, value: days, to: noon(in: utc))!
        return LocalDate(d, in: utc)
    }

    /// 1 = Sunday ... 7 = Saturday.
    public var weekday: Int {
        let utc = TimeZone(identifier: "UTC")!
        return Calendar.gregorian(utc).component(.weekday, from: noon(in: utc))
    }

    public var isFriday: Bool { weekday == 6 }

    public var weekdayName: String { Self.weekdays[weekday - 1] }
    public var monthName: String { Self.months[month - 1] }

    /// Days in this date's month.
    public var daysInMonth: Int {
        let utc = TimeZone(identifier: "UTC")!
        return Calendar.gregorian(utc).range(of: .day, in: .month, for: noon(in: utc))!.count
    }

    public var firstOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1) }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let months = ["January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December"]
}

extension Calendar {
    static func gregorian(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
}
