import XCTest
@testable import SalahCore

final class NotificationPlannerTests: XCTestCase {
    /// Just after local midnight, so all three days are fully in the future.
    let startOfDay = Fixtures.date("2026-09-27T00:00:30+08:00")

    func testThreeDayWindowCountAndCap() {
        let plan = NotificationPlanner.plan(from: startOfDay, config: Fixtures.config(Fixtures.singapore))
        // 5 prayers × (lead + at time) × 3 days.
        XCTAssertEqual(plan.count, 30)
        XCTAssertLessThanOrEqual(plan.count, NotificationPlanner.maxPending)
        XCTAssertLessThan(NotificationPlanner.maxPending, 64)
        XCTAssertEqual(Set(plan.map(\.date)).count, 3)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func testPastEntriesAreSkipped() {
        let evening = Fixtures.date("2026-09-27T19:30:00+08:00")
        let plan = NotificationPlanner.plan(from: evening, config: Fixtures.config(Fixtures.singapore))
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > evening })
        // Only Isha remains today (lead at 19:58 and at-time 20:08).
        XCTAssertEqual(plan.filter { $0.date == LocalDate(year: 2026, month: 9, day: 27) }.count, 2)
    }

    func testDeterministicIdentifiersAndIdempotentReplan() {
        let config = Fixtures.config(Fixtures.singapore)
        let a = NotificationPlanner.plan(from: startOfDay, config: config)
        let b = NotificationPlanner.plan(from: startOfDay, config: config)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a.map(\.id)).count, a.count, "duplicate identifiers")
        XCTAssertTrue(a.contains { $0.id == "salah.2026-09-27.asr.10" })
        XCTAssertTrue(a.contains { $0.id == "salah.2026-09-27.asr.0" })
        XCTAssertTrue(a.allSatisfy { $0.id.hasPrefix(NotificationPlanner.idPrefix) })
    }

    func testQuietHoursExcludeEntries() {
        var config = Fixtures.config(Fixtures.singapore)
        config.reminders.quietHours = QuietHours(enabled: true, start: "04:00", end: "06:00")
        let plan = NotificationPlanner.plan(from: startOfDay, config: config)
        // Fajr (≈05:36) and its 15-minute lead fall inside, every day.
        XCTAssertFalse(plan.contains { $0.prayer == .fajr })
        XCTAssertEqual(plan.count, 24)
    }

    func testQuietHoursWrapPastMidnight() {
        let q = QuietHours(enabled: true, start: "23:00", end: "04:30")
        XCTAssertTrue(q.contains(minuteOfDay: 23 * 60 + 30))
        XCTAssertTrue(q.contains(minuteOfDay: 60))
        XCTAssertFalse(q.contains(minuteOfDay: 4 * 60 + 30))
        XCTAssertFalse(QuietHours(enabled: false, start: "23:00", end: "04:30").contains(minuteOfDay: 60))
    }

    func testPauseExcludesUntilItEnds() {
        var config = Fixtures.config(Fixtures.singapore)
        let until = Fixtures.date("2026-09-28T00:00:00+08:00")
        config.reminders.pausedUntil = until
        let plan = NotificationPlanner.plan(from: startOfDay, config: config)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate >= until })
        XCTAssertEqual(plan.count, 20)
    }

    func testDisabledPrayerAndGlobalSwitch() {
        var config = Fixtures.config(Fixtures.singapore)
        config.reminders.update(.asr) { $0.enabled = false }
        XCTAssertFalse(NotificationPlanner.plan(from: startOfDay, config: config).contains { $0.prayer == .asr })
        config.reminders.enabled = false
        XCTAssertTrue(NotificationPlanner.plan(from: startOfDay, config: config).isEmpty)
        XCTAssertTrue(NotificationPlanner.plan(from: startOfDay, config: Fixtures.config(nil)).isEmpty)
    }

    func testLeadOnlyAndAtTimeOnly() {
        var config = Fixtures.config(Fixtures.singapore)
        for p in Prayer.prayers { config.reminders.update(p) { $0.atTime = false } }
        XCTAssertTrue(NotificationPlanner.plan(from: startOfDay, config: config).allSatisfy { $0.leadMinutes > 0 })
        for p in Prayer.prayers { config.reminders.update(p) { $0.atTime = true; $0.leadMinutes = 0 } }
        let plan = NotificationPlanner.plan(from: startOfDay, config: config)
        XCTAssertEqual(plan.count, 15)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate == $0.prayerTime })
    }

    func testChangingInputsChangesFireDates() {
        let base = NotificationPlanner.plan(from: startOfDay, config: Fixtures.config(Fixtures.singapore, method: .singapore))
        var offset = Fixtures.config(Fixtures.singapore, method: .singapore)
        offset.calculation.setOffset(2, for: .isha)
        var method = Fixtures.config(Fixtures.singapore, method: .muslimWorldLeague)
        method.calculation.madhab = .hanafi
        let moved = Fixtures.config(Fixtures.jakarta, method: .singapore)

        func fire(_ plan: [PlannedNotification], _ id: String) -> Date? { plan.first { $0.id == id }?.fireDate }
        let isha = "salah.2026-09-28.isha.0", fajr = "salah.2026-09-28.fajr.0"
        XCTAssertNotEqual(fire(base, isha), fire(NotificationPlanner.plan(from: startOfDay, config: offset), isha))
        XCTAssertEqual(fire(base, fajr), fire(NotificationPlanner.plan(from: startOfDay, config: offset), fajr))
        XCTAssertNotEqual(fire(base, fajr), fire(NotificationPlanner.plan(from: startOfDay, config: method), fajr))
        XCTAssertNotEqual(fire(base, fajr), fire(NotificationPlanner.plan(from: startOfDay, config: moved), fajr))
    }

    func testCopyAndJumuah() {
        let friday = Fixtures.date("2026-09-25T00:00:30+08:00")
        let plan = NotificationPlanner.plan(from: friday, config: Fixtures.config(Fixtures.singapore))
        let lead = plan.first { $0.id == "salah.2026-09-25.dhuhr.10" }!
        XCTAssertEqual(lead.title, "Jumu'ah in 10 minutes")
        XCTAssertEqual(lead.body, "12:58 · Singapore")
        let asr = plan.first { $0.id == "salah.2026-09-25.asr.0" }!
        XCTAssertEqual(asr.title, "Time for Asr")

        var twelve = Fixtures.config(Fixtures.singapore)
        twelve.display.use24HourClock = false
        let asrLead = NotificationPlanner.plan(from: friday, config: twelve).first { $0.id == "salah.2026-09-25.asr.10" }!
        XCTAssertEqual(asrLead.title, "Asr in 10 minutes")
        XCTAssertEqual(asrLead.body, "4:01 PM · Singapore")
    }
}
