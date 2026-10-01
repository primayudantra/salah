import Foundation

public enum ThemeSetting: String, CaseIterable, Codable, Sendable {
    case system, light, dark
}

public enum MenuBarStyle: String, CaseIterable, Codable, Sendable {
    /// "☾ Asr · 12m"
    case nameAndCountdown
    /// "☾ 4:05 PM"
    case timeOnly
    case iconOnly

    public var displayName: String {
        switch self {
        case .nameAndCountdown: return "Name and countdown"
        case .timeOnly: return "Time only"
        case .iconOnly: return "Icon only"
        }
    }
}

public struct DisplaySettings: Codable, Equatable, Sendable {
    public var use24HourClock: Bool
    public var theme: ThemeSetting
    public var jumuahRelabel: Bool
    /// Manual Hijri adjustment for local moon sighting, clamped to -2...2.
    public var hijriAdjustment: Int
    /// How long the display shows NOW after a prayer starts, 0...60 minutes.
    public var nowWindowMinutes: Int
    public var showMenuBarExtra: Bool
    public var menuBarStyle: MenuBarStyle

    public init(
        use24HourClock: Bool = true, theme: ThemeSetting = .system, jumuahRelabel: Bool = true,
        hijriAdjustment: Int = 0, nowWindowMinutes: Int = 15, showMenuBarExtra: Bool = true,
        menuBarStyle: MenuBarStyle = .nameAndCountdown
    ) {
        self.use24HourClock = use24HourClock
        self.theme = theme
        self.jumuahRelabel = jumuahRelabel
        self.hijriAdjustment = hijriAdjustment
        self.nowWindowMinutes = nowWindowMinutes
        self.showMenuBarExtra = showMenuBarExtra
        self.menuBarStyle = menuBarStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisplaySettings()
        use24HourClock = try c.decodeIfPresent(Bool.self, forKey: .use24HourClock) ?? d.use24HourClock
        theme = try c.decodeLenient(ThemeSetting.self, forKey: .theme) ?? d.theme
        jumuahRelabel = try c.decodeIfPresent(Bool.self, forKey: .jumuahRelabel) ?? d.jumuahRelabel
        hijriAdjustment = min(2, max(-2, try c.decodeIfPresent(Int.self, forKey: .hijriAdjustment) ?? 0))
        nowWindowMinutes = min(60, max(0, try c.decodeIfPresent(Int.self, forKey: .nowWindowMinutes) ?? d.nowWindowMinutes))
        showMenuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? d.showMenuBarExtra
        menuBarStyle = try c.decodeLenient(MenuBarStyle.self, forKey: .menuBarStyle) ?? d.menuBarStyle
    }
}

public enum ReminderSound: String, CaseIterable, Codable, Sendable {
    case systemDefault, chime, silent

    public var displayName: String {
        switch self {
        case .systemDefault: return "System default"
        case .chime: return "Soft chime"
        case .silent: return "Silent"
        }
    }
}

public struct PrayerReminder: Codable, Equatable, Sendable {
    public static let allowedLeads = [0, 5, 10, 15, 30]

    public var enabled: Bool
    /// Minutes before the prayer for the early reminder; 0 means no early reminder.
    public var leadMinutes: Int
    /// Also notify at the prayer time itself.
    public var atTime: Bool

    public init(enabled: Bool = true, leadMinutes: Int = 10, atTime: Bool = true) {
        self.enabled = enabled
        self.leadMinutes = leadMinutes
        self.atTime = atTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let lead = try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? 10
        leadMinutes = Self.allowedLeads.contains(lead) ? lead : 10
        atTime = try c.decodeIfPresent(Bool.self, forKey: .atTime) ?? true
    }

    /// Lead times this reminder fires at, largest first; 0 is "at prayer time".
    public var leads: [Int] {
        var out: [Int] = []
        if leadMinutes > 0 { out.append(leadMinutes) }
        if atTime { out.append(0) }
        return out
    }
}

/// Minutes-since-midnight window, e.g. 23:00–04:30. May wrap past midnight.
public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var start: String
    public var end: String

    public init(enabled: Bool = false, start: String = "23:00", end: String = "04:30") {
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let s = try c.decodeIfPresent(String.self, forKey: .start) ?? "23:00"
        let e = try c.decodeIfPresent(String.self, forKey: .end) ?? "04:30"
        start = Self.minutes(s) == nil ? "23:00" : s
        end = Self.minutes(e) == nil ? "04:30" : e
    }

    public static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// True when the minute-of-day falls in [start, end), wrapping past midnight.
    public func contains(minuteOfDay m: Int) -> Bool {
        guard enabled, let s = Self.minutes(start), let e = Self.minutes(end), s != e else { return false }
        return s < e ? (m >= s && m < e) : (m >= s || m < e)
    }
}

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var pausedUntil: Date?
    public var sound: ReminderSound
    public var quietHours: QuietHours
    /// Keyed by `Prayer.rawValue` for the five prayers.
    public var prayers: [String: PrayerReminder]

    public static let defaultPrayers: [String: PrayerReminder] = [
        "fajr": PrayerReminder(leadMinutes: 15),
        "dhuhr": PrayerReminder(leadMinutes: 10),
        "asr": PrayerReminder(leadMinutes: 10),
        "maghrib": PrayerReminder(leadMinutes: 5),
        "isha": PrayerReminder(leadMinutes: 10),
    ]

    public init(
        enabled: Bool = true, pausedUntil: Date? = nil, sound: ReminderSound = .systemDefault,
        quietHours: QuietHours = QuietHours(), prayers: [String: PrayerReminder] = ReminderSettings.defaultPrayers
    ) {
        self.enabled = enabled
        self.pausedUntil = pausedUntil
        self.sound = sound
        self.quietHours = quietHours
        self.prayers = prayers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pausedUntil = try? c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        sound = try c.decodeLenient(ReminderSound.self, forKey: .sound) ?? .systemDefault
        quietHours = try c.decodeIfPresent(QuietHours.self, forKey: .quietHours) ?? QuietHours()
        var p = Self.defaultPrayers
        for (k, v) in try c.decodeIfPresent([String: PrayerReminder].self, forKey: .prayers) ?? [:]
        where Prayer(rawValue: k)?.isPrayer == true {
            p[k] = v
        }
        prayers = p
    }

    public func reminder(for prayer: Prayer) -> PrayerReminder {
        prayers[prayer.rawValue] ?? PrayerReminder(enabled: false)
    }

    public mutating func update(_ prayer: Prayer, _ body: (inout PrayerReminder) -> Void) {
        var r = reminder(for: prayer)
        body(&r)
        prayers[prayer.rawValue] = r
    }

    public func isPaused(at now: Date) -> Bool {
        if let pausedUntil { return pausedUntil > now }
        return false
    }
}

/// The single shared configuration, read and written by both the app and the CLI.
public struct SalahConfig: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var location: SavedLocation?
    public var calculation: CalculationSettings
    public var display: DisplaySettings
    public var reminders: ReminderSettings
    public var prayerMode: PrayerModeSettings
    public var launchAtLogin: Bool

    public init(
        location: SavedLocation? = nil, calculation: CalculationSettings = CalculationSettings(),
        display: DisplaySettings = DisplaySettings(), reminders: ReminderSettings = ReminderSettings(),
        prayerMode: PrayerModeSettings = PrayerModeSettings(), launchAtLogin: Bool = true
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.location = location
        self.calculation = calculation
        self.display = display
        self.reminders = reminders
        self.prayerMode = prayerMode
        self.launchAtLogin = launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        location = try c.decodeIfPresent(SavedLocation.self, forKey: .location)
        calculation = try c.decodeIfPresent(CalculationSettings.self, forKey: .calculation) ?? CalculationSettings()
        display = try c.decodeIfPresent(DisplaySettings.self, forKey: .display) ?? DisplaySettings()
        reminders = try c.decodeIfPresent(ReminderSettings.self, forKey: .reminders) ?? ReminderSettings()
        prayerMode = try c.decodeIfPresent(PrayerModeSettings.self, forKey: .prayerMode) ?? PrayerModeSettings()
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
    }

    public static let `default` = SalahConfig()

    public var methodName: String { calculation.methodName(for: location) }
}
