import Foundation

/// A card on the Home screen's right-hand column.
public enum HomeWidget: String, CaseIterable, Codable, Sendable {
    /// Countdown to the next prayer; on Friday after Asr, the last hour before Maghrib.
    case nextPrayer
    case prayerTimes
    case duaOfTheDay
    /// What's playing, or a surah suggested for the moment (Al-Kahf on Friday, Al-Mulk at night).
    case quran
    /// Today's or tomorrow's sunnah fast; hidden when there's none.
    case sunnahFast
    case kindWord
    /// How Kind Words decides when to send.
    case kindWordsSchedule

    public var displayName: String {
        switch self {
        case .nextPrayer: return "Next prayer"
        case .prayerTimes: return "Prayer times"
        case .duaOfTheDay: return "Du'a of the day"
        case .quran: return "Quran"
        case .sunnahFast: return "Sunnah fasting"
        case .kindWord: return "Kind word of the day"
        case .kindWordsSchedule: return "Kind Words schedule"
        }
    }
}

/// The Home screen's widgets, in order. Users turn them on and off and reorder them.
public struct HomeSettings: Codable, Equatable, Sendable {
    public static let defaultWidgets: [HomeWidget] = [.nextPrayer, .prayerTimes, .duaOfTheDay, .quran, .sunnahFast]

    public var widgets: [HomeWidget]

    public init(widgets: [HomeWidget] = HomeSettings.defaultWidgets) {
        self.widgets = widgets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown names are dropped and duplicates kept once, so a newer or hand-edited file still loads.
        let raw = (try? c.decodeIfPresent([String].self, forKey: .widgets)) ?? nil
        guard let raw else { widgets = Self.defaultWidgets; return }
        var seen = Set<HomeWidget>()
        widgets = raw.compactMap(HomeWidget.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    public func isOn(_ w: HomeWidget) -> Bool { widgets.contains(w) }

    public mutating func set(_ w: HomeWidget, on: Bool) {
        if on { if !widgets.contains(w) { widgets.append(w) } } else { widgets.removeAll { $0 == w } }
    }

    /// Moves a shown widget up (-1) or down (+1).
    public mutating func move(_ w: HomeWidget, by offset: Int) {
        guard let i = widgets.firstIndex(of: w) else { return }
        let j = i + offset
        guard widgets.indices.contains(j) else { return }
        widgets.swapAt(i, j)
    }
}
