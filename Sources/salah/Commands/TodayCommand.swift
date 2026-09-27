import ArgumentParser
import Foundation
import SalahCore

struct TodayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "today",
        abstract: "Show today's prayer times and the next prayer (the default command)."
    )

    @Option(help: "Show another date instead of today (YYYY-MM-DD).")
    var date: String?

    @OptionGroup var output: OutputOptions

    func validate() throws { _ = try CLIContext.parseDate(date) }

    func run() async throws {
        let config = try CLIContext.loadConfig()
        let location = try CLIContext.requireLocation(config)
        let now = CLIContext.now()
        CLIContext.write(try Self.render(config: config, location: location, now: now, date: try CLIContext.parseDate(date), output: output))
    }

    static func render(config: SalahConfig, location: SavedLocation, now: Date, date: LocalDate?, output: OutputOptions) throws -> String {
        let state = PrayerClock.state(
            now: now, location: location, settings: config.calculation, nowWindowMinutes: config.display.nowWindowMinutes
        )
        let isToday = date == nil || date == state.today.date
        let schedule = isToday ? state.today : PrayerSchedule.for(date: date!, location: location, settings: config.calculation)
        let d = config.display

        switch output.mode {
        case .json:
            return try JSONOutput.encode(JSONOutput.Today(
                generatedAt: TimeFormatting.iso8601(now, in: location.tz),
                location: .init(location), method: .init(config),
                day: .init(schedule, config: config),
                next: isToday ? state.next.map { .init($0, now: now, tz: location.tz, jumuahRelabel: d.jumuahRelabel) } : nil,
                now: isToday ? JSONOutput.now(state, config: config) : nil,
                currentPeriod: isToday ? state.current?.rawValue : nil
            ))
        case .compact:
            return compactLine(state: state, schedule: schedule, isToday: isToday, config: config) + "\n"
        case .pretty, .plain:
            var sections = [DayView.header(schedule.date, location: location, config: config)]
            if isToday { sections.append(nextSection(state, config: config)) }
            sections.append(DayView.rows(schedule, config: config, state: isToday ? state : nil) + DayView.undefinedNote(schedule))
            return output.renderer.render(sections)
        }
    }

    static func nextSection(_ state: PrayerClockState, config: SalahConfig) -> [Line] {
        let d = config.display
        let tz = state.today.timeZone
        var lines: [Line] = []
        if let p = state.nowPrayer, let t = state.today.time(p) {
            lines.append([.dim("NOW")])
            lines.append([
                .accent(state.today.label(p, jumuahRelabel: d.jumuahRelabel).uppercased()),
                .normal("  " + DayView.time(t, tz, d)),
                .dim("  STARTED " + TimeFormatting.countdown(state.secondsSinceNow ?? 0)),
            ])
        }
        if let n = state.next {
            lines.append([.dim(n.isTomorrow ? "NEXT PRAYER · TOMORROW" : "NEXT PRAYER")])
            lines.append([
                .bold(n.label(jumuahRelabel: d.jumuahRelabel).uppercased()),
                .normal("  " + DayView.time(n.time, tz, d)),
                .accent("  IN " + TimeFormatting.countdown(n.secondsRemaining(from: state.now))),
            ])
        } else {
            lines.append([.dim("NEXT PRAYER")])
            lines.append([.normal("— can't be calculated for this location")])
        }
        return lines
    }

    /// e.g. "Isha 20:10 (42m)", or "Asr now · Maghrib 18:55 (2h 50m)" inside the NOW window.
    static func compactLine(state: PrayerClockState, schedule: DaySchedule, isToday: Bool, config: SalahConfig) -> String {
        let d = config.display
        let tz = schedule.timeZone
        guard isToday else {
            return Prayer.allCases.map { p in
                "\(schedule.label(p, jumuahRelabel: d.jumuahRelabel)) \(schedule.time(p).map { TimeFormatting.clock($0, in: tz, use24Hour: d.use24HourClock) } ?? "—")"
            }.joined(separator: " · ")
        }
        var parts: [String] = []
        if let p = state.nowPrayer { parts.append("\(state.today.label(p, jumuahRelabel: d.jumuahRelabel)) now") }
        if let n = state.next {
            parts.append("\(n.label(jumuahRelabel: d.jumuahRelabel)) \(TimeFormatting.clock(n.time, in: tz, use24Hour: d.use24HourClock)) (\(TimeFormatting.short(n.secondsRemaining(from: state.now))))")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
