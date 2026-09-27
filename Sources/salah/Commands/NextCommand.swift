import ArgumentParser
import Foundation
import SalahCore

struct NextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "next",
        abstract: "Show the next prayer and the countdown to it."
    )

    @Flag(help: "Refresh every second until Ctrl-C.")
    var watch = false

    @OptionGroup var output: OutputOptions

    func validate() throws {
        if watch && output.json { throw ValidationError("--watch can't be combined with --json.") }
    }

    func run() async throws {
        let config = try CLIContext.loadConfig()
        let location = try CLIContext.requireLocation(config)

        guard watch else {
            CLIContext.write(try Self.render(config: config, location: location, now: CLIContext.now(), output: output))
            return
        }

        signal(SIGINT) { _ in
            FileHandle.standardOutput.write(Data("\n".utf8))
            Foundation.exit(0)
        }
        let tty = Terminal.stdoutIsTTY
        let style = Style(enabled: output.renderer.color)
        while true {
            let now = Date()
            let line = Self.watchLine(config: config, location: location, now: now, style: style)
            CLIContext.write(tty ? "\r\u{1B}[2K" + line : line + "\n")
            // Sleep to the next whole second so the countdown ticks evenly.
            let frac = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
            try await Task.sleep(nanoseconds: UInt64((1 - frac) * 1_000_000_000))
        }
    }

    static func state(config: SalahConfig, location: SavedLocation, now: Date) -> PrayerClockState {
        PrayerClock.state(now: now, location: location, settings: config.calculation, nowWindowMinutes: config.display.nowWindowMinutes)
    }

    static func render(config: SalahConfig, location: SavedLocation, now: Date, output: OutputOptions) throws -> String {
        let st = state(config: config, location: location, now: now)
        switch output.mode {
        case .json:
            return try JSONOutput.encode(JSONOutput.NextOnly(
                generatedAt: TimeFormatting.iso8601(now, in: location.tz),
                location: .init(location), method: .init(config),
                next: st.next.map { .init($0, now: now, tz: location.tz, jumuahRelabel: config.display.jumuahRelabel) },
                now: JSONOutput.now(st, config: config)
            ))
        case .compact:
            return TodayCommand.compactLine(state: st, schedule: st.today, isToday: true, config: config) + "\n"
        case .pretty, .plain:
            let header: [Line] = [[.dim("\(location.name.uppercased()) · \(config.calculation.methodShortName(for: location).uppercased())")]]
            return output.renderer.render([header, TodayCommand.nextSection(st, config: config)])
        }
    }

    static func watchLine(config: SalahConfig, location: SavedLocation, now: Date, style: Style) -> String {
        let st = state(config: config, location: location, now: now)
        let d = config.display
        guard let n = st.next else { return "Next prayer can't be calculated for this location" }
        var s = "\(style.bold(n.label(jumuahRelabel: d.jumuahRelabel).uppercased()))  "
            + TimeFormatting.clock(n.time, in: location.tz, use24Hour: d.use24HourClock)
            + "  " + style.accent("IN " + TimeFormatting.countdown(n.secondsRemaining(from: now)))
        if let p = st.nowPrayer {
            s = style.accent("\(st.today.label(p, jumuahRelabel: d.jumuahRelabel).uppercased()) NOW") + "  ·  " + s
        }
        return s
    }
}
