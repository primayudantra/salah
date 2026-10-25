import XCTest
@testable import SalahCore

final class KindWordsPlannerTests: XCTestCase {
    /// Friday 25 September 2026, just after midnight in Singapore.
    let fridayStart = Fixtures.date("2026-09-25T00:00:30+08:00")
    let friday = LocalDate(year: 2026, month: 9, day: 25)

    func config(_ body: (inout KindWordsSettings) -> Void = { _ in }) -> SalahConfig {
        var c = Fixtures.config(Fixtures.singapore)
        c.kindWords.enabled = true
        body(&c.kindWords)
        return c
    }

    func testOffByDefaultAddsNothing() {
        let plan = NotificationPlanner.plan(from: fridayStart, config: Fixtures.config(Fixtures.singapore))
        XCTAssertFalse(plan.contains { $0.prayer == nil })
        XCTAssertFalse(plan.contains { $0.body.contains("—") }, "no kind line added to prayer reminders")
    }

    func testFridayPlan() {
        let plan = KindWordsPlanner.plan(from: fridayStart, days: 1, config: config())
        let ids = Set(plan.map(\.id))
        XCTAssertTrue(ids.contains("salah.2026-09-25.kind.friday-kahf"))
        XCTAssertTrue(ids.contains("salah.2026-09-25.kind.friday-lasthour"))
        XCTAssertTrue(ids.contains("salah.2026-09-25.kind.after-dhuhr"))
        XCTAssertTrue(plan.contains { $0.title == "Have you prayed Jumu'ah?" })
        XCTAssertTrue(plan.allSatisfy { $0.silent && $0.id.hasPrefix(NotificationPlanner.idPrefix) })

        // The last hour starts an hour before Maghrib.
        let schedule = PrayerSchedule.for(date: friday, location: Fixtures.singapore, settings: CalculationSettings())
        let lastHour = plan.first { $0.id.hasSuffix("friday-lasthour") }!
        XCTAssertEqual(lastHour.fireDate, schedule.time(.maghrib)!.addingTimeInterval(-3600))
    }

    func testKindWordSlotsKeepClearOfPrayersAndEachOther() {
        let c = config()
        let plan = KindWordsPlanner.plan(from: fridayStart, days: 3, config: c)
        let words = plan.filter { $0.id.contains(".kind.word-") }
        XCTAssertFalse(words.isEmpty)
        for w in words {
            let schedule = PrayerSchedule.for(date: w.date, location: Fixtures.singapore, settings: c.calculation)
            for p in Prayer.prayers {
                XCTAssertGreaterThanOrEqual(abs(schedule.time(p)!.timeIntervalSince(w.fireDate)), 45 * 60, w.id)
            }
        }
        // Singapore Dhuhr is ≈13:00, so the 13:00 slot is always skipped.
        XCTAssertFalse(words.contains { $0.id.hasSuffix("word-1300") })
    }

    func testDeterministicAndUnique() {
        let a = NotificationPlanner.plan(from: fridayStart, config: config())
        let b = NotificationPlanner.plan(from: fridayStart, config: config())
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)
        XCTAssertLessThanOrEqual(a.count, NotificationPlanner.maxPending)
        XCTAssertEqual(a.map(\.fireDate), a.map(\.fireDate).sorted())
    }

    func testBeforePrayerLineOnEarlyReminderOnly() {
        let plan = NotificationPlanner.plan(from: fridayStart, config: config())
        let early = plan.first { $0.id == "salah.2026-09-25.dhuhr.10" }!
        XCTAssertTrue(early.body.contains("Al-Jumu‘ah 62:9"), "Jumu'ah gets 62:9")
        let atTime = plan.first { $0.id == "salah.2026-09-25.dhuhr.0" }!
        XCTAssertFalse(atTime.body.contains("—"))

        let off = NotificationPlanner.plan(from: fridayStart, config: config { $0.beforePrayer = false })
        XCTAssertFalse(off.first { $0.id == "salah.2026-09-25.dhuhr.10" }!.body.contains("—"))
    }

    func testWorkDuasWeekdaysOnly() {
        let c = config { $0.workDuas = true; $0.cadence = .off }
        // Friday, Saturday, Sunday.
        let plan = KindWordsPlanner.plan(from: fridayStart, days: 3, config: c)
        let work = plan.filter { $0.id.contains(".kind.work-") }
        XCTAssertEqual(Set(work.map(\.date)), [friday])
        XCTAssertEqual(work.count, 2)
    }

    func testQuietHoursAndPauseApply() {
        var c = config()
        c.reminders.quietHours = QuietHours(enabled: true, start: "07:00", end: "12:00")
        let plan = NotificationPlanner.plan(from: fridayStart, config: c)
        XCTAssertFalse(plan.contains { $0.id.hasSuffix("friday-kahf") })

        c.reminders.pausedUntil = Fixtures.date("2026-09-30T00:00:00+08:00")
        XCTAssertTrue(NotificationPlanner.plan(from: fridayStart, config: c).isEmpty)
    }

    func testPrayerRemindersOffStillAllowsKindWords() {
        var c = config()
        c.reminders.enabled = false
        let plan = NotificationPlanner.plan(from: fridayStart, config: c)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.prayer == nil })
    }

    func testSettingsDecodeLeniently() throws {
        let json = #"{"enabled": true, "cadence": "hourly", "afterPrayerMinutes": 7, "workStart": "25:00"}"#
        let s = try JSONDecoder().decode(KindWordsSettings.self, from: Data(json.utf8))
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.cadence, .everyFourHours)
        XCTAssertEqual(s.afterPrayerMinutes, 30)
        XCTAssertEqual(s.workStart, "09:00")
        XCTAssertTrue(s.silent)
    }

    func testConfigKeys() throws {
        var c = SalahConfig.default
        try ConfigKeys.find("kindWords.enabled").set(&c, "on")
        try ConfigKeys.find("kindWords.cadence").set(&c, "peakMoments")
        try ConfigKeys.find("kindWords.workEnd").set(&c, "18:30")
        XCTAssertTrue(c.kindWords.enabled)
        XCTAssertEqual(c.kindWords.cadence, .peakMoments)
        XCTAssertEqual(c.kindWords.workEnd, "18:30")
        XCTAssertThrowsError(try ConfigKeys.find("kindWords.afterPrayerMinutes").set(&c, "7"))
    }

    func testLibraryEntriesHaveSources() {
        let lib = KindWordsLibrary.bundled
        XCTAssertEqual(Set(lib.words.map(\.id)).count, lib.words.count)
        XCTAssertTrue(lib.words.allSatisfy { !$0.source.isEmpty && !$0.text.isEmpty })
        XCTAssertTrue(lib.duas.allSatisfy { !$0.source.isEmpty && !$0.transliteration.isEmpty })
        for cat in KindWordCategory.allCases { XCTAssertFalse(lib.words(cat).isEmpty, cat.rawValue) }
        for m in DuaMoment.allCases { XCTAssertFalse(lib.duas(m).isEmpty, m.rawValue) }
    }
}

final class SunnahFastTests: XCTestCase {
    func testMondayAndThursday() {
        // Mon 26 Oct and Thu 29 Oct 2026; Tue 27 is neither.
        // Mon 26 Oct is also 15 Jumada al-Ula, a White Day: both show.
        let monday = SunnahFast.reasons(on: LocalDate(year: 2026, month: 10, day: 26))
        XCTAssertEqual(monday, [.whiteDays, .mondayThursday])
        XCTAssertEqual(SunnahFast.tag(monday), "Sunnah fast · White day")
        XCTAssertEqual(SunnahFast.tag(SunnahFast.reasons(on: LocalDate(year: 2026, month: 10, day: 29))), "Sunnah fast")
        XCTAssertNil(SunnahFast.tag(SunnahFast.reasons(on: LocalDate(year: 2026, month: 10, day: 27))))
    }

    func testNeverInRamadanOrOnEid() {
        // Scan two years: no tag in Ramadan, on Eid al-Fitr, or 10–13 Dhu al-Hijjah.
        var d = LocalDate(year: 2026, month: 1, day: 1)
        for _ in 0..<730 {
            let h = HijriDate(d)
            let fast = SunnahFast.reasons(on: d)
            if h.month == 9 || (h.month == 10 && h.day == 1) || (h.month == 12 && (10...13).contains(h.day)) {
                XCTAssertTrue(fast.isEmpty, "\(d)")
            }
            if h.month == 12 && h.day == 9 { XCTAssertEqual(fast.first, .arafah) }
            d = d.adding(days: 1)
        }
    }
}
