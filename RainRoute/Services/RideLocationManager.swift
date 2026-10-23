import CoreLocation
import Foundation

/// Thin wrapper around `CLLocationManager` for foreground ride tracking.
///
/// Delegate callbacks are forwarded on the main actor through the stored
/// closures. Background location is deliberately not enabled.
final class RideLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var onLocation: (@MainActor (GeoCoordinate, Double) -> Void)?
    var onAuthorization: (@MainActor (CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    static var locationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let callback = onAuthorization
        Task { @MainActor in
            callback?(status)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let age = Date().timeIntervalSince(location.timestamp)
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100,
              age >= -5,
              age <= 30 else {
            return
        }

        let coordinate = GeoCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let accuracy = location.horizontalAccuracy
        let callback = onLocation
        Task { @MainActor in
            callback?(coordinate, accuracy)
        }
    }
}
