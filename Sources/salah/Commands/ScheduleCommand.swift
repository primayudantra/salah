import ArgumentParser
import Foundation
import SalahCore

struct ScheduleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Show prayer times for a day, a week or a month."
    )

    @Option(help: "Start date (YYYY-MM-DD). Defaults to today.")
    var date: String?

    @Flag(help: "Seven days starting at the date.")
    var week = false

    @Flag(help: "The whole calendar month containing the date.")
    var month = false

    @OptionGroup var output: OutputOptions

    func validate() throws {
        _ = try CLIContext.parseDate(date)
        if week && month { throw ValidationError("Use either --week or --month, not both.") }
    }

    func run() async throws {
        let config = try CLIContext.loadConfig()
        let location = try CLIContext.requireLocation(config)
        let now = CLIContext.now()
        let start = try CLIContext.parseDate(date) ?? LocalDate(now, in: location.tz)
        let period: Period = week ? .week : month ? .month : .day
        CLIContext.write(try Self.render(config: config, location: location, now: now, start: start, period: period, output: output))
    }

    enum Period { case day, week, month }

    static func render(config: SalahConfig, location: SavedLocation, now: Date, start: LocalDate, period: Period, output: OutputOptions) throws -> String {
        let days: [DaySchedule]
        switch period {
        case .day: days = [PrayerSchedule.for(date: start, location: location, settings: config.calculation)]
        case .week: days = PrayerSchedule.range(from: start, days: 7, location: location, settings: config.calculation)
        case .month: days = PrayerSchedule.month(containing: start, location: location, settings: config.calculation)
        }
        let d = config.display
        let today = LocalDate(now, in: location.tz)

        switch output.mode {
        case .json:
            return try JSONOutput.encode(JSONOutput.Schedule(
                generatedAt: TimeFormatting.iso8601(now, in: location.tz),
                location: .init(location), method: .init(config),
                days: days.map { .init($0, config: config) }
            ))
        case .compact:
            return days.map { s in
                "\(s.date) " + Prayer.allCases.map { p in
                    "\(s.label(p, jumuahRelabel: d.jumuahRelabel)) \(s.time(p).map { TimeFormatting.clock($0, in: s.timeZone, use24Hour: d.use24HourClock) } ?? "—")"
                }.joined(separator: " · ")
            }.joined(separator: "\n") + "\n"
        case .pretty, .plain:
            if period == .day {
                let s = days[0]
                return output.renderer.render([
                    DayView.header(s.date, location: location, config: config),
                    DayView.rows(s, config: config, state: nil) + DayView.undefinedNote(s),
                ])
            }
            return output.renderer.render(table(days, location: location, config: config, today: today))
        }
    }

    static func table(_ days: [DaySchedule], location: SavedLocation, config: SalahConfig, today: LocalDate) -> [[Line]] {
        let d = config.display
        let first = days.first!.date, last = days.last!.date
        let range = "\(first.day) \(first.monthName.prefix(3).uppercased()) – \(last.day) \(last.monthName.prefix(3).uppercased()) \(last.year)"
        let header: [Line] = [
            [.bold("SALAH · SCHEDULE")],
            [.normal(range)],
            [.dim("\(location.name.uppercased()) · \(config.calculation.methodShortName(for: location).uppercased())")],
        ]

        let timeWidth = d.use24HourClock ? 5 : 8
        let dateWidth = 12
        func col(_ s: String, _ w: Int) -> String { Renderer.pad(s, w + 2) }

        var rows: [Line] = [[.dim(col("Date", dateWidth) + Prayer.allCases.map { col($0.name, max(timeWidth, 7)) }.joined())]]
        var hasFriday = false
        for s in days {
            let dateLabel = "\(s.date.weekdayName.prefix(3)) \(s.date.day) \(s.date.monthName.prefix(3))"
            let cells = Prayer.allCases.map { p -> String in
                var t = DayView.time(s.time(p), s.timeZone, d)
                if p == .dhuhr && s.isFriday && d.jumuahRelabel { t += "*"; hasFriday = true }
                return col(t, max(timeWidth, 7))
            }
            let text = col(dateLabel, dateWidth) + cells.joined()
            rows.append([Span(text: text, kind: s.date == today ? .bold : .normal)])
        }
        var notes: [Line] = [[.dim("Sunrise marks the end of Fajr and is not a prayer.")]]
        if hasFriday { notes.insert([.dim("* Jumu'ah")], at: 0) }
        if days.contains(where: \.hasUndefined) {
            notes.append([.accent("— means the time can't be calculated here on that date.")])
        }
        return [header, rows, notes]
    }
}
