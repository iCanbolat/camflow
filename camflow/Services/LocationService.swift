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

    /// A high-accuracy one-shot fix for stamping a capture as evidence. Requests
    /// `Best` accuracy and returns the raw `CLLocation` (carrying its own
    /// `timestamp`/`horizontalAccuracy`) plus whether the OS reports the fix as
    /// software-simulated. Returns nil when unauthorized or no fix arrives — the
    /// caller stamps without location (the server then grades it `unverified`).
    func verifiedFix() async -> (location: CLLocation, isSimulated: Bool)? {
        guard isAuthorized else { return nil }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        defer { manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters }
        do {
            let location = try await withCheckedThrowingContinuation { continuation in
                oneShotContinuations.append(continuation)
                manager.requestLocation()
            }
            return (location, location.isSimulatedFix)
        } catch {
            return nil
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

extension CLLocation {
    /// Whether the OS attributes this fix to software simulation (e.g. Xcode/
    /// Simulator location, or a tweaked-location tool). A mock-detection signal.
    var isSimulatedFix: Bool {
        sourceInformation?.isSimulatedBySoftware ?? false
    }
}
