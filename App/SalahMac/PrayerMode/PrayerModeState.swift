import Foundation
import SalahCore

/// Runtime state for Prayer Mode: which prayer was last handled, what's paused, whether Salah
/// turned a Focus on, and a pending deferred card. Lives in `state.json`, next to `config.json` —
/// never in the shared config, since the CLI has no business reading or writing it.
struct PrayerModeState: Codable, Equatable {
    /// `<yyyy-MM-dd>.<prayer>` of the last prayer whose at-time actions already ran.
    var lastHandledID: String?
    /// Bundle IDs Salah paused and should resume on Done.
    var pausedApps: Set<String> = []
    /// True while the active Focus was turned on by Salah (not the user).
    var salahTurnedFocusOn: Bool = false
    /// How many times the current card has been snoozed, reset once it's handled.
    var snoozeCount: Int = 0
    /// A prayer waiting to show its card once the user is free (`<yyyy-MM-dd>.<prayer>`).
    var pendingPrayerID: String?
    var pendingNote: CardNote?

    static let empty = PrayerModeState()
}

/// Reads and atomically writes `state.json` beside the shared config.
struct PrayerModeStateStore {
    let url: URL

    init(configURL: URL) {
        url = configURL.deletingLastPathComponent().appendingPathComponent("state.json")
    }

    func load() -> PrayerModeState {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(PrayerModeState.self, from: data)) ?? .empty
    }

    func save(_ state: PrayerModeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".state-\(UUID().uuidString).tmp")
        guard (try? data.write(to: tmp)) != nil else { return }
        if rename(tmp.path, url.path) != 0 { try? FileManager.default.removeItem(at: tmp) }
    }

    @discardableResult
    func update(_ body: (inout PrayerModeState) -> Void) -> PrayerModeState {
        var s = load()
        body(&s)
        save(s)
        return s
    }
}

/// `<yyyy-MM-dd>.<prayer>`, the dedup key used throughout Prayer Mode.
func prayerHandledID(_ date: LocalDate, _ prayer: Prayer) -> String { "\(date).\(prayer.rawValue)" }
