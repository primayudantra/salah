import XCTest
@testable import SalahCore

final class PrayerModePlannerTests: XCTestCase {
    let prayerTime = Fixtures.date("2026-09-27T16:01:00+08:00")
    var onTime: Date { prayerTime.addingTimeInterval(30) }

    func settings(
        enabled: Bool = true, prayers: Set<Prayer> = PrayerModeSettings.defaultPrayers,
        card: Bool = true, autoClose: Int = 15, pauseMedia: Bool = true, resumeOnDone: Bool = true,
        focus: Bool = false, turnOffOnDone: Bool = true, onCall: CallBusyMode = .nudgeThenCard, focusIsBusy: Bool = true
    ) -> PrayerModeSettings {
        PrayerModeSettings(
            enabled: enabled, prayers: prayers,
            card: PrayerModeCardSettings(enabled: card, autoCloseMinutes: autoClose),
            pauseMedia: PrayerModePauseMediaSettings(enabled: pauseMedia, resumeOnDone: resumeOnDone),
            focus: PrayerModeFocusSettings(enabled: focus, turnOffOnDone: turnOffOnDone),
            whenBusy: PrayerModeBusySettings(onCall: onCall, focusIsBusy: focusIsBusy)
        )
    }

    func context(
        prayer: Prayer = .asr, now: Date? = nil, settings s: PrayerModeSettings? = nil,
        busy: BusyState = .free, locked: Bool = false, handled: Bool = false, ownsFocus: Bool = false, note: CardNote? = nil
    ) -> PrayerModeContext {
        PrayerModeContext(
            prayer: prayer, prayerTime: prayerTime, now: now ?? onTime, settings: s ?? settings(),
            busy: busy, isScreenLocked: locked, alreadyHandled: handled, salahOwnsFocus: ownsFocus, pendingNote: note
        )
    }

    // MARK: - Nothing to do

    func testMasterOffProducesNoActions() {
        XCTAssertEqual(PrayerModePlanner.decide(context(settings: settings(enabled: false))), [])
    }

    func testPrayerNotSelectedProducesNoActions() {
        XCTAssertEqual(PrayerModePlanner.decide(context(prayer: .fajr)), [])
    }

    func testNoActionEnabledProducesNoActions() {
        let s = settings(card: false, pauseMedia: false, focus: false)
        XCTAssertEqual(PrayerModePlanner.decide(context(settings: s)), [])
    }

    func testAlreadyHandledProducesNoActions() {
        XCTAssertEqual(PrayerModePlanner.decide(context(handled: true)), [])
    }

    // MARK: - Locked

    func testLockedScreenDefers() {
        XCTAssertEqual(PrayerModePlanner.decide(context(locked: true)), [.deferUntilUnlock])
    }

    func testLockedTakesPriorityOverBusy() {
        XCTAssertEqual(PrayerModePlanner.decide(context(busy: .onCall(appName: "Zoom"), locked: true)), [.deferUntilUnlock])
    }

    // MARK: - Free: normal flow

    func testFreeRunsAllEnabledActionsInOrder() {
        let s = settings(card: true, pauseMedia: true, focus: true)
        XCTAssertEqual(PrayerModePlanner.decide(context(settings: s)), [.pauseMedia, .focusOn, .showCard(note: nil)])
    }

    func testFreeSkipsDisabledActions() {
        let s = settings(card: true, pauseMedia: false, focus: false)
        XCTAssertEqual(PrayerModePlanner.decide(context(settings: s)), [.showCard(note: nil)])
    }

    func testFreePassesThroughThePendingNote() {
        XCTAssertEqual(PrayerModePlanner.decide(context(note: .callEnded)), [.pauseMedia, .showCard(note: .callEnded)])
    }

    // MARK: - On a call

    func testOnCallWithCardLaterShowsNudgeAndDefers() {
        let s = settings(card: true, onCall: .nudgeThenCard)
        XCTAssertEqual(
            PrayerModePlanner.decide(context(settings: s, busy: .onCall(appName: "Zoom"))),
            [.showNudge(reason: .call(appName: "Zoom"), cardLater: true), .deferUntilFree]
        )
    }

    func testOnCallWithNudgeOnlyDoesNotDefer() {
        let s = settings(card: true, onCall: .nudgeOnly)
        XCTAssertEqual(
            PrayerModePlanner.decide(context(settings: s, busy: .onCall(appName: "Zoom"))),
            [.showNudge(reason: .call(appName: "Zoom"), cardLater: false)]
        )
    }

    func testOnCallWithCardOffNeverDefers() {
        let s = settings(card: false, onCall: .nudgeThenCard)
        XCTAssertEqual(
            PrayerModePlanner.decide(context(settings: s, busy: .onCall(appName: nil))),
            [.showNudge(reason: .call(appName: nil), cardLater: false)]
        )
    }

    func testOnCallNeverPausesMediaOrTurnsOnFocus() {
        let s = settings(card: true, pauseMedia: true, focus: true)
        let actions = PrayerModePlanner.decide(context(settings: s, busy: .onCall(appName: "Teams")))
        XCTAssertFalse(actions.contains(.pauseMedia))
        XCTAssertFalse(actions.contains(.focusOn))
    }

    // MARK: - Focus on

    func testFocusOnCountsAsBusyWhenFocusIsBusyTrue() {
        let s = settings(card: true, onCall: .nudgeThenCard, focusIsBusy: true)
        XCTAssertEqual(
            PrayerModePlanner.decide(context(settings: s, busy: .focusOn)),
            [.showNudge(reason: .focus, cardLater: true), .deferUntilFree]
        )
    }

    func testFocusOnIgnoredWhenFocusIsBusyFalse() {
        let s = settings(card: true, pauseMedia: true, focus: false, focusIsBusy: false)
        XCTAssertEqual(PrayerModePlanner.decide(context(settings: s, busy: .focusOn)), [.pauseMedia, .showCard(note: nil)])
    }

    func testSalahOwnedFocusNeverCountsAsBusy() {
        let s = settings(card: true, pauseMedia: true, focus: true, focusIsBusy: true)
        let actions = PrayerModePlanner.decide(context(settings: s, busy: .focusOn, ownsFocus: true))
        XCTAssertEqual(actions, [.pauseMedia, .focusOn, .showCard(note: nil)])
    }

    // MARK: - Late

    func testLateSkipsPauseAndFocusButCardStillShowsWithinAutoCloseWindow() {
        let s = settings(card: true, autoClose: 15, pauseMedia: true, focus: true)
        let late = prayerTime.addingTimeInterval(11 * 60) // 11 min late, within the 15-min auto-close window
        let actions = PrayerModePlanner.decide(context(now: late, settings: s))
        XCTAssertEqual(actions, [.showCard(note: nil)])
    }

    func testVeryLateSkipsEverything() {
        let s = settings(card: true, autoClose: 15, pauseMedia: true, focus: true)
        let veryLate = prayerTime.addingTimeInterval(20 * 60) // past the 15-min auto-close window
        XCTAssertEqual(PrayerModePlanner.decide(context(now: veryLate, settings: s)), [])
    }

    func testExactlyAtTheLateThresholdIsNotLate() {
        let s = settings(card: true, pauseMedia: true, focus: true)
        let now = prayerTime.addingTimeInterval(PrayerModePlanner.lateThreshold)
        let actions = PrayerModePlanner.decide(context(now: now, settings: s))
        XCTAssertEqual(actions, [.pauseMedia, .focusOn, .showCard(note: nil)])
    }

    func testLateWithCardOffProducesNoActions() {
        let s = settings(card: false, pauseMedia: true, focus: true)
        let veryLate = prayerTime.addingTimeInterval(20 * 60)
        XCTAssertEqual(PrayerModePlanner.decide(context(now: veryLate, settings: s)), [])
    }
}
