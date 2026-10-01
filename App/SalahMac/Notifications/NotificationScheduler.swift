import Foundation
import SalahCore
import UserNotifications

/// Maps `NotificationPlanner` output onto `UNUserNotificationCenter`. The only place Salah schedules notifications.
@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    enum Authorization: Equatable {
        /// Running outside an app bundle (e.g. `swift run`); notifications need a bundle.
        case unavailable
        case notDetermined
        case denied
        case authorized
    }

    static let testIdentifier = "salah-test"
    static let chimeSound = UNNotificationSoundName("salah-chime.caf")

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func activate() {
        center?.delegate = self
    }

    func authorization() async -> Authorization {
        guard let center else { return .unavailable }
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    @discardableResult
    func requestAuthorization() async -> Authorization {
        guard let center else { return .unavailable }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    /// Idempotent top-up: remove every pending `salah.*` request, then add the planned window.
    /// Returns the planned notifications that were added.
    @discardableResult
    func topUp(config: SalahConfig, now: Date = Date()) async -> [PlannedNotification] {
        guard let center else { return [] }
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard await authorization() == .authorized else { return [] }
        let plan = NotificationPlanner.plan(from: now, config: config)
        guard let tz = config.location?.tz else { return [] }
        var added: [PlannedNotification] = []
        for item in plan {
            let request = UNNotificationRequest(
                identifier: item.id,
                content: content(title: item.title, body: item.body, sound: config.reminders.sound),
                trigger: trigger(for: item.fireDate, in: tz)
            )
            do {
                try await center.add(request)
                added.append(item)
            } catch {
                NSLog("Salah: failed to schedule \(item.id): \(error.localizedDescription)")
            }
        }
        return added
    }

    /// Removes the already-delivered at-time (lead 0) banner for a prayer once its Focus Mode
    /// card is shown, so the user doesn't see both.
    static func removeDeliveredAtTimeNotification(date: LocalDate, prayer: Prayer) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let id = NotificationPlanner.identifier(date: date, prayer: prayer, leadMinutes: 0)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    func removeAll() async {
        guard let center else { return }
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(NotificationPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func sendTest(title: String, body: String, sound: ReminderSound) async -> Authorization {
        var auth = await authorization()
        if auth == .notDetermined { auth = await requestAuthorization() }
        guard auth == .authorized, let center else { return auth }
        let request = UNNotificationRequest(
            identifier: Self.testIdentifier,
            content: content(title: title, body: body, sound: sound),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
        return auth
    }

    private func content(title: String, body: String, sound: ReminderSound) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.threadIdentifier = "salah"
        switch sound {
        case .systemDefault: c.sound = .default
        case .chime: c.sound = UNNotificationSound(named: Self.chimeSound)
        case .silent: c.sound = nil
        }
        return c
    }

    /// Calendar trigger in the location's zone, so it fires at the right instant even if the Mac's zone differs.
    private func trigger(for date: Date, in tz: TimeZone) -> UNCalendarNotificationTrigger {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        comps.timeZone = tz
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    // Show banners even while Salah is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
