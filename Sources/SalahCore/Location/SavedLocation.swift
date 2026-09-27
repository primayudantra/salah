import Foundation

public struct SavedLocation: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case automatic, manual
    }

    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// IANA identifier. All times are computed and shown in this zone, never the machine's.
    public var timeZone: String
    public var countryCode: String?
    public var source: Source

    public init(
        name: String, latitude: Double, longitude: Double, timeZone: String,
        countryCode: String? = nil, source: Source = .manual
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
        self.countryCode = countryCode
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Custom location"
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        timeZone = try c.decode(String.self, forKey: .timeZone)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
        source = try c.decodeLenient(Source.self, forKey: .source) ?? .manual
    }

    /// The location's zone; falls back to the machine zone only if the stored identifier is unknown.
    public var tz: TimeZone { TimeZone(identifier: timeZone) ?? .current }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && TimeZone(identifier: timeZone) != nil
    }

    /// e.g. "1.3521° N, 103.8198° E"
    public var coordinateDescription: String {
        let lat = String(format: "%.4f° %@", abs(latitude), latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.4f° %@", abs(longitude), longitude >= 0 ? "E" : "W")
        return "\(lat), \(lon)"
    }
}
