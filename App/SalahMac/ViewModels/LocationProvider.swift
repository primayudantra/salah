import CoreLocation
import Foundation
import SalahCore

/// One-shot current location. Permission is requested only when the user taps "Use my location".
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    @Published private(set) var isLocating = false
    @Published var errorMessage: String?

    var onLocation: ((SavedLocation) -> Void)?

    private let manager = CLLocationManager()
    private var wantsLocation = false

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { status == .denied || status == .restricted }

    func requestLocation() {
        errorMessage = nil
        wantsLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            wantsLocation = false
            errorMessage = "Location access is off for Salah."
        default:
            isLocating = true
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            guard self.wantsLocation else { return }
            if s == .authorizedAlways {
                self.isLocating = true
                self.manager.requestLocation()
            } else if s == .denied || s == .restricted {
                self.wantsLocation = false
                self.errorMessage = "Location access is off for Salah."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            guard self.wantsLocation else { return }
            self.wantsLocation = false
            let found = await LocationSearch.reverse(latitude: c.latitude, longitude: c.longitude, source: .automatic)
            // Offline: the Mac's zone is a reasonable guess for where the Mac physically is.
            let loc = found ?? SavedLocation(
                name: "Current location", latitude: c.latitude, longitude: c.longitude,
                timeZone: TimeZone.current.identifier, source: .automatic
            )
            self.isLocating = false
            self.onLocation?(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLocating = false
            self.wantsLocation = false
            self.errorMessage = "Couldn't get your location. Try again or enter it manually."
        }
    }
}
