import Foundation

/// Plain-text, CSV and iCalendar renderings of a schedule, shared by the app's export and copy actions.
public enum ScheduleExporter {
    public static func text(_ days: [DaySchedule], location: SavedLocation, display: DisplaySettings) -> String {
        var lines = ["\(location.name) · \(days.first?.methodName ?? "")"]
        for d in days {
            let cols = Prayer.allCases.map { p -> String in
                let label = d.label(p, jumuahRelabel: display.jumuahRelabel)
                let t = d.time(p).map { TimeFormatting.clock($0, in: d.timeZone, use24Hour: display.use24HourClock) } ?? "—"
                return "\(label) \(t)"
            }
            lines.append("\(TimeFormatting.shortDate(d.date))  " + cols.joined(separator: "  "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Times in 24-hour local time; empty cells mean the time is undefined for that date.
    public static func csv(_ days: [DaySchedule]) -> String {
        var rows = ["date,weekday,fajr,sunrise,dhuhr,asr,maghrib,isha,timezone,method"]
        for d in days {
            let times = Prayer.allCases.map { p in
                d.time(p).map { TimeFormatting.clock($0, in: d.timeZone, use24Hour: true) } ?? ""
            }
            let fields = [d.date.description, d.date.weekdayName] + times + [d.timeZone.identifier, d.methodName]
            rows.append(fields.map(csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    /// One zero-duration event per prayer (Sunrise excluded), in UTC.
    public static func ics(_ days: [DaySchedule], location: SavedLocation, jumuahRelabel: Bool, now: Date = Date()) -> String {
        let stamp = utcStamp(now)
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Salah//Prayer Times//EN", "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:Prayer times · \(icsText(location.name))",
        ]
        for d in days {
            for p in Prayer.prayers {
                guard let t = d.time(p) else { continue }
                lines += [
                    "BEGIN:VEVENT",
                    "UID:salah-\(d.date)-\(p.rawValue)@salah.local",
                    "DTSTAMP:\(stamp)",
                    "DTSTART:\(utcStamp(t))",
                    "DTEND:\(utcStamp(t))",
                    "SUMMARY:\(icsText(d.label(p, jumuahRelabel: jumuahRelabel)))",
                    "LOCATION:\(icsText(location.name))",
                    "DESCRIPTION:\(icsText(d.methodName))",
                    "TRANSP:TRANSPARENT",
                    "END:VEVENT",
                ]
            }
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func csvField(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }

    static func icsText(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func utcStamp(_ date: Date) -> String {
        let c = Calendar.gregorian(TimeZone(identifier: "UTC")!).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
}
