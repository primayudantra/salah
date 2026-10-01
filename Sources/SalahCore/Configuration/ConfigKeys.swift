import Foundation

public enum ConfigKeyError: Error, LocalizedError, Equatable {
    case unknownKey(String)
    case readOnly(String)
    case invalidValue(key: String, value: String, expected: String)

    public var errorDescription: String? {
        switch self {
        case .unknownKey(let k): return "Unknown config key “\(k)”. Run `salah config get` to list keys."
        case .readOnly(let k): return "“\(k)” is read-only here. Use `salah location set` to change the location."
        case .invalidValue(let k, let v, let e): return "Invalid value “\(v)” for \(k). Expected \(e)."
        }
    }
}

/// Dotted-path access to config values for `salah config get/set`.
public struct ConfigKey: Sendable {
    public let key: String
    public let expected: String
    let getter: @Sendable (SalahConfig) -> String
    let setter: (@Sendable (inout SalahConfig, String) throws -> Void)?

    public var isReadOnly: Bool { setter == nil }

    public func get(_ c: SalahConfig) -> String { getter(c) }

    public func set(_ c: inout SalahConfig, _ value: String) throws {
        guard let setter else { throw ConfigKeyError.readOnly(key) }
        try setter(&c, value)
    }
}

public enum ConfigKeys {
    public static func find(_ key: String) throws -> ConfigKey {
        guard let k = all.first(where: { $0.key == key }) else { throw ConfigKeyError.unknownKey(key) }
        return k
    }

    public static let all: [ConfigKey] = {
        var keys: [ConfigKey] = [
            readOnly("location.name") { $0.location?.name ?? "" },
            readOnly("location.latitude") { $0.location.map { String($0.latitude) } ?? "" },
            readOnly("location.longitude") { $0.location.map { String($0.longitude) } ?? "" },
            ConfigKey(
                key: "location.timeZone", expected: "an IANA time zone, e.g. Asia/Singapore",
                getter: { $0.location?.timeZone ?? "" },
                setter: { c, v in
                    guard TimeZone(identifier: v) != nil else {
                        throw ConfigKeyError.invalidValue(key: "location.timeZone", value: v, expected: "an IANA time zone, e.g. Asia/Singapore")
                    }
                    guard c.location != nil else { throw ConfigKeyError.readOnly("location.timeZone") }
                    c.location?.timeZone = v
                }
            ),
            enumKey("calculation.method", ["auto"] + MethodID.allCases.map(\.rawValue),
                    get: { $0.calculation.method?.rawValue ?? "auto" },
                    set: { c, v in c.calculation.method = v == "auto" ? nil : MethodID(rawValue: v) }),
            enumKey("calculation.madhab", MadhabSetting.allCases.map(\.rawValue),
                    get: { $0.calculation.madhab.rawValue },
                    set: { c, v in c.calculation.madhab = MadhabSetting(rawValue: v)! }),
            enumKey("calculation.highLatitudeRule", ["auto"] + HighLatitudeSetting.allCases.map(\.rawValue),
                    get: { $0.calculation.highLatitudeRule?.rawValue ?? "auto" },
                    set: { c, v in c.calculation.highLatitudeRule = v == "auto" ? nil : HighLatitudeSetting(rawValue: v) }),
            doubleKey("calculation.customFajrAngle", 0...30, get: { $0.calculation.customFajrAngle }, set: { $0.calculation.customFajrAngle = $1 }),
            doubleKey("calculation.customIshaAngle", 0...30, get: { $0.calculation.customIshaAngle }, set: { $0.calculation.customIshaAngle = $1 }),
        ]
        for p in Prayer.allCases {
            keys.append(intKey("calculation.offsets.\(p.rawValue)", -60...60,
                               get: { $0.calculation.offset(for: p) },
                               set: { $0.calculation.setOffset($1, for: p) }))
        }
        keys += [
            enumKey("display.clock", ["12", "24"],
                    get: { $0.display.use24HourClock ? "24" : "12" },
                    set: { c, v in c.display.use24HourClock = v == "24" }),
            enumKey("display.theme", ThemeSetting.allCases.map(\.rawValue),
                    get: { $0.display.theme.rawValue },
                    set: { c, v in c.display.theme = ThemeSetting(rawValue: v)! }),
            enumKey("display.accentTheme", AccentTheme.allCases.map(\.rawValue),
                    get: { $0.display.accentTheme.rawValue },
                    set: { c, v in c.display.accentTheme = AccentTheme(rawValue: v)! }),
            boolKey("display.jumuahRelabel", get: { $0.display.jumuahRelabel }, set: { $0.display.jumuahRelabel = $1 }),
            intKey("display.hijriAdjustment", -2...2, get: { $0.display.hijriAdjustment }, set: { $0.display.hijriAdjustment = $1 }),
            intKey("display.nowWindowMinutes", 0...60, get: { $0.display.nowWindowMinutes }, set: { $0.display.nowWindowMinutes = $1 }),
            boolKey("display.showMenuBarExtra", get: { $0.display.showMenuBarExtra }, set: { $0.display.showMenuBarExtra = $1 }),
            enumKey("display.menuBarStyle", MenuBarStyle.allCases.map(\.rawValue),
                    get: { $0.display.menuBarStyle.rawValue },
                    set: { c, v in c.display.menuBarStyle = MenuBarStyle(rawValue: v)! }),
            boolKey("reminders.enabled", get: { $0.reminders.enabled }, set: { $0.reminders.enabled = $1 }),
            ConfigKey(
                key: "reminders.pausedUntil", expected: "an ISO 8601 date-time, or “none”",
                getter: { c in c.reminders.pausedUntil.map { ISO8601DateFormatter().string(from: $0) } ?? "none" },
                setter: { c, v in
                    if v == "none" || v.isEmpty { c.reminders.pausedUntil = nil; return }
                    guard let d = ISO8601DateFormatter().date(from: v) else {
                        throw ConfigKeyError.invalidValue(key: "reminders.pausedUntil", value: v, expected: "an ISO 8601 date-time, or “none”")
                    }
                    c.reminders.pausedUntil = d
                }
            ),
            enumKey("reminders.sound", ReminderSound.allCases.map(\.rawValue),
                    get: { $0.reminders.sound.rawValue },
                    set: { c, v in c.reminders.sound = ReminderSound(rawValue: v)! }),
            boolKey("reminders.quietHours.enabled", get: { $0.reminders.quietHours.enabled }, set: { $0.reminders.quietHours.enabled = $1 }),
            timeKey("reminders.quietHours.start", get: { $0.reminders.quietHours.start }, set: { $0.reminders.quietHours.start = $1 }),
            timeKey("reminders.quietHours.end", get: { $0.reminders.quietHours.end }, set: { $0.reminders.quietHours.end = $1 }),
        ]
        for p in Prayer.prayers {
            let base = "reminders.\(p.rawValue)"
            keys += [
                boolKey("\(base).enabled", get: { $0.reminders.reminder(for: p).enabled },
                        set: { c, v in c.reminders.update(p) { $0.enabled = v } }),
                enumKey("\(base).leadMinutes", PrayerReminder.allowedLeads.map(String.init),
                        get: { String($0.reminders.reminder(for: p).leadMinutes) },
                        set: { c, v in c.reminders.update(p) { $0.leadMinutes = Int(v)! } }),
                boolKey("\(base).atTime", get: { $0.reminders.reminder(for: p).atTime },
                        set: { c, v in c.reminders.update(p) { $0.atTime = v } }),
            ]
        }
        keys += [
            boolKey("focusMode.enabled", get: { $0.focusMode.enabled }, set: { $0.focusMode.enabled = $1 }),
            ConfigKey(
                key: "focusMode.prayers", expected: "comma-separated: dhuhr,asr,maghrib,isha (fajr allowed too)",
                getter: { c in Prayer.prayers.filter { c.focusMode.prayers.contains($0) }.map(\.rawValue).joined(separator: ",") },
                setter: { c, v in
                    let names = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    var set = Set<Prayer>()
                    for n in names {
                        guard let p = Prayer(name: n), p.isPrayer else {
                            throw ConfigKeyError.invalidValue(key: "focusMode.prayers", value: v, expected: "comma-separated: dhuhr,asr,maghrib,isha (fajr allowed too)")
                        }
                        set.insert(p)
                    }
                    c.focusMode.prayers = set
                }
            ),
            boolKey("focusMode.card.enabled", get: { $0.focusMode.card.enabled }, set: { $0.focusMode.card.enabled = $1 }),
            enumKey("focusMode.card.autoCloseMinutes", FocusModeCardSettings.allowedAutoCloseMinutes.map(String.init),
                    get: { String($0.focusMode.card.autoCloseMinutes) },
                    set: { c, v in c.focusMode.card.autoCloseMinutes = Int(v)! }),
            boolKey("focusMode.pauseMedia.enabled", get: { $0.focusMode.pauseMedia.enabled }, set: { $0.focusMode.pauseMedia.enabled = $1 }),
            boolKey("focusMode.pauseMedia.resumeOnDone", get: { $0.focusMode.pauseMedia.resumeOnDone }, set: { $0.focusMode.pauseMedia.resumeOnDone = $1 }),
            boolKey("focusMode.focus.enabled", get: { $0.focusMode.focus.enabled }, set: { $0.focusMode.focus.enabled = $1 }),
            boolKey("focusMode.focus.turnOffOnDone", get: { $0.focusMode.focus.turnOffOnDone }, set: { $0.focusMode.focus.turnOffOnDone = $1 }),
            enumKey("focusMode.whenBusy.onCall", CallBusyMode.allCases.map(\.rawValue),
                    get: { $0.focusMode.whenBusy.onCall.rawValue },
                    set: { c, v in c.focusMode.whenBusy.onCall = CallBusyMode(rawValue: v)! }),
            boolKey("focusMode.whenBusy.focusIsBusy", get: { $0.focusMode.whenBusy.focusIsBusy }, set: { $0.focusMode.whenBusy.focusIsBusy = $1 }),
        ]
        keys.append(boolKey("launchAtLogin", get: { $0.launchAtLogin }, set: { $0.launchAtLogin = $1 }))
        return keys
    }()

    // MARK: - Builders

    static func readOnly(_ key: String, _ get: @escaping @Sendable (SalahConfig) -> String) -> ConfigKey {
        ConfigKey(key: key, expected: "", getter: get, setter: nil)
    }

    static func enumKey(
        _ key: String, _ values: [String],
        get: @escaping @Sendable (SalahConfig) -> String,
        set: @escaping @Sendable (inout SalahConfig, String) -> Void
    ) -> ConfigKey {
        let expected = "one of: " + values.joined(separator: ", ")
        return ConfigKey(key: key, expected: expected, getter: get) { c, v in
            guard values.contains(v) else { throw ConfigKeyError.invalidValue(key: key, value: v, expected: expected) }
            set(&c, v)
        }
    }

    static func boolKey(
        _ key: String, get: @escaping @Sendable (SalahConfig) -> Bool, set: @escaping @Sendable (inout SalahConfig, Bool) -> Void
    ) -> ConfigKey {
        let expected = "true or false"
        return ConfigKey(key: key, expected: expected, getter: { String(get($0)) }) { c, v in
            switch v.lowercased() {
            case "true", "on", "yes", "1": set(&c, true)
            case "false", "off", "no", "0": set(&c, false)
            default: throw ConfigKeyError.invalidValue(key: key, value: v, expected: expected)
            }
        }
    }

    static func intKey(
        _ key: String, _ range: ClosedRange<Int>,
        get: @escaping @Sendable (SalahConfig) -> Int, set: @escaping @Sendable (inout SalahConfig, Int) -> Void
    ) -> ConfigKey {
        let expected = "a whole number from \(range.lowerBound) to \(range.upperBound)"
        return ConfigKey(key: key, expected: expected, getter: { String(get($0)) }) { c, v in
            guard let n = Int(v), range.contains(n) else { throw ConfigKeyError.invalidValue(key: key, value: v, expected: expected) }
            set(&c, n)
        }
    }

    static func doubleKey(
        _ key: String, _ range: ClosedRange<Double>,
        get: @escaping @Sendable (SalahConfig) -> Double, set: @escaping @Sendable (inout SalahConfig, Double) -> Void
    ) -> ConfigKey {
        let expected = "a number from \(Int(range.lowerBound)) to \(Int(range.upperBound))"
        return ConfigKey(key: key, expected: expected, getter: { String(get($0)) }) { c, v in
            guard let n = Double(v), range.contains(n) else { throw ConfigKeyError.invalidValue(key: key, value: v, expected: expected) }
            set(&c, n)
        }
    }

    static func timeKey(
        _ key: String, get: @escaping @Sendable (SalahConfig) -> String, set: @escaping @Sendable (inout SalahConfig, String) -> Void
    ) -> ConfigKey {
        let expected = "a 24-hour time HH:MM"
        return ConfigKey(key: key, expected: expected, getter: get) { c, v in
            guard let m = QuietHours.minutes(v) else { throw ConfigKeyError.invalidValue(key: key, value: v, expected: expected) }
            set(&c, String(format: "%02d:%02d", m / 60, m % 60))
        }
    }
}
