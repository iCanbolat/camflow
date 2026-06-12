import CoreLocation
import Observation

/// App-wide location access: authorization state, a continuously updated
/// last-known location (for nearest-project suggestions), and one-shot fixes.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastKnownLocation: CLLocation?

    private var oneShotContinuations: [CheckedContinuation<CLLocation, Error>] = []

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    /// One-shot fix for "Use Current Location" style actions.
    func currentLocation() async throws -> CLLocation {
        if let recent = lastKnownLocation, recent.timestamp.timeIntervalSinceNow > -30 {
            return recent
        }
        return try await withCheckedThrowingContinuation { continuation in
            oneShotContinuations.append(continuation)
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastKnownLocation = location
        let pending = oneShotContinuations
        oneShotContinuations.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let pending = oneShotContinuations
        oneShotContinuations.removeAll()
        pending.forEach { $0.resume(throwing: error) }
    }
}
