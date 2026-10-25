import Foundation

public enum KindWordsCadence: String, CaseIterable, Codable, Sendable {
    /// 09:00, 13:00, 17:00, 21:00.
    case everyFourHours
    /// 10:30, 15:30, 20:30.
    case peakMoments
    /// No daytime kind words; prayer and Friday reminders still follow their own switches.
    case off

    public var displayName: String {
        switch self {
        case .everyFourHours: return "Every 4 hours"
        case .peakMoments: return "Peak moments only"
        case .off: return "Off"
        }
    }

    /// Local times of day, as minutes since midnight.
    public var slots: [Int] {
        switch self {
        case .everyFourHours: return [9 * 60, 13 * 60, 17 * 60, 21 * 60]
        case .peakMoments: return [10 * 60 + 30, 15 * 60 + 30, 20 * 60 + 30]
        case .off: return []
        }
    }
}

/// Kind Words settings (roadmap/kind-words.md). Off by default: it adds notifications, so the
/// user turns it on.
public struct KindWordsSettings: Codable, Equatable, Sendable {
    public static let allowedAfterPrayerMinutes = [20, 30, 45, 60]

    public var enabled: Bool
    public var cadence: KindWordsCadence
    /// Adds a verse or hadith to the early prayer reminder.
    public var beforePrayer: Bool
    /// "Have you prayed?" after each prayer.
    public var afterPrayer: Bool
    public var afterPrayerMinutes: Int
    /// Al-Kahf in the morning and the last hour after Asr.
    public var friday: Bool
    /// A du'a at the start and end of the work day, Monday to Friday.
    public var workDuas: Bool
    public var workStart: String
    public var workEnd: String
    /// Kind words arrive without sound, whatever the prayer reminder sound is.
    public var silent: Bool

    public init(
        enabled: Bool = false, cadence: KindWordsCadence = .everyFourHours, beforePrayer: Bool = true,
        afterPrayer: Bool = true, afterPrayerMinutes: Int = 30, friday: Bool = true,
        workDuas: Bool = false, workStart: String = "09:00", workEnd: String = "17:00", silent: Bool = true
    ) {
        self.enabled = enabled
        self.cadence = cadence
        self.beforePrayer = beforePrayer
        self.afterPrayer = afterPrayer
        self.afterPrayerMinutes = afterPrayerMinutes
        self.friday = friday
        self.workDuas = workDuas
        self.workStart = workStart
        self.workEnd = workEnd
        self.silent = silent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KindWordsSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        cadence = try c.decodeLenient(KindWordsCadence.self, forKey: .cadence) ?? d.cadence
        beforePrayer = try c.decodeIfPresent(Bool.self, forKey: .beforePrayer) ?? d.beforePrayer
        afterPrayer = try c.decodeIfPresent(Bool.self, forKey: .afterPrayer) ?? d.afterPrayer
        let after = try c.decodeIfPresent(Int.self, forKey: .afterPrayerMinutes) ?? d.afterPrayerMinutes
        afterPrayerMinutes = Self.allowedAfterPrayerMinutes.contains(after) ? after : d.afterPrayerMinutes
        friday = try c.decodeIfPresent(Bool.self, forKey: .friday) ?? d.friday
        workDuas = try c.decodeIfPresent(Bool.self, forKey: .workDuas) ?? d.workDuas
        let start = try c.decodeIfPresent(String.self, forKey: .workStart) ?? d.workStart
        let end = try c.decodeIfPresent(String.self, forKey: .workEnd) ?? d.workEnd
        workStart = QuietHours.minutes(start) == nil ? d.workStart : start
        workEnd = QuietHours.minutes(end) == nil ? d.workEnd : end
        silent = try c.decodeIfPresent(Bool.self, forKey: .silent) ?? d.silent
    }
}
