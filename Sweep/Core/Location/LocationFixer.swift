import CoreLocation
import Foundation

/// One-shot fix per §6.2: request When-In-Use on first use, accept the first
/// fix with horizontalAccuracy ≤ 25 m; after the soft deadline take the best
/// fix if ≤ 65 m. Field amendments to the spec's 5 s window:
/// - a cold GPS start (first grant, indoors) often needs longer than 5 s, so
///   a grace phase extends the wait to 12 s before giving up;
/// - when the user granted with Precise Location off, every fix is ~2 km and
///   would never pass — request temporary full accuracy instead of silently
///   failing to manual search.
public final class LocationFixer: NSObject, CLLocationManagerDelegate {

    public enum Outcome: Sendable {
        case fix(GeoPoint)
        case denied
        case unavailable   // timed out / too inaccurate → manual block search
    }

    static let acceptInstantlyM: Double = 25
    static let acceptAtDeadlineM: Double = 65
    static let softDeadlineSeconds: Double = 5
    static let hardDeadlineSeconds: Double = 12

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var best: CLLocation?
    private var deadline: Task<Void, Never>?
    private var inGracePhase = false

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
            inGracePhase = false
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                startUpdates()
            }
        }
    }

    private func startUpdates() {
        #if os(iOS)
        // Precise Location off → fixes are km-scale and can never pass the
        // 65 m gate. Ask for temporary full accuracy (purpose key in
        // Info.plist); updates resume with real accuracy if the user agrees.
        if manager.accuracyAuthorization == .reducedAccuracy {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "BlockFinding")
        }
        #endif
        manager.startUpdatingLocation()
        scheduleDeadline(seconds: Self.softDeadlineSeconds)
    }

    private func scheduleDeadline(seconds: Double) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.deadlineFired() }
        }
    }

    private func deadlineFired() {
        if let best, best.horizontalAccuracy <= Self.acceptAtDeadlineM {
            finish(.fix(GeoPoint(lat: best.coordinate.latitude, lon: best.coordinate.longitude)))
            return
        }
        if !inGracePhase {
            // Nothing usable yet — cold start. Keep listening a while longer.
            inGracePhase = true
            scheduleDeadline(seconds: Self.hardDeadlineSeconds - Self.softDeadlineSeconds)
            return
        }
        finish(.unavailable)
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
        guard let best else { return }
        if best.horizontalAccuracy <= Self.acceptInstantlyM {
            finish(.fix(GeoPoint(lat: best.coordinate.latitude, lon: best.coordinate.longitude)))
        } else if inGracePhase && best.horizontalAccuracy <= Self.acceptAtDeadlineM {
            // Past the soft deadline any usable fix wins — don't make the
            // user stand at the curb longer than needed.
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
