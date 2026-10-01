import XCTest
@testable import SalahCore

final class PrayerModeConfigTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let pm = PrayerModeSettings()
        XCTAssertFalse(pm.enabled)
        XCTAssertEqual(pm.prayers, [.dhuhr, .asr, .maghrib, .isha])
        XCTAssertFalse(pm.prayers.contains(.fajr))
        XCTAssertTrue(pm.card.enabled)
        XCTAssertEqual(pm.card.autoCloseMinutes, 15)
        XCTAssertTrue(pm.pauseMedia.enabled)
        XCTAssertTrue(pm.pauseMedia.resumeOnDone)
        XCTAssertFalse(pm.focus.enabled)
        XCTAssertTrue(pm.focus.turnOffOnDone)
        XCTAssertEqual(pm.whenBusy.onCall, .nudgeThenCard)
        XCTAssertTrue(pm.whenBusy.focusIsBusy)
    }

    func testRoundTrip() throws {
        let store = ConfigStore(url: Fixtures.tempURL())
        var c = Fixtures.config(Fixtures.singapore)
        c.prayerMode.enabled = true
        c.prayerMode.prayers = [.fajr, .isha]
        c.prayerMode.card.autoCloseMinutes = 30
        c.prayerMode.whenBusy.onCall = .nudgeOnly
        try store.save(c)
        XCTAssertEqual(try store.load(), c)
    }

    func testExistingConfigWithoutPrayerModeMigratesOff() throws {
        // An older config file with no "prayerMode" key at all.
        let json = #"{"schemaVersion":1,"location":{"name":"Singapore","latitude":1.35,"longitude":103.82,"timeZone":"Asia/Singapore"}}"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertFalse(c.prayerMode.enabled)
        XCTAssertEqual(c.schemaVersion, SalahConfig.currentSchemaVersion)
    }

    func testUnknownPrayerNamesAreDroppedNotCrashed() throws {
        let json = #"{"schemaVersion":2,"prayerMode":{"prayers":["fajr","lunch","isha"]}}"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.prayerMode.prayers, [.fajr, .isha])
    }

    func testInvalidAutoCloseFallsBackToDefault() throws {
        let json = #"{"schemaVersion":2,"prayerMode":{"card":{"autoCloseMinutes":42}}}"#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.prayerMode.card.autoCloseMinutes, 15)
    }

    func testConfigKeys() throws {
        var c = SalahConfig.default
        try ConfigKeys.find("prayerMode.enabled").set(&c, "true")
        XCTAssertTrue(c.prayerMode.enabled)
        try ConfigKeys.find("prayerMode.prayers").set(&c, "fajr,asr")
        XCTAssertEqual(c.prayerMode.prayers, [.fajr, .asr])
        try ConfigKeys.find("prayerMode.card.autoCloseMinutes").set(&c, "10")
        XCTAssertEqual(c.prayerMode.card.autoCloseMinutes, 10)
        try ConfigKeys.find("prayerMode.whenBusy.onCall").set(&c, "nudgeOnly")
        XCTAssertEqual(c.prayerMode.whenBusy.onCall, .nudgeOnly)

        XCTAssertThrowsError(try ConfigKeys.find("prayerMode.card.autoCloseMinutes").set(&c, "12"))
        XCTAssertThrowsError(try ConfigKeys.find("prayerMode.prayers").set(&c, "sunrise"))
        XCTAssertThrowsError(try ConfigKeys.find("prayerMode.whenBusy.onCall").set(&c, "nope"))
    }

    func testConfigKeysPrayersPreserveCanonicalOrder() throws {
        var c = SalahConfig.default
        try ConfigKeys.find("prayerMode.prayers").set(&c, "isha,fajr,dhuhr")
        XCTAssertEqual(try ConfigKeys.find("prayerMode.prayers").get(c), "fajr,dhuhr,isha")
    }

    func testHasAnyAction() {
        var pm = PrayerModeSettings()
        pm.card.enabled = false; pm.pauseMedia.enabled = false; pm.focus.enabled = false
        XCTAssertFalse(pm.hasAnyAction)
        pm.focus.enabled = true
        XCTAssertTrue(pm.hasAnyAction)
    }
}
