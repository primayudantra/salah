import Foundation

/// Formatting shared by the app, menu bar, notifications and CLI so they read identically.
public enum TimeFormatting {
    /// "20:10" or "8:10 PM" in the given zone.
    public static func clock(_ date: Date, in tz: TimeZone, use24Hour: Bool, padHour: Bool = false) -> String {
        let p = parts(date, in: tz, use24Hour: use24Hour, padHour: padHour)
        return p.period.isEmpty ? p.time : "\(p.time) \(p.period)"
    }

    /// Splits a clock time into its digits and AM/PM marker, so views can style them separately.
    public static func parts(_ date: Date, in tz: TimeZone, use24Hour: Bool, padHour: Bool = false) -> (time: String, period: String) {
        let c = Calendar.gregorian(tz).dateComponents([.hour, .minute], from: date)
        let h = c.hour!, m = c.minute!
        if use24Hour { return (String(format: "%02d:%02d", h, m), "") }
        let h12 = h % 12 == 0 ? 12 : h % 12
        return (String(format: padHour ? "%02d:%02d" : "%d:%02d", h12, m), h < 12 ? "AM" : "PM")
    }

    /// "HH:MM:SS" with zero padding; negative values clamp to zero.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Compact form for menu bar and shell prompts: "42m", "1h 25m", "<1m". Truncates, matching the countdown.
    public static func short(_ seconds: TimeInterval) -> String {
        let m = Int(max(0, seconds) / 60)
        if m == 0 { return "<1m" }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Spoken form for VoiceOver: "1 hour 25 minutes".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let m = Int((max(0, seconds) / 60).rounded(.up))
        let h = m / 60, mm = m % 60
        var out: [String] = []
        if h > 0 { out.append("\(h) hour\(h == 1 ? "" : "s")") }
        if mm > 0 || h == 0 { out.append("\(mm) minute\(mm == 1 ? "" : "s")") }
        return out.joined(separator: " ")
    }

    /// ISO 8601 with the location's offset, e.g. "2026-09-27T20:10:00+08:00".
    public static func iso8601(_ date: Date, in tz: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = tz
        return f.string(from: date)
    }

    /// "SUNDAY, 27 SEPTEMBER 2026" style (callers upper-case as needed).
    public static func longDate(_ d: LocalDate, includeYear: Bool = true) -> String {
        "\(d.weekdayName), \(d.day) \(d.monthName)" + (includeYear ? " \(d.year)" : "")
    }

    /// "Fri, 25 Sep"
    public static func shortDate(_ d: LocalDate) -> String {
        "\(d.weekdayName.prefix(3)), \(d.day) \(d.monthName.prefix(3))"
    }
}
