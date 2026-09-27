import Adhan
import Foundation

/// One day's times for a location. A missing entry means the library could not
/// produce that time (e.g. polar day or night); it is never filled with a guess.
public struct DaySchedule: Equatable, Sendable {
    public let date: LocalDate
    public let timeZone: TimeZone
    public let times: [Prayer: Date]
    public let methodName: String

    public init(date: LocalDate, timeZone: TimeZone, times: [Prayer: Date], methodName: String) {
        self.date = date
        self.timeZone = timeZone
        self.times = times
        self.methodName = methodName
    }

    public func time(_ prayer: Prayer) -> Date? { times[prayer] }

    public var isFriday: Bool { date.isFriday }

    /// Prayers (and sunrise) the library could not calculate for this date.
    public var undefined: [Prayer] { Prayer.allCases.filter { times[$0] == nil } }

    public var hasUndefined: Bool { !undefined.isEmpty }

    /// Why times are missing, and what the user can do. Nil when every time is defined.
    public var undefinedExplanation: (reason: String, suggestion: String?)? {
        guard hasUndefined else { return nil }
        if times.isEmpty {
            return ("The sun doesn't rise or set here on this date, so prayer times can't be calculated. Salah never invents a time.",
                    "Follow a nearby city or your local authority's timetable for these days.")
        }
        let names = undefined.map(\.name).joined(separator: " and ")
        return ("\(names) can't be calculated here on this date.",
                "Choose a high-latitude rule in Settings.")
    }

    public func label(_ prayer: Prayer, jumuahRelabel: Bool) -> String {
        prayer.label(isFriday: isFriday, jumuahRelabel: jumuahRelabel)
    }
}

public enum PrayerSchedule {
    /// Computes the schedule for a local date. Always per date, so DST changes are handled by construction.
    public static func `for`(date: LocalDate, location: SavedLocation, settings: CalculationSettings) -> DaySchedule {
        let params = settings.adhanParameters(for: location)
        let coords = Coordinates(latitude: location.latitude, longitude: location.longitude)
        var times: [Prayer: Date] = [:]
        if let pt = PrayerTimes(coordinates: coords, date: date.components, calculationParameters: params) {
            times = [
                .fajr: pt.fajr, .sunrise: pt.sunrise, .dhuhr: pt.dhuhr,
                .asr: pt.asr, .maghrib: pt.maghrib, .isha: pt.isha,
            ]
        }
        return DaySchedule(
            date: date, timeZone: location.tz, times: times,
            methodName: settings.methodName(for: location)
        )
    }

    /// Consecutive days starting at `start`.
    public static func range(from start: LocalDate, days: Int, location: SavedLocation, settings: CalculationSettings) -> [DaySchedule] {
        (0..<max(0, days)).map { PrayerSchedule.for(date: start.adding(days: $0), location: location, settings: settings) }
    }

    /// Every day of the month containing `date`.
    public static func month(containing date: LocalDate, location: SavedLocation, settings: CalculationSettings) -> [DaySchedule] {
        range(from: date.firstOfMonth, days: date.daysInMonth, location: location, settings: settings)
    }
}
