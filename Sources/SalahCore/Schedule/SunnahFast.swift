import Foundation

/// A recommended (sunnah) fast on a given day, shown on the Schedule. Ramadan and the days on
/// which fasting is not allowed (the two Eids and the days of Tashriq) never get one.
public enum SunnahFast: String, Equatable, Sendable {
    case mondayThursday, whiteDays, arafah, ashura

    /// The day's special name, or nil for a plain Monday or Thursday.
    public var name: String? {
        switch self {
        case .mondayThursday: return nil
        case .whiteDays: return "White day"
        case .arafah: return "Arafah"
        case .ashura: return "Ashura"
        }
    }

    /// Why, with its source, for the tooltip.
    public var reason: String {
        switch self {
        case .mondayThursday:
            return "“Deeds are presented on Monday and Thursday, and I love that my deeds are presented while I am fasting.” — At-Tirmidhi 747"
        case .whiteDays:
            return "The White Days, the 13th, 14th and 15th of each Hijri month. — An-Nasa’i 2420"
        case .arafah:
            return "Fasting the Day of Arafah expiates the sins of the past year and the coming year. — Muslim 1162"
        case .ashura:
            return "Fasting Ashura expiates the sins of the past year; fast the 9th with it. — Muslim 1162, 1134"
        }
    }

    /// Every reason to fast this date, most notable first; empty when there's none. Uses the same
    /// Hijri adjustment as the rest of the app, so it follows local moon sighting.
    public static func reasons(on date: LocalDate, hijriAdjustment: Int = 0) -> [SunnahFast] {
        let h = HijriDate(date, adjustment: hijriAdjustment)
        // Ramadan is obligatory, not sunnah.
        if h.month == 9 { return [] }
        // No fasting on Eid al-Fitr, Eid al-Adha or the days of Tashriq.
        if h.month == 10 && h.day == 1 { return [] }
        if h.month == 12 && (10...13).contains(h.day) { return [] }

        var out: [SunnahFast] = []
        if h.month == 12 && h.day == 9 { out.append(.arafah) }
        if h.month == 1 && (h.day == 9 || h.day == 10) { out.append(.ashura) }
        if (13...15).contains(h.day) { out.append(.whiteDays) }
        // weekday: 1 = Sunday … 7 = Saturday.
        if date.weekday == 2 || date.weekday == 5 { out.append(.mondayThursday) }
        return out
    }

    /// The Schedule tag: "Sunnah fast", plus the day's names, e.g. "Sunnah fast · White day".
    public static func tag(_ reasons: [SunnahFast]) -> String? {
        guard !reasons.isEmpty else { return nil }
        return (["Sunnah fast"] + reasons.compactMap(\.name)).joined(separator: " · ")
    }
}
