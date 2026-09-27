import Foundation
import SalahCore

/// Stable JSON schema for `--json`. Documented in README.md; bump `schemaVersion` on breaking changes.
/// Optional fields are always present and encoded as `null` rather than omitted.
enum JSONOutput {
    static let schemaVersion = 1

    struct Location: Encodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let timeZone: String

        init(_ l: SavedLocation) {
            name = l.name
            latitude = l.latitude
            longitude = l.longitude
            timeZone = l.timeZone
        }
    }

    struct Method: Encodable {
        let id: String
        let name: String
        let automatic: Bool
        let madhab: String
        let highLatitudeRule: String
        let offsets: [String: Int]

        init(_ config: SalahConfig) {
            let c = config.calculation
            id = c.resolvedMethod(for: config.location).rawValue
            name = c.methodName(for: config.location)
            automatic = c.method == nil
            madhab = c.madhab.rawValue
            highLatitudeRule = c.highLatitudeRule?.rawValue ?? "auto"
            offsets = c.offsets
        }
    }

    struct Hijri: Encodable {
        let day: Int
        let month: Int
        let monthName: String
        let year: Int
        let adjustment: Int
        let formatted: String

        init(_ d: LocalDate, adjustment: Int) {
            let h = HijriDate(d, adjustment: adjustment)
            day = h.day
            month = h.month
            monthName = h.monthName
            year = h.year
            self.adjustment = adjustment
            formatted = h.formatted
        }
    }

    struct PrayerTime: Encodable {
        let prayer: String
        let label: String
        let isPrayer: Bool
        let time: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(prayer, forKey: .prayer)
            try c.encode(label, forKey: .label)
            try c.encode(isPrayer, forKey: .isPrayer)
            try c.encode(time, forKey: .time)
        }

        enum CodingKeys: String, CodingKey { case prayer, label, isPrayer, time }
    }

    struct Day: Encodable {
        let date: String
        let weekday: String
        let hijri: Hijri
        let prayers: [PrayerTime]
        let undefined: [String]

        init(_ s: DaySchedule, config: SalahConfig) {
            date = s.date.description
            weekday = s.date.weekdayName
            hijri = Hijri(s.date, adjustment: config.display.hijriAdjustment)
            prayers = Prayer.allCases.map { p in
                PrayerTime(
                    prayer: p.rawValue, label: s.label(p, jumuahRelabel: config.display.jumuahRelabel),
                    isPrayer: p.isPrayer, time: s.time(p).map { TimeFormatting.iso8601($0, in: s.timeZone) }
                )
            }
            undefined = s.undefined.map(\.rawValue)
        }
    }

    struct Next: Encodable {
        let prayer: String
        let label: String
        let time: String
        let isTomorrow: Bool
        let secondsRemaining: Int

        init(_ n: NextPrayer, now: Date, tz: TimeZone, jumuahRelabel: Bool) {
            prayer = n.prayer.rawValue
            label = n.label(jumuahRelabel: jumuahRelabel)
            time = TimeFormatting.iso8601(n.time, in: tz)
            isTomorrow = n.isTomorrow
            secondsRemaining = Int(n.secondsRemaining(from: now).rounded(.down))
        }
    }

    struct Now: Encodable {
        let prayer: String
        let label: String
        let time: String
        let secondsSince: Int
    }

    struct Today: Encodable {
        let schemaVersion = JSONOutput.schemaVersion
        let generatedAt: String
        let location: Location
        let method: Method
        let day: Day
        let next: Next?
        let now: Now?
        let currentPeriod: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(schemaVersion, forKey: .schemaVersion)
            try c.encode(generatedAt, forKey: .generatedAt)
            try c.encode(location, forKey: .location)
            try c.encode(method, forKey: .method)
            try c.encode(day, forKey: .day)
            try c.encode(next, forKey: .next)
            try c.encode(now, forKey: .now)
            try c.encode(currentPeriod, forKey: .currentPeriod)
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, generatedAt, location, method, day, next, now, currentPeriod }
    }

    struct NextOnly: Encodable {
        let schemaVersion = JSONOutput.schemaVersion
        let generatedAt: String
        let location: Location
        let method: Method
        let next: Next?
        let now: Now?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(schemaVersion, forKey: .schemaVersion)
            try c.encode(generatedAt, forKey: .generatedAt)
            try c.encode(location, forKey: .location)
            try c.encode(method, forKey: .method)
            try c.encode(next, forKey: .next)
            try c.encode(now, forKey: .now)
        }

        enum CodingKeys: String, CodingKey { case schemaVersion, generatedAt, location, method, next, now }
    }

    struct Schedule: Encodable {
        let schemaVersion = JSONOutput.schemaVersion
        let generatedAt: String
        let location: Location
        let method: Method
        let days: [Day]

        enum CodingKeys: String, CodingKey { case schemaVersion, generatedAt, location, method, days }
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try e.encode(value), as: UTF8.self) + "\n"
    }

    static func now(_ state: PrayerClockState, config: SalahConfig) -> Now? {
        guard let p = state.nowPrayer, let t = state.today.time(p), let loc = config.location else { return nil }
        return Now(
            prayer: p.rawValue, label: state.today.label(p, jumuahRelabel: config.display.jumuahRelabel),
            time: TimeFormatting.iso8601(t, in: loc.tz), secondsSince: Int(state.secondsSinceNow ?? 0)
        )
    }
}
