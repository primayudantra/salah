import Adhan
import XCTest
@testable import SalahCore

final class CalculationTests: XCTestCase {
    /// Our wrapper must reproduce adhan-swift exactly (±1 min) for each supported method and city.
    func testMatchesLibraryAcrossCitiesAndDates() {
        let cases: [(SavedLocation, MethodID, CalculationMethod)] = [
            (Fixtures.singapore, .singapore, .singapore),
            (Fixtures.mecca, .ummAlQura, .ummAlQura),
            (Fixtures.newYork, .northAmerica, .northAmerica),
            (Fixtures.london, .muslimWorldLeague, .muslimWorldLeague),
            (Fixtures.oslo, .muslimWorldLeague, .muslimWorldLeague),
        ]
        let dates = [LocalDate(year: 2026, month: 1, day: 15), LocalDate(year: 2026, month: 3, day: 20),
                     LocalDate(year: 2026, month: 6, day: 21), LocalDate(year: 2026, month: 9, day: 27)]
        for (loc, id, adhan) in cases {
            var settings = CalculationSettings()
            settings.method = id
            for d in dates {
                let ours = PrayerSchedule.for(date: d, location: loc, settings: settings)
                let theirs = PrayerTimes(coordinates: Coordinates(latitude: loc.latitude, longitude: loc.longitude),
                                         date: d.components, calculationParameters: adhan.params)
                guard let theirs else {
                    XCTAssertTrue(ours.times.isEmpty, "\(loc.name) \(d): library undefined but we produced times")
                    continue
                }
                let pairs: [(SalahCore.Prayer, Date)] = [(.fajr, theirs.fajr), (.sunrise, theirs.sunrise), (.dhuhr, theirs.dhuhr),
                                               (.asr, theirs.asr), (.maghrib, theirs.maghrib), (.isha, theirs.isha)]
                for (p, expected) in pairs {
                    guard let got = ours.time(p) else { return XCTFail("\(loc.name) \(d) \(p) missing") }
                    XCTAssertEqual(got.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 60, "\(loc.name) \(d) \(p)")
                }
            }
        }
    }

    func testJakartaCustomAnglesMatchKemenag() {
        var settings = CalculationSettings()
        settings.method = .custom
        settings.customFajrAngle = 20
        settings.customIshaAngle = 18
        let d = LocalDate(year: 2026, month: 9, day: 27)
        let ours = PrayerSchedule.for(date: d, location: Fixtures.jakarta, settings: settings)

        var params = CalculationMethod.other.params
        params.fajrAngle = 20
        params.ishaAngle = 18
        let theirs = PrayerTimes(coordinates: Coordinates(latitude: Fixtures.jakarta.latitude, longitude: Fixtures.jakarta.longitude),
                                 date: d.components, calculationParameters: params)!
        XCTAssertEqual(ours.time(.fajr)!.timeIntervalSince1970, theirs.fajr.timeIntervalSince1970, accuracy: 60)
        XCTAssertEqual(ours.time(.isha)!.timeIntervalSince1970, theirs.isha.timeIntervalSince1970, accuracy: 60)
        XCTAssertEqual(ours.methodName, "Custom (20° / 18°)")
    }

    func testSingaporeKnownValues() {
        // Reference output of adhan-swift 1.4.0, MUIS, 28 Sep 2026.
        let s = PrayerSchedule.for(date: LocalDate(year: 2026, month: 9, day: 28), location: Fixtures.singapore, settings: CalculationSettings(method: .singapore))
        let expected: [SalahCore.Prayer: String] = [.fajr: "05:36", .sunrise: "06:53", .dhuhr: "12:57", .asr: "16:02", .maghrib: "18:59", .isha: "20:08"]
        for (p, t) in expected {
            XCTAssertEqual(TimeFormatting.clock(s.time(p)!, in: Fixtures.singapore.tz, use24Hour: true), t, "\(p)")
        }
    }

    func testOffsetsApplyPerPrayer() {
        let d = LocalDate(year: 2026, month: 9, day: 27)
        let base = PrayerSchedule.for(date: d, location: Fixtures.singapore, settings: CalculationSettings(method: .singapore))
        var s = CalculationSettings(method: .singapore)
        s.setOffset(3, for: .isha)
        s.setOffset(-2, for: .fajr)
        let adjusted = PrayerSchedule.for(date: d, location: Fixtures.singapore, settings: s)
        XCTAssertEqual(adjusted.time(.isha)!.timeIntervalSince(base.time(.isha)!), 180, accuracy: 60)
        XCTAssertEqual(adjusted.time(.fajr)!.timeIntervalSince(base.time(.fajr)!), -120, accuracy: 60)
        XCTAssertEqual(adjusted.time(.asr), base.time(.asr))
        XCTAssertEqual(adjusted.time(.dhuhr), base.time(.dhuhr))
    }

    func testMadhabMovesAsrLater() {
        let d = LocalDate(year: 2026, month: 9, day: 27)
        let shafi = PrayerSchedule.for(date: d, location: Fixtures.london, settings: CalculationSettings(madhab: .shafi))
        let hanafi = PrayerSchedule.for(date: d, location: Fixtures.london, settings: CalculationSettings(madhab: .hanafi))
        XCTAssertGreaterThan(hanafi.time(.asr)!, shafi.time(.asr)!)
    }

    func testPolarDayIsUndefinedNotACrash() {
        let s = PrayerSchedule.for(date: LocalDate(year: 2026, month: 6, day: 21), location: Fixtures.tromso, settings: CalculationSettings())
        XCTAssertTrue(s.times.isEmpty)
        XCTAssertEqual(s.undefined, Prayer.allCases)
        XCTAssertNotNil(s.undefinedExplanation)
        // The resolver looks ahead but never invents a time.
        let next = NextPrayerResolver.resolve(now: Fixtures.date("2026-06-21T12:00:00+02:00"), location: Fixtures.tromso, settings: CalculationSettings())
        XCTAssertNil(next)
    }

    func testHighLatitudeRuleChangesOsloSummerIsha() {
        let d = LocalDate(year: 2026, month: 6, day: 21)
        var mid = CalculationSettings(); mid.highLatitudeRule = .middleOfTheNight
        var seventh = CalculationSettings(); seventh.highLatitudeRule = .seventhOfTheNight
        let a = PrayerSchedule.for(date: d, location: Fixtures.oslo, settings: mid)
        let b = PrayerSchedule.for(date: d, location: Fixtures.oslo, settings: seventh)
        XCTAssertNotEqual(a.time(.isha), b.time(.isha))
    }

    func testAutomaticMethodPicksMUISInSingapore() {
        XCTAssertEqual(MethodID.automatic(for: Fixtures.singapore), .singapore)
        XCTAssertEqual(MethodID.automatic(for: Fixtures.london), .muslimWorldLeague)
        XCTAssertEqual(MethodID.automatic(for: nil), .muslimWorldLeague)
    }
}
