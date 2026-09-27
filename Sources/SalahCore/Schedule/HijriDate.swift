import Foundation

/// Hijri date via the Umm al-Qura calendar, with a manual ±2 day adjustment for local moon sighting.
/// The Hijri day is taken at local noon; it does not roll over at Maghrib.
public struct HijriDate: Equatable, Sendable {
    public let day: Int
    public let month: Int
    public let year: Int

    public static let monthNames = [
        "Muharram", "Safar", "Rabi' al-Awwal", "Rabi' al-Thani", "Jumada al-Ula", "Jumada al-Akhirah",
        "Rajab", "Sha'ban", "Ramadan", "Shawwal", "Dhu al-Qa'dah", "Dhu al-Hijjah",
    ]

    public init(day: Int, month: Int, year: Int) {
        self.day = day
        self.month = month
        self.year = year
    }

    public init(_ date: LocalDate, adjustment: Int = 0) {
        let utc = TimeZone(identifier: "UTC")!
        let shifted = date.adding(days: min(2, max(-2, adjustment))).noon(in: utc)
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = utc
        let c = cal.dateComponents([.year, .month, .day], from: shifted)
        self.init(day: c.day!, month: c.month!, year: c.year!)
    }

    public var monthName: String { Self.monthNames[month - 1] }

    /// e.g. "12 Rabi' al-Awwal 1448"
    public var formatted: String { "\(day) \(monthName) \(year)" }
}
