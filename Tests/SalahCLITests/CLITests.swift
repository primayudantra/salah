import ArgumentParser
import Foundation
import SalahCore
import XCTest
@testable import salah

final class CLITests: XCTestCase {
    private var configURL: URL!

    override func setUp() {
        super.setUp()
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("salah-cli-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        setenv("SALAH_CONFIG_PATH", configURL.path, 1)
        setenv("SALAH_NOW", "2026-09-27T19:27:42+08:00", 1)
    }

    override func tearDown() {
        unsetenv("SALAH_CONFIG_PATH")
        unsetenv("SALAH_NOW")
        super.tearDown()
    }

    private func saveSingapore() throws {
        var c = SalahConfig(location: SavedLocation(name: "Singapore", latitude: 1.3521, longitude: 103.8198, timeZone: "Asia/Singapore", countryCode: "SG"))
        c.launchAtLogin = false
        try ConfigStore(url: configURL).save(c)
    }

    private var config: SalahConfig { try! ConfigStore(url: configURL).load() }
    private var location: SavedLocation { config.location! }
    private var now: Date { CLIContext.now() }

    private func output(_ args: [String]) throws -> OutputOptions {
        try OutputOptions.parse(args)
    }

    // MARK: - Parsing

    func testParsesEveryCommand() throws {
        XCTAssertTrue(try Salah.parseAsRoot([]) is TodayCommand)
        XCTAssertTrue(try Salah.parseAsRoot(["--json"]) is TodayCommand)
        XCTAssertTrue(try Salah.parseAsRoot(["today", "--date", "2026-09-27"]) is TodayCommand)
        XCTAssertTrue(try Salah.parseAsRoot(["next", "--watch"]) is NextCommand)
        XCTAssertTrue(try Salah.parseAsRoot(["schedule", "--week"]) is ScheduleCommand)
        XCTAssertTrue(try Salah.parseAsRoot(["schedule", "--month", "--date", "2026-02-01"]) is ScheduleCommand)
        XCTAssertTrue(try Salah.parseAsRoot(["location"]) is LocationCommand.Show)
        XCTAssertTrue(try Salah.parseAsRoot(["location", "set", "Singapore"]) is LocationCommand.Set)
        XCTAssertTrue(try Salah.parseAsRoot(["location", "set", "--lat", "1.35", "--lon", "103.8", "--tz", "Asia/Singapore"]) is LocationCommand.Set)
        XCTAssertTrue(try Salah.parseAsRoot(["setup"]) is SetupCommand)
        XCTAssertTrue(try Salah.parseAsRoot(["config"]) is ConfigCommand.Get)
        XCTAssertTrue(try Salah.parseAsRoot(["config", "get", "calculation.method"]) is ConfigCommand.Get)
        XCTAssertTrue(try Salah.parseAsRoot(["config", "set", "display.clock", "12"]) is ConfigCommand.Set)
        XCTAssertTrue(try Salah.parseAsRoot(["config", "path"]) is ConfigCommand.Path)
        XCTAssertTrue(try Salah.parseAsRoot(["config", "reset"]) is ConfigCommand.Reset)
        XCTAssertTrue(try Salah.parseAsRoot(["reminders"]) is RemindersCommand.Status)
        XCTAssertTrue(try Salah.parseAsRoot(["reminders", "enable", "--prayer", "asr"]) is RemindersCommand.Enable)
        XCTAssertTrue(try Salah.parseAsRoot(["reminders", "disable"]) is RemindersCommand.Disable)
    }

    func testRejectsInvalidArguments() {
        XCTAssertThrowsError(try Salah.parseAsRoot(["today", "--date", "2026-02-30"]))
        XCTAssertThrowsError(try Salah.parseAsRoot(["schedule", "--week", "--month"]))
        XCTAssertThrowsError(try Salah.parseAsRoot(["today", "--json", "--plain"]))
        XCTAssertThrowsError(try Salah.parseAsRoot(["location", "set", "--lat", "91", "--lon", "0"]))
        XCTAssertThrowsError(try Salah.parseAsRoot(["location", "set", "--lat", "1"]))
        XCTAssertThrowsError(try Salah.parseAsRoot(["location", "set", "--lat", "1", "--lon", "1", "--tz", "Mars/Olympus"]))
        XCTAssertThrowsError(try Salah.parseAsRoot(["reminders", "enable", "--prayer", "sunrise"]))
        XCTAssertThrowsError(try Salah.parseAsRoot(["next", "--watch", "--json"]))
    }

    // MARK: - Exit codes

    func testExitCodes() async throws {
        let code3 = await Main.run(["today"])
        XCTAssertEqual(code3, 3, "missing location")
        let code2 = await Main.run(["bogus"])
        XCTAssertEqual(code2, 2)
        let badValue = await Main.run(["config", "set", "display.clock", "13"])
        XCTAssertEqual(badValue, 2)
        try saveSingapore()
        let ok = await Main.run(["today", "--compact"])
        XCTAssertEqual(ok, 0)
        try Data("{ corrupt".utf8).write(to: configURL)
        let corrupt = await Main.run(["today"])
        XCTAssertEqual(corrupt, 3)
        let reset = await Main.run(["config", "reset"])
        XCTAssertEqual(reset, 0)
    }

    // MARK: - Output

    func testCompactMatchesSpecShape() throws {
        try saveSingapore()
        let s = try TodayCommand.render(config: config, location: location, now: now, date: nil, output: output(["--compact"]))
        XCTAssertEqual(s, "Isha 20:08 (40m)\n")
    }

    func testPrettyTodaySnapshot() throws {
        try saveSingapore()
        var opts = try output([])
        opts.noColor = true
        let s = try TodayCommand.render(config: config, location: location, now: now, date: nil, output: opts)
        XCTAssertEqual(s, """
        ╭────────────────────────────────────────────╮
        │  SALAH                                     │
        │  SUNDAY, 27 SEPTEMBER 2026                 │
        │  16 RABI' AL-THANI 1448                    │
        │  SINGAPORE · MUIS                          │
        ├────────────────────────────────────────────┤
        │  NEXT PRAYER                               │
        │  ISHA  20:08  IN 00:40:18                  │
        ├────────────────────────────────────────────┤
        │  Fajr       05:36                          │
        │  Sunrise    06:53                          │
        │  Dhuhr      12:57                          │
        │  Asr        16:01                          │
        │  Maghrib    18:59                          │
        │  Isha       20:08   ◀ next                 │
        ╰────────────────────────────────────────────╯

        """)
    }

    func testPlainAndNoColorHaveNoEscapeCodes() throws {
        try saveSingapore()
        for args in [["--plain"], ["--no-color"], ["--compact"], ["--json"]] {
            let out = try TodayCommand.render(config: config, location: location, now: now, date: nil, output: output(args))
            XCTAssertFalse(out.contains("\u{1B}"), "escape code in \(args)")
        }
        let plain = try TodayCommand.render(config: config, location: location, now: now, date: nil, output: output(["--plain"]))
        XCTAssertFalse(plain.contains("│"))
        XCTAssertFalse(plain.contains("╭"))
    }

    func testColorPolicy() {
        XCTAssertTrue(Terminal.colorAllowed(environment: [:], isTTY: true))
        XCTAssertFalse(Terminal.colorAllowed(environment: [:], isTTY: false))
        XCTAssertFalse(Terminal.colorAllowed(environment: ["NO_COLOR": "1"], isTTY: true))
        XCTAssertTrue(Terminal.colorAllowed(environment: ["NO_COLOR": ""], isTTY: true))
        XCTAssertFalse(Terminal.colorAllowed(environment: ["TERM": "dumb"], isTTY: true))
    }

    func testTodayJSONSchema() throws {
        try saveSingapore()
        let s = try TodayCommand.render(config: config, location: location, now: now, date: nil, output: output(["--json"]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "generatedAt", "location", "method", "day", "next", "now", "currentPeriod"])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["generatedAt"] as? String, "2026-09-27T19:27:42+08:00")
        XCTAssertTrue(json["now"] is NSNull)
        let method = try XCTUnwrap(json["method"] as? [String: Any])
        XCTAssertEqual(method["id"] as? String, "singapore")
        XCTAssertEqual(method["name"] as? String, "Singapore (MUIS)")
        let next = try XCTUnwrap(json["next"] as? [String: Any])
        XCTAssertEqual(next["prayer"] as? String, "isha")
        XCTAssertEqual(next["time"] as? String, "2026-09-27T20:08:00+08:00")
        XCTAssertEqual(next["isTomorrow"] as? Bool, false)
        XCTAssertEqual(next["secondsRemaining"] as? Int, 2418)
        let day = try XCTUnwrap(json["day"] as? [String: Any])
        let prayers = try XCTUnwrap(day["prayers"] as? [[String: Any]])
        XCTAssertEqual(prayers.map { $0["prayer"] as? String }, ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"])
        XCTAssertEqual(prayers[1]["isPrayer"] as? Bool, false)
        for p in prayers {
            let t = try XCTUnwrap(p["time"] as? String)
            XCTAssertTrue(t.hasSuffix("+08:00"), t)
        }
    }

    func testScheduleJSONAndFridayLabel() throws {
        try saveSingapore()
        let s = try ScheduleCommand.render(config: config, location: location, now: now, start: LocalDate(year: 2026, month: 9, day: 21), period: .week, output: output(["--json"]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
        let days = try XCTUnwrap(json["days"] as? [[String: Any]])
        XCTAssertEqual(days.count, 7)
        let friday = try XCTUnwrap(days.first { $0["weekday"] as? String == "Friday" })
        let dhuhr = try XCTUnwrap((friday["prayers"] as? [[String: Any]])?.first { $0["prayer"] as? String == "dhuhr" })
        XCTAssertEqual(dhuhr["label"] as? String, "Jumu'ah")
    }

    func testNextAfterIshaIsTomorrow() throws {
        try saveSingapore()
        let s = try NextCommand.render(config: config, location: location, now: Fixtures.date("2026-09-27T22:10:00+08:00"), output: output(["--plain"]))
        XCTAssertTrue(s.contains("NEXT PRAYER · TOMORROW"), s)
        XCTAssertTrue(s.contains("FAJR  05:36  IN 07:26:00"), s)
    }

    func testRemindersMessageNeverClaimsScheduling() {
        let off = RemindersCommand.savedMessage(what: "Reminders on.", appRunning: false)
        XCTAssertEqual(off, "Saved. Reminders on. Reminders take effect when Salah.app is running.")
        XCTAssertFalse(off.lowercased().contains("scheduled"))
        XCTAssertTrue(RemindersCommand.savedMessage(what: "Reminders on.", appRunning: true).contains("Salah.app is running"))
    }
}

private enum Fixtures {
    static func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
}
