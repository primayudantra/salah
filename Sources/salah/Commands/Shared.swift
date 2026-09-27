import AppKit
import ArgumentParser
import Foundation
import SalahCore

struct OutputOptions: ParsableArguments {
    @Flag(help: "Print JSON (stable schema, ISO 8601 times with offset).")
    var json = false

    @Flag(help: "Print a single line, for shell prompts.")
    var compact = false

    @Flag(help: "Print without box drawing or color.")
    var plain = false

    @Flag(name: .customLong("no-color"), help: "Disable color.")
    var noColor = false

    func validate() throws {
        if [json, compact, plain].filter({ $0 }).count > 1 {
            throw ValidationError("Use only one of --json, --compact and --plain.")
        }
    }

    var mode: OutputMode { json ? .json : compact ? .compact : plain ? .plain : .pretty }

    var renderer: Renderer {
        Renderer(mode: mode, color: mode == .pretty && !noColor && Terminal.colorAllowed())
    }
}

/// Shared loading and clock for commands.
enum CLIContext {
    static var store: ConfigStore { ConfigStore() }

    static func loadConfig() throws -> SalahConfig { try store.load() }

    static func requireLocation(_ config: SalahConfig) throws -> SavedLocation {
        guard let loc = config.location else { throw CLIError.missingLocation() }
        guard loc.isValid else {
            throw CLIError(code: CLIError.missingConfig, message: "The saved location is invalid. Run `salah setup` or `salah location set <city>`.")
        }
        return loc
    }

    /// The current instant. `SALAH_NOW` (ISO 8601) overrides it for deterministic tests.
    static func now() -> Date {
        if let s = ProcessInfo.processInfo.environment["SALAH_NOW"], let d = ISO8601DateFormatter().date(from: s) {
            return d
        }
        return Date()
    }

    static func parseDate(_ s: String?) throws -> LocalDate? {
        guard let s else { return nil }
        guard let d = LocalDate(string: s) else {
            throw ValidationError("Invalid date “\(s)”. Use YYYY-MM-DD.")
        }
        return d
    }

    static var appIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: SalahInfo.appBundleIdentifier).isEmpty
    }

    static func write(_ s: String) {
        FileHandle.standardOutput.write(Data(s.utf8))
    }
}

/// Builders for the day view shared by `today` and `schedule`.
enum DayView {
    static func time(_ date: Date?, _ tz: TimeZone, _ display: DisplaySettings) -> String {
        guard let date else { return "—" }
        return TimeFormatting.clock(date, in: tz, use24Hour: display.use24HourClock, padHour: true)
    }

    static func header(_ day: LocalDate, location: SavedLocation, config: SalahConfig, title: String = "SALAH") -> [Line] {
        [
            [.bold(title)],
            [.normal(TimeFormatting.longDate(day).uppercased())],
            [.dim(HijriDate(day, adjustment: config.display.hijriAdjustment).formatted.uppercased())],
            [.dim("\(location.name.uppercased()) · \(config.calculation.methodShortName(for: location).uppercased())")],
        ]
    }

    /// Timeline rows. `state` marks next/now when the schedule is today's.
    static func rows(_ s: DaySchedule, config: SalahConfig, state: PrayerClockState?) -> [Line] {
        let d = config.display
        return Prayer.allCases.map { p in
            let label = Renderer.pad(s.label(p, jumuahRelabel: d.jumuahRelabel), 11)
            let t = time(s.time(p), s.timeZone, d)
            var marker: Span?
            if let state {
                if state.nowPrayer == p {
                    marker = .accent("   ◀ now")
                } else if let n = state.next, !n.isTomorrow, n.prayer == p {
                    marker = .accent("   ◀ next")
                }
            }
            let isPast = state.map { st in s.time(p).map { $0 <= st.now } ?? false } ?? false
            let kind: Span.Kind = p == .sunrise || (isPast && marker == nil) ? .dim : .normal
            var line: Line = [Span(text: label, kind: kind), Span(text: t, kind: marker != nil ? .bold : kind)]
            if let marker { line.append(marker) }
            return line
        }
    }

    static func undefinedNote(_ s: DaySchedule) -> [Line] {
        guard let e = s.undefinedExplanation else { return [] }
        var lines: [Line] = wrap(e.reason, 60).map { [.accent($0)] }
        if s.times.isEmpty, let hint = e.suggestion {
            lines += wrap(hint, 60).map { [.dim($0)] }
        } else if !s.times.isEmpty {
            lines.append([.dim("Try: salah config set calculation.highLatitudeRule seventhOfTheNight")])
        }
        return lines
    }

    /// Word-wraps to keep box lines readable.
    static func wrap(_ text: String, _ width: Int) -> [String] {
        var lines: [String] = [], cur = ""
        for word in text.split(separator: " ") {
            if !cur.isEmpty && cur.count + word.count + 1 > width { lines.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : " ") + word
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }
}
