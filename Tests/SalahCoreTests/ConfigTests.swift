import XCTest
@testable import SalahCore

final class ConfigTests: XCTestCase {
    func testRoundTrip() throws {
        let store = ConfigStore(url: Fixtures.tempURL())
        var c = Fixtures.config(Fixtures.singapore, method: .custom)
        c.calculation.setOffset(2, for: .isha)
        c.display.use24HourClock = false
        c.reminders.pausedUntil = Fixtures.date("2026-09-28T00:00:00+08:00")
        c.reminders.quietHours = QuietHours(enabled: true, start: "22:30", end: "05:00")
        try store.save(c)
        XCTAssertEqual(try store.load(), c)
    }

    func testMissingFileLoadsDefaults() throws {
        XCTAssertEqual(try ConfigStore(url: Fixtures.tempURL()).load(), .default)
    }

    func testMigrationFromUnversionedFile() throws {
        let json = #"{"location":{"name":"Singapore","latitude":1.35,"longitude":103.82,"timeZone":"Asia/Singapore"}}"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.schemaVersion, SalahConfig.currentSchemaVersion)
        XCTAssertEqual(c.location?.name, "Singapore")
        XCTAssertEqual(c.location?.source, .manual)
        XCTAssertEqual(c.reminders, ReminderSettings())
    }

    func testUnknownKeysAndValuesAreTolerated() throws {
        let json = #"""
        {"schemaVersion":1,"futureFeature":{"x":1},
         "calculation":{"method":"someNewMethod","madhab":"hanafi","unknown":true},
         "display":{"theme":"sepia","nowWindowMinutes":500},
         "reminders":{"prayers":{"asr":{"enabled":false,"leadMinutes":7},"sunrise":{"enabled":true}}}}
        """#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertNil(c.calculation.method, "unknown method falls back to automatic")
        XCTAssertEqual(c.calculation.madhab, .hanafi)
        XCTAssertEqual(c.display.theme, .system)
        XCTAssertEqual(c.display.nowWindowMinutes, 60)
        XCTAssertFalse(c.reminders.reminder(for: .asr).enabled)
        XCTAssertEqual(c.reminders.reminder(for: .asr).leadMinutes, 10, "invalid lead falls back")
        XCTAssertNil(c.reminders.prayers["sunrise"], "sunrise is not a prayer")
    }

    func testCorruptFileSurfacesClearError() throws {
        let url = Fixtures.tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        XCTAssertThrowsError(try ConfigStore(url: url).load()) { error in
            guard case ConfigError.corrupt(let path, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(path, url.path)
        }
        try Data(#"{"location":{"latitude":"north"}}"#.utf8).write(to: url)
        XCTAssertThrowsError(try ConfigStore(url: url).load()) { error in
            XCTAssertTrue(error is ConfigError)
        }
    }

    func testAtomicWriteSurvivesConcurrentReads() throws {
        let store = ConfigStore(url: Fixtures.tempURL())
        try store.save(Fixtures.config(Fixtures.singapore))
        let writer = DispatchQueue(label: "writer")
        let done = expectation(description: "writes")
        writer.async {
            for i in 0..<200 {
                var c = Fixtures.config(i.isMultiple(of: 2) ? Fixtures.singapore : Fixtures.jakarta)
                c.calculation.setOffset(i % 30, for: .isha)
                try? store.save(c)
            }
            done.fulfill()
        }
        var reads = 0
        while reads < 500 {
            XCTAssertNoThrow(try store.load())
            reads += 1
        }
        wait(for: [done], timeout: 30)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["config.json"], "temp files left behind")
    }

    func testConfigKeysGetAndSet() throws {
        var c = SalahConfig.default
        try ConfigKeys.find("calculation.method").set(&c, "singapore")
        XCTAssertEqual(c.calculation.method, .singapore)
        try ConfigKeys.find("calculation.method").set(&c, "auto")
        XCTAssertNil(c.calculation.method)
        try ConfigKeys.find("calculation.offsets.isha").set(&c, "-3")
        XCTAssertEqual(c.calculation.offset(for: .isha), -3)
        try ConfigKeys.find("reminders.asr.leadMinutes").set(&c, "15")
        XCTAssertEqual(c.reminders.reminder(for: .asr).leadMinutes, 15)
        try ConfigKeys.find("display.clock").set(&c, "12")
        XCTAssertFalse(c.display.use24HourClock)
        try ConfigKeys.find("reminders.quietHours.start").set(&c, "9:05")
        XCTAssertEqual(c.reminders.quietHours.start, "09:05")

        XCTAssertThrowsError(try ConfigKeys.find("nope"))
        XCTAssertThrowsError(try ConfigKeys.find("display.clock").set(&c, "13"))
        XCTAssertThrowsError(try ConfigKeys.find("reminders.asr.leadMinutes").set(&c, "7"))
        XCTAssertThrowsError(try ConfigKeys.find("display.hijriAdjustment").set(&c, "3"))
        XCTAssertThrowsError(try ConfigKeys.find("location.name").set(&c, "X")) { error in
            XCTAssertEqual(error as? ConfigKeyError, .readOnly("location.name"))
        }
    }

    func testExporters() {
        let days = PrayerSchedule.range(from: LocalDate(year: 2026, month: 9, day: 25), days: 2, location: Fixtures.singapore, settings: CalculationSettings())
        let csv = ScheduleExporter.csv(days)
        let rows = csv.split(separator: "\r\n")
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[1].hasPrefix("2026-09-25,Friday,05:37,06:54,12:58,"))
        XCTAssertTrue(rows[1].hasSuffix(",Asia/Singapore,Singapore (MUIS)"))
        let ics = ScheduleExporter.ics(days, location: Fixtures.singapore, jumuahRelabel: true, now: Fixtures.date("2026-09-25T00:00:00Z"))
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 10)
        XCTAssertTrue(ics.contains("SUMMARY:Jumu'ah"))
        XCTAssertTrue(ics.contains("UID:salah-2026-09-25-dhuhr@salah.local"))
    }
}
