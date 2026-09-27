import ArgumentParser
import Foundation
import SalahCore

struct RemindersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Show or change reminder settings. Salah.app delivers the notifications.",
        subcommands: [Status.self, Enable.self, Disable.self],
        defaultSubcommand: Status.self
    )

    struct PrayerOption: ParsableArguments {
        @Option(help: "Only this prayer: fajr, dhuhr, asr, maghrib or isha.")
        var prayer: String?

        func resolved() throws -> Prayer? {
            guard let prayer else { return nil }
            guard let p = Prayer(name: prayer), p.isPrayer else {
                throw ValidationError("Unknown prayer “\(prayer)”. Use fajr, dhuhr, asr, maghrib or isha.")
            }
            return p
        }

        func validate() throws { _ = try resolved() }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show reminder settings and whether Salah.app is running.")

        @OptionGroup var output: OutputOptions

        func run() async throws {
            let config = try CLIContext.loadConfig()
            CLIContext.write(try Self.render(config: config, now: CLIContext.now(), appRunning: CLIContext.appIsRunning, output: output))
        }

        struct JSONStatus: Encodable {
            let enabled: Bool
            let paused: Bool
            let pausedUntil: String?
            let sound: String
            let quietHours: QuietHours
            let prayers: [String: PrayerReminder]
            let appRunning: Bool
            let plannedCount: Int
            let nextReminder: String?

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(enabled, forKey: .enabled)
                try c.encode(paused, forKey: .paused)
                try c.encode(pausedUntil, forKey: .pausedUntil)
                try c.encode(sound, forKey: .sound)
                try c.encode(quietHours, forKey: .quietHours)
                try c.encode(prayers, forKey: .prayers)
                try c.encode(appRunning, forKey: .appRunning)
                try c.encode(plannedCount, forKey: .plannedCount)
                try c.encode(nextReminder, forKey: .nextReminder)
            }

            enum CodingKeys: String, CodingKey {
                case enabled, paused, pausedUntil, sound, quietHours, prayers, appRunning, plannedCount, nextReminder
            }
        }

        static func render(config: SalahConfig, now: Date, appRunning: Bool, output: OutputOptions) throws -> String {
            let r = config.reminders
            let tz = config.location?.tz ?? .current
            let planned = NotificationPlanner.plan(from: now, config: config)
            let paused = r.isPaused(at: now)

            switch output.mode {
            case .json:
                return try JSONOutput.encode(JSONStatus(
                    enabled: r.enabled, paused: paused,
                    pausedUntil: r.pausedUntil.map { TimeFormatting.iso8601($0, in: tz) },
                    sound: r.sound.rawValue, quietHours: r.quietHours, prayers: r.prayers,
                    appRunning: appRunning, plannedCount: planned.count,
                    nextReminder: planned.first.map { TimeFormatting.iso8601($0.fireDate, in: tz) }
                ))
            case .compact:
                let state = !r.enabled ? "off" : paused ? "paused" : "on"
                return "reminders \(state) · \(planned.count) planned · app \(appRunning ? "running" : "not running")\n"
            case .pretty, .plain:
                let stateText = !r.enabled ? "OFF" : paused ? "PAUSED" : "ON"
                var head: [Line] = [
                    [.bold("REMINDERS  "), r.enabled && !paused ? .accent(stateText) : .dim(stateText)],
                    [.dim(appRunning ? "Salah.app is running" : "Salah.app is not running — reminders are delivered only by the app")],
                ]
                if paused, let until = r.pausedUntil {
                    head.append([.normal("Paused until \(TimeFormatting.shortDate(LocalDate(until, in: tz))) \(TimeFormatting.clock(until, in: tz, use24Hour: config.display.use24HourClock))")])
                }
                let rows: [Line] = Prayer.prayers.map { p in
                    let pr = r.reminder(for: p)
                    let desc: String
                    if !pr.enabled {
                        desc = "off"
                    } else {
                        var parts: [String] = []
                        if pr.leadMinutes > 0 { parts.append("\(pr.leadMinutes) min before") }
                        if pr.atTime { parts.append("at prayer time") }
                        desc = parts.isEmpty ? "off" : parts.joined(separator: " + ")
                    }
                    return [.normal(Renderer.pad(p.name, 11)), pr.enabled && r.enabled ? .normal(desc) : .dim(desc)]
                }
                var foot: [Line] = [
                    [.normal("Sound: \(r.sound.displayName)")],
                    [.normal("Quiet hours: " + (r.quietHours.enabled ? "\(r.quietHours.start)–\(r.quietHours.end)" : "off"))],
                ]
                if let first = planned.first {
                    let when = "\(TimeFormatting.shortDate(first.date)) \(TimeFormatting.clock(first.fireDate, in: tz, use24Hour: config.display.use24HourClock))"
                    foot.append([.dim("Next: \(first.title) · \(when)")])
                    foot.append([.dim("\(planned.count) reminders in the next \(NotificationPlanner.defaultDays) days")])
                }
                foot.append([.dim("Reminders stop if Salah.app doesn't run for 3 days.")])
                return output.renderer.render([head, rows, foot])
            }
        }
    }

    struct Enable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Turn reminders on (all, or one prayer). Also clears any pause.")

        @OptionGroup var prayerOption: PrayerOption

        func run() async throws {
            let prayer = try prayerOption.resolved()
            try CLIContext.store.update { c in
                if let prayer {
                    c.reminders.update(prayer) { $0.enabled = true }
                } else {
                    c.reminders.enabled = true
                    c.reminders.pausedUntil = nil
                }
            }
            print(RemindersCommand.savedMessage(what: prayer.map { "\($0.name) reminders on." } ?? "Reminders on.", appRunning: CLIContext.appIsRunning))
        }
    }

    struct Disable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Turn reminders off (all, or one prayer).")

        @OptionGroup var prayerOption: PrayerOption

        func run() async throws {
            let prayer = try prayerOption.resolved()
            try CLIContext.store.update { c in
                if let prayer {
                    c.reminders.update(prayer) { $0.enabled = false }
                } else {
                    c.reminders.enabled = false
                }
            }
            print(RemindersCommand.savedMessage(what: prayer.map { "\($0.name) reminders off." } ?? "Reminders off.", appRunning: CLIContext.appIsRunning))
        }
    }

    /// Never claims notifications are scheduled: only the app schedules them.
    static func savedMessage(what: String, appRunning: Bool) -> String {
        appRunning
            ? "Saved. \(what) Salah.app is running and will update its scheduled reminders."
            : "Saved. \(what) Reminders take effect when Salah.app is running."
    }
}
