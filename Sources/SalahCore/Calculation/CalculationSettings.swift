import Adhan
import Foundation

/// Calculation methods exposed to users. All map to adhan-swift built-ins except `custom`.
public enum MethodID: String, CaseIterable, Codable, Sendable {
    case singapore
    case muslimWorldLeague
    case northAmerica
    case egyptian
    case ummAlQura
    case karachi
    case dubai
    case kuwait
    case qatar
    case moonsightingCommittee
    case turkey
    case tehran
    case custom

    public var displayName: String {
        switch self {
        case .singapore: return "Singapore (MUIS)"
        case .muslimWorldLeague: return "Muslim World League"
        case .northAmerica: return "North America (ISNA)"
        case .egyptian: return "Egyptian General Authority of Survey"
        case .ummAlQura: return "Umm al-Qura"
        case .karachi: return "Karachi"
        case .dubai: return "Dubai"
        case .kuwait: return "Kuwait"
        case .qatar: return "Qatar"
        case .moonsightingCommittee: return "Moonsighting Committee"
        case .turkey: return "Turkey"
        case .tehran: return "Tehran"
        case .custom: return "Custom"
        }
    }

    /// Short name for headers and the menu bar, e.g. "MUIS".
    public var shortName: String {
        switch self {
        case .singapore: return "MUIS"
        case .muslimWorldLeague: return "MWL"
        case .northAmerica: return "ISNA"
        case .egyptian: return "Egypt"
        case .ummAlQura: return "Umm al-Qura"
        case .karachi: return "Karachi"
        case .dubai: return "Dubai"
        case .kuwait: return "Kuwait"
        case .qatar: return "Qatar"
        case .moonsightingCommittee: return "MSC"
        case .turkey: return "Turkey"
        case .tehran: return "Tehran"
        case .custom: return "Custom"
        }
    }

    var adhanMethod: CalculationMethod {
        switch self {
        case .singapore: return .singapore
        case .muslimWorldLeague: return .muslimWorldLeague
        case .northAmerica: return .northAmerica
        case .egyptian: return .egyptian
        case .ummAlQura: return .ummAlQura
        case .karachi: return .karachi
        case .dubai: return .dubai
        case .kuwait: return .kuwait
        case .qatar: return .qatar
        case .moonsightingCommittee: return .moonsightingCommittee
        case .turkey: return .turkey
        case .tehran: return .tehran
        case .custom: return .other
        }
    }

    /// Default method for a location: MUIS in Singapore, Muslim World League elsewhere.
    public static func automatic(for location: SavedLocation?) -> MethodID {
        guard let location else { return .muslimWorldLeague }
        if location.timeZone == "Asia/Singapore" || location.countryCode?.uppercased() == "SG" {
            return .singapore
        }
        return .muslimWorldLeague
    }
}

public enum MadhabSetting: String, CaseIterable, Codable, Sendable {
    case shafi, hanafi

    public var displayName: String {
        switch self {
        case .shafi: return "Shafi'i, Maliki, Hanbali"
        case .hanafi: return "Hanafi"
        }
    }
}

public enum HighLatitudeSetting: String, CaseIterable, Codable, Sendable {
    case middleOfTheNight, seventhOfTheNight, twilightAngle

    public var displayName: String {
        switch self {
        case .middleOfTheNight: return "Middle of the night"
        case .seventhOfTheNight: return "Seventh of the night"
        case .twilightAngle: return "Twilight angle"
        }
    }
}

public struct CalculationSettings: Codable, Equatable, Sendable {
    /// `nil` means automatic: chosen from the location (see `MethodID.automatic`).
    public var method: MethodID?
    public var madhab: MadhabSetting
    /// `nil` means the library's recommendation for the latitude.
    public var highLatitudeRule: HighLatitudeSetting?
    public var customFajrAngle: Double
    public var customIshaAngle: Double
    /// Manual per-prayer offsets in minutes, keyed by `Prayer.rawValue`.
    public var offsets: [String: Int]

    public init(
        method: MethodID? = nil,
        madhab: MadhabSetting = .shafi,
        highLatitudeRule: HighLatitudeSetting? = nil,
        customFajrAngle: Double = 20,
        customIshaAngle: Double = 18,
        offsets: [String: Int] = [:]
    ) {
        self.method = method
        self.madhab = madhab
        self.highLatitudeRule = highLatitudeRule
        self.customFajrAngle = customFajrAngle
        self.customIshaAngle = customIshaAngle
        self.offsets = offsets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CalculationSettings()
        method = try c.decodeLenient(MethodID.self, forKey: .method)
        madhab = try c.decodeLenient(MadhabSetting.self, forKey: .madhab) ?? d.madhab
        highLatitudeRule = try c.decodeLenient(HighLatitudeSetting.self, forKey: .highLatitudeRule)
        customFajrAngle = try c.decodeIfPresent(Double.self, forKey: .customFajrAngle) ?? d.customFajrAngle
        customIshaAngle = try c.decodeIfPresent(Double.self, forKey: .customIshaAngle) ?? d.customIshaAngle
        offsets = try c.decodeIfPresent([String: Int].self, forKey: .offsets) ?? [:]
    }

    public func offset(for prayer: Prayer) -> Int { offsets[prayer.rawValue] ?? 0 }

    public mutating func setOffset(_ minutes: Int, for prayer: Prayer) {
        offsets[prayer.rawValue] = minutes == 0 ? nil : minutes
    }

    public func resolvedMethod(for location: SavedLocation?) -> MethodID {
        method ?? MethodID.automatic(for: location)
    }

    /// Human-readable method name, e.g. "Singapore (MUIS)" or "Custom (20° / 18°)".
    public func methodName(for location: SavedLocation?) -> String {
        let m = resolvedMethod(for: location)
        if m == .custom {
            return "Custom (\(Self.angle(customFajrAngle))° / \(Self.angle(customIshaAngle))°)"
        }
        return m.displayName
    }

    public func methodShortName(for location: SavedLocation?) -> String {
        resolvedMethod(for: location).shortName
    }

    static func angle(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(v)
    }

    func adhanParameters(for location: SavedLocation) -> CalculationParameters {
        let m = resolvedMethod(for: location)
        var params = m.adhanMethod.params
        if m == .custom {
            params.fajrAngle = customFajrAngle
            params.ishaAngle = customIshaAngle
            params.ishaInterval = 0
        }
        params.madhab = madhab == .hanafi ? .hanafi : .shafi
        switch highLatitudeRule {
        case .middleOfTheNight: params.highLatitudeRule = .middleOfTheNight
        case .seventhOfTheNight: params.highLatitudeRule = .seventhOfTheNight
        case .twilightAngle: params.highLatitudeRule = .twilightAngle
        case nil: params.highLatitudeRule = nil
        }
        params.adjustments = PrayerAdjustments(
            fajr: offset(for: .fajr),
            sunrise: offset(for: .sunrise),
            dhuhr: offset(for: .dhuhr),
            asr: offset(for: .asr),
            maghrib: offset(for: .maghrib),
            isha: offset(for: .isha)
        )
        return params
    }
}

extension KeyedDecodingContainer {
    /// Decodes an optional enum-like value, treating unknown raw values as absent instead of failing.
    func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try? decode(T.self, forKey: key)
    }
}
