import Foundation

/// The six daily times shown on the timeline. Sunrise is a time marker, not a prayer.
public enum Prayer: String, CaseIterable, Codable, Hashable, Sendable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    /// The five obligatory prayers, in order.
    public static let prayers: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    public var isPrayer: Bool { self != .sunrise }

    public var name: String {
        switch self {
        case .fajr: return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }

    /// Display label, relabelling Dhuhr as Jumu'ah on Fridays when enabled.
    public func label(isFriday: Bool, jumuahRelabel: Bool) -> String {
        if self == .dhuhr && isFriday && jumuahRelabel { return "Jumu'ah" }
        return name
    }

    /// Case-insensitive lookup that also accepts "jumuah"/"jumu'ah" for Dhuhr.
    public init?(name: String) {
        let key = name.lowercased().replacingOccurrences(of: "'", with: "")
        if key == "jumuah" || key == "jummah" { self = .dhuhr; return }
        guard let p = Prayer(rawValue: key) else { return nil }
        self = p
    }
}
