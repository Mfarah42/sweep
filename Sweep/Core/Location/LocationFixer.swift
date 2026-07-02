import CoreLocation
import Foundation

/// One-shot fix per §6.2 input contract: request When-In-Use on first use,
/// accept the first fix with horizontalAccuracy ≤ 25 m; after 5 s take the
/// best fix if ≤ 65 m; otherwise nil → the UI falls through to manual search.
public final class LocationFixer: NSObject, CLLocationManagerDelegate {

    public enum Outcome: Sendable {
        case fix(GeoPoint)
        case denied
        case unavailable   // timed out / too inaccurate → manual block search
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var best: CLLocation?
    private var deadline: Task<Void, Never>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public func acquireFix() async -> Outcome {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            return .denied
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            best = nil
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                startUpdates()
            }
        }
    }

    private func startUpdates() {
        manager.startUpdatingLocation()
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.finishAtDeadline() }
        }
    }

    private func finishAtDeadline() {
        if let best, best.horizontalAccuracy <= 65 {
            finish(.fix(GeoPoint(lat: best.coordinate.latitude, lon: best.coordinate.longitude)))
        } else {
            finish(.unavailable)
        }
    }

    private func finish(_ outcome: Outcome) {
        manager.stopUpdatingLocation()
        deadline?.cancel()
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        case .denied, .restricted:
            finish(.denied)
        default:
            break   // .notDetermined: waiting on the prompt
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard continuation != nil else { return }
        for loc in locations where loc.horizontalAccuracy > 0 {
            if best == nil || loc.horizontalAccuracy < best!.horizontalAccuracy {
                best = loc
            }
        }
        if let best, best.horizontalAccuracy <= 25 {
            finish(.fix(GeoPoint(lat: best.coordinate.latitude, lon: best.coordinate.longitude)))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard continuation != nil else { return }
        if (error as? CLError)?.code == .denied {
            finish(.denied)
        }
    }
}
