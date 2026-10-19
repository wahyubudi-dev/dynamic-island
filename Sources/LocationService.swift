import AppKit
import Combine
import CoreLocation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var placeName = ""
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let cacheKey = "island.lastCoordinate"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
        restoreCache()
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized:
            manager.requestLocation()
        default:
            break
        }
    }

    func requestLocation() {
        errorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized:
            manager.requestLocation()
        default:
            break
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        errorMessage = nil
        UserDefaults.standard.set(
            [location.coordinate.latitude, location.coordinate.longitude],
            forKey: cacheKey
        )
        resolvePlace(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    private func restoreCache() {
        guard let raw = UserDefaults.standard.array(forKey: cacheKey), raw.count == 2 else { return }
        if let values = raw as? [Double] {
            coordinate = CLLocationCoordinate2D(latitude: values[0], longitude: values[1])
        } else if let values = raw as? [NSNumber] {
            coordinate = CLLocationCoordinate2D(latitude: values[0].doubleValue, longitude: values[1].doubleValue)
        } else if let values = raw as? [String],
                  let latitude = Double(values[0]),
                  let longitude = Double(values[1]) {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        if let coordinate {
            resolvePlace(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }

    private func resolvePlace(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let place = placemarks?.first else { return }
            let city = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea ?? ""
            let country = place.country ?? ""
            let label = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
            if !label.isEmpty {
                DispatchQueue.main.async { self.placeName = label }
            }
        }
    }
}
