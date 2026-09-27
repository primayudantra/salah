import CoreLocation
import Foundation

public enum LocationSearchError: Error, LocalizedError {
    case noResults(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .noResults(let q): return "No places found for “\(q)”."
        case .failed(let m): return "Location search failed: \(m)"
        }
    }
}

/// City search and reverse lookup via Apple's `CLGeocoder`. Queries are sent to Apple; nothing else leaves the Mac.
public enum LocationSearch {
    public static func search(_ query: String) async throws -> [SavedLocation] {
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await CLGeocoder().geocodeAddressString(query)
        } catch let error as CLError where error.code == .geocodeFoundNoResult {
            throw LocationSearchError.noResults(query)
        } catch {
            throw LocationSearchError.failed(error.localizedDescription)
        }
        let results = placemarks.compactMap { location(from: $0, source: .manual) }
        if results.isEmpty { throw LocationSearchError.noResults(query) }
        return results
    }

    /// Names a coordinate and finds its time zone. Returns nil when offline or nothing matches.
    public static func reverse(latitude: Double, longitude: Double, source: SavedLocation.Source) async -> SavedLocation? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        guard let p = placemarks?.first, var loc = location(from: p, source: source) else { return nil }
        loc.latitude = latitude
        loc.longitude = longitude
        return loc
    }

    static func location(from p: CLPlacemark, source: SavedLocation.Source) -> SavedLocation? {
        guard let coord = p.location?.coordinate, let tz = p.timeZone else { return nil }
        let name = p.locality ?? p.name ?? p.administrativeArea ?? p.country ?? "Custom location"
        return SavedLocation(
            name: name, latitude: coord.latitude, longitude: coord.longitude,
            timeZone: tz.identifier, countryCode: p.isoCountryCode, source: source
        )
    }

    /// A readable disambiguation line for search results, e.g. "Singapore, Singapore".
    public static func detail(for location: SavedLocation) -> String {
        "\(location.name) · \(location.timeZone) · \(location.coordinateDescription)"
    }
}
