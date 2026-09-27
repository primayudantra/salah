import Foundation
@testable import SalahCore

enum Fixtures {
    static let singapore = SavedLocation(name: "Singapore", latitude: 1.3521, longitude: 103.8198, timeZone: "Asia/Singapore", countryCode: "SG")
    static let jakarta = SavedLocation(name: "Jakarta", latitude: -6.2088, longitude: 106.8456, timeZone: "Asia/Jakarta", countryCode: "ID")
    static let mecca = SavedLocation(name: "Mecca", latitude: 21.4225, longitude: 39.8262, timeZone: "Asia/Riyadh", countryCode: "SA")
    static let newYork = SavedLocation(name: "New York", latitude: 40.7128, longitude: -74.0060, timeZone: "America/New_York", countryCode: "US")
    static let london = SavedLocation(name: "London", latitude: 51.5074, longitude: -0.1278, timeZone: "Europe/London", countryCode: "GB")
    static let oslo = SavedLocation(name: "Oslo", latitude: 59.9139, longitude: 10.7522, timeZone: "Europe/Oslo", countryCode: "NO")
    static let tromso = SavedLocation(name: "Tromsø", latitude: 69.6492, longitude: 18.9553, timeZone: "Europe/Oslo", countryCode: "NO")

    /// Parses an ISO 8601 instant, e.g. "2026-09-27T19:27:42+08:00".
    static func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: s) else { fatalError("bad fixture date \(s)") }
        return d
    }

    static func config(_ location: SavedLocation?, method: MethodID? = nil) -> SalahConfig {
        var c = SalahConfig(location: location)
        c.calculation.method = method
        c.launchAtLogin = false
        return c
    }

    static func tempURL(_ name: String = "config.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("salah-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}
