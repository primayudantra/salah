import XCTest
@testable import SalahCore

final class TimeEdgeTests: XCTestCase {
    private func assertOrdered(_ s: DaySchedule, file: StaticString = #filePath, line: UInt = #line) {
        let times = Prayer.allCases.compactMap { s.time($0) }
        XCTAssertEqual(times.count, 6, file: file, line: line)
        XCTAssertEqual(times, times.sorted(), "times out of order on \(s.date)", file: file, line: line)
        for t in times {
            XCTAssertEqual(LocalDate(t, in: s.timeZone), s.date, "time falls on another local day", file: file, line: line)
        }
    }

    func testDSTTransitionDays() {
        let days: [(SavedLocation, LocalDate)] = [
            (Fixtures.newYork, LocalDate(year: 2026, month: 3, day: 8)),
            (Fixtures.newYork, LocalDate(year: 2026, month: 11, day: 1)),
            (Fixtures.london, LocalDate(year: 2026, month: 3, day: 29)),
            (Fixtures.london, LocalDate(year: 2026, month: 10, day: 25)),
        ]
        for (loc, d) in days {
            for offset in -1...1 {
                assertOrdered(PrayerSchedule.for(date: d.adding(days: offset), location: loc, settings: CalculationSettings(method: .northAmerica)))
            }
        }
    }

    func testDSTSpringForwardShiftsLocalClockByAnHour() {
        let s = CalculationSettings(method: .northAmerica)
        let before = PrayerSchedule.for(date: LocalDate(year: 2026, month: 3, day: 7), location: Fixtures.newYork, settings: s)
        let after = PrayerSchedule.for(date: LocalDate(year: 2026, month: 3, day: 8), location: Fixtures.newYork, settings: s)
        let tz = Fixtures.newYork.tz
        let dhuhrBefore = TimeFormatting.clock(before.time(.dhuhr)!, in: tz, use24Hour: true)
        let dhuhrAfter = TimeFormatting.clock(after.time(.dhuhr)!, in: tz, use24Hour: true)
        XCTAssertTrue(dhuhrBefore.hasPrefix("12:"), dhuhrBefore)
        XCTAssertTrue(dhuhrAfter.hasPrefix("13:"), dhuhrAfter)
    }

    func testManualLocationIgnoresMachineTimeZone() {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        // 01:00 on the 28th in Singapore is still the 27th in Los Angeles.
        let now = Fixtures.date("2026-09-28T01:00:00+08:00")
        let state = PrayerClock.state(now: now, location: Fixtures.singapore, settings: CalculationSettings(), nowWindowMinutes: 15)
        XCTAssertEqual(state.today.date, LocalDate(year: 2026, month: 9, day: 28))
        XCTAssertEqual(state.next?.prayer, .fajr)
        XCTAssertEqual(state.next?.isTomorrow, false)
        XCTAssertEqual(TimeFormatting.clock(state.next!.time, in: Fixtures.singapore.tz, use24Hour: true), "05:36")
    }

    func testAfterIshaNextIsTomorrowsFajrAcrossMidnight() {
        let now = Fixtures.date("2026-09-27T22:10:00+08:00")
        let next = NextPrayerResolver.resolve(now: now, location: Fixtures.singapore, settings: CalculationSettings())!
        XCTAssertEqual(next.prayer, .fajr)
        XCTAssertTrue(next.isTomorrow)
        XCTAssertEqual(next.date, LocalDate(year: 2026, month: 9, day: 28))
        // 22:10 → 05:36 is 7h26m, spanning midnight.
        XCTAssertEqual(next.secondsRemaining(from: now), 7 * 3600 + 26 * 60, accuracy: 60)
        XCTAssertEqual(TimeFormatting.countdown(next.secondsRemaining(from: now)), "07:26:00")
    }

    func testMidnightRolloverSwapsSchedule() {
        let before = PrayerClock.state(now: Fixtures.date("2026-09-27T23:59:59+08:00"), location: Fixtures.singapore, settings: CalculationSettings(), nowWindowMinutes: 15)
        let after = PrayerClock.state(now: Fixtures.date("2026-09-28T00:00:01+08:00"), location: Fixtures.singapore, settings: CalculationSettings(), nowWindowMinutes: 15)
        XCTAssertEqual(before.today.date, LocalDate(year: 2026, month: 9, day: 27))
        XCTAssertEqual(after.today.date, LocalDate(year: 2026, month: 9, day: 28))
        XCTAssertTrue(before.next!.isTomorrow)
        XCTAssertFalse(after.next!.isTomorrow)
        XCTAssertEqual(before.next!.time, after.next!.time)
    }

    func testJumuahOnlyOnFridayAndWhenEnabled() {
        let friday = LocalDate(year: 2026, month: 9, day: 25)
        let saturday = LocalDate(year: 2026, month: 9, day: 26)
        XCTAssertTrue(friday.isFriday)
        let f = PrayerSchedule.for(date: friday, location: Fixtures.singapore, settings: CalculationSettings())
        let s = PrayerSchedule.for(date: saturday, location: Fixtures.singapore, settings: CalculationSettings())
        XCTAssertEqual(f.label(.dhuhr, jumuahRelabel: true), "Jumu'ah")
        XCTAssertEqual(f.label(.dhuhr, jumuahRelabel: false), "Dhuhr")
        XCTAssertEqual(s.label(.dhuhr, jumuahRelabel: true), "Dhuhr")
        XCTAssertEqual(f.label(.asr, jumuahRelabel: true), "Asr")

        let next = NextPrayerResolver.resolve(now: Fixtures.date("2026-09-25T10:00:00+08:00"), location: Fixtures.singapore, settings: CalculationSettings())!
        XCTAssertEqual(next.label(jumuahRelabel: true), "Jumu'ah")
        XCTAssertEqual(next.label(jumuahRelabel: false), "Dhuhr")
    }

    func testNowWindowStartsAndEnds() {
        let settings = CalculationSettings()
        let asr = PrayerSchedule.for(date: LocalDate(year: 2026, month: 9, day: 27), location: Fixtures.singapore, settings: settings).time(.asr)!
        func state(_ offset: TimeInterval, window: Int = 15) -> PrayerClockState {
            PrayerClock.state(now: asr.addingTimeInterval(offset), location: Fixtures.singapore, settings: settings, nowWindowMinutes: window)
        }
        XCTAssertNil(state(-1).nowPrayer)
        XCTAssertEqual(state(0).nowPrayer, .asr)
        XCTAssertEqual(state(14 * 60 + 59).nowPrayer, .asr)
        XCTAssertNil(state(15 * 60).nowPrayer)
        XCTAssertNil(state(60, window: 0).nowPrayer)
        XCTAssertEqual(state(60).next?.prayer, .maghrib)
        XCTAssertEqual(state(60).current, .asr)
    }

    func testFajrPeriodEndsAtSunrise() {
        let s = PrayerSchedule.for(date: LocalDate(year: 2026, month: 9, day: 27), location: Fixtures.singapore, settings: CalculationSettings())
        let during = PrayerClock.state(now: s.time(.fajr)!.addingTimeInterval(600), location: Fixtures.singapore, settings: CalculationSettings(), nowWindowMinutes: 0)
        let afterSunrise = PrayerClock.state(now: s.time(.sunrise)!.addingTimeInterval(60), location: Fixtures.singapore, settings: CalculationSettings(), nowWindowMinutes: 0)
        XCTAssertEqual(during.current, .fajr)
        XCTAssertNil(afterSunrise.current)
    }

    func testHijriDateAndAdjustment() {
        let d = LocalDate(year: 2026, month: 9, day: 27)
        let h = HijriDate(d)
        XCTAssertEqual(h.year, 1448)
        XCTAssertEqual(h.month, 4)
        XCTAssertEqual(h.monthName, "Rabi' al-Thani")
        XCTAssertEqual(HijriDate(d, adjustment: 1), HijriDate(d.adding(days: 1)))
        XCTAssertEqual(HijriDate(d, adjustment: -2), HijriDate(d.adding(days: -2)))
        // Clamped to ±2.
        XCTAssertEqual(HijriDate(d, adjustment: 5), HijriDate(d, adjustment: 2))
    }

    func testLocalDateParsing() {
        XCTAssertEqual(LocalDate(string: "2026-09-27"), LocalDate(year: 2026, month: 9, day: 27))
        XCTAssertNil(LocalDate(string: "2026-02-30"))
        XCTAssertNil(LocalDate(string: "27/09/2026"))
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1), LocalDate(year: 2027, month: 1, day: 1))
        XCTAssertEqual(LocalDate(year: 2028, month: 2, day: 1).daysInMonth, 29)
    }

    func testFormatting() {
        XCTAssertEqual(TimeFormatting.countdown(5143), "01:25:43")
        XCTAssertEqual(TimeFormatting.countdown(-4), "00:00:00")
        XCTAssertEqual(TimeFormatting.short(42 * 60 + 18), "42m")
        XCTAssertEqual(TimeFormatting.short(85 * 60), "1h 25m")
        XCTAssertEqual(TimeFormatting.short(30), "<1m")
        XCTAssertEqual(TimeFormatting.spoken(85 * 60), "1 hour 25 minutes")
        let t = Fixtures.date("2026-09-27T20:10:00+08:00")
        XCTAssertEqual(TimeFormatting.clock(t, in: Fixtures.singapore.tz, use24Hour: true), "20:10")
        XCTAssertEqual(TimeFormatting.clock(t, in: Fixtures.singapore.tz, use24Hour: false), "8:10 PM")
        XCTAssertEqual(TimeFormatting.clock(t, in: Fixtures.singapore.tz, use24Hour: false, padHour: true), "08:10 PM")
        XCTAssertEqual(TimeFormatting.iso8601(t, in: Fixtures.singapore.tz), "2026-09-27T20:10:00+08:00")
    }
}
