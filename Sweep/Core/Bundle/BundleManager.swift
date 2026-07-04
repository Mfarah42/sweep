import CryptoKit
import Foundation

/// Owns bundle files in the App Group container (spec §4.6–4.7):
/// - copies the shipped bundles out of the app bundle on first launch and
///   after app updates (keyed by built_at) so widgets can read them,
/// - runs the opportunistic OTA refresh: index.json → download → sha256 →
///   atomic swap. All failures are silent; the app never blocks on this.
public final class BundleManager {

    /// Static host for OTA bundles (spec §4.7) — single constant. The weekly
    /// CI publishes bundles + index.json to the rolling "schedule-data"
    /// release; replace OWNER with the GitHub org/user hosting the repo.
    public static let indexURL = URL(string:
        "https://github.com/OWNER/sweep/releases/download/schedule-data/index.json")!

    public static let refreshTaskIdentifier = "com.TEAM.sweep.refresh"

    private let containerDir: URL
    private let fileManager = FileManager.default

    /// `containerDir` is the App Group container's /bundles directory in the
    /// app; tests inject a temp directory.
    public init(containerDir: URL) {
        self.containerDir = containerDir
    }

    public static func appGroup() -> BundleManager? {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PersistenceStore.appGroupId) else { return nil }
        return BundleManager(containerDir: base.appendingPathComponent("bundles", isDirectory: true))
    }

    public func bundlePath(for city: City) -> URL {
        containerDir.appendingPathComponent("\(city.rawValue).sweepbundle")
    }

    public func openBundle(for city: City) throws -> SweepBundle {
        try SweepBundle(path: bundlePath(for: city).path)
    }

    /// Copy shipped bundles into the App Group when missing or older (§4.6).
    public func installShippedBundles(from resourceBundle: Bundle) {
        try? fileManager.createDirectory(at: containerDir, withIntermediateDirectories: true)
        for city in City.allCases {
            // Shipped as .sweepdata: codesign rejects nested resources whose
            // extension ends in "bundle". Installed name stays .sweepbundle.
            guard let shipped = resourceBundle.url(forResource: city.rawValue,
                                                   withExtension: "sweepdata") else { continue }
            let installed = bundlePath(for: city)
            if let current = try? SweepBundle(path: installed.path),
               let candidate = try? SweepBundle(path: shipped.path),
               current.manifest.builtAt >= candidate.manifest.builtAt {
                continue   // installed copy is same or newer (possibly OTA-updated)
            }
            replaceAtomically(at: installed, with: shipped, copySource: true)
        }
    }

    // MARK: - OTA refresh (§4.7)

    public struct IndexEntry: Codable {
        public let built_at: String
        public let url: String
        public let sha256: String
    }

    /// Returns true when any bundle was refreshed (caller reschedules
    /// notifications and reloads widgets). Never throws — silent by design.
    public func refreshFromRemote(session: URLSession = .shared) async -> Bool {
        guard let (data, _) = try? await session.data(from: Self.indexURL),
              let index = try? JSONDecoder().decode([String: IndexEntry].self, from: data) else {
            return false
        }
        var refreshed = false
        for city in City.allCases {
            guard let entry = index[city.rawValue], let url = URL(string: entry.url) else { continue }
            let installedBuiltAt = (try? openBundle(for: city))?.manifest.builtAt ?? ""
            guard entry.built_at > installedBuiltAt else { continue }
            guard let (fileURL, _) = try? await session.download(from: url),
                  let payload = try? Data(contentsOf: fileURL) else { continue }
            let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            guard digest == entry.sha256.lowercased() else { continue }
            // Verify it opens and matches the city before swapping in.
            let staging = bundlePath(for: city).appendingPathExtension("staging")
            try? payload.write(to: staging)
            guard let candidate = try? SweepBundle(path: staging.path),
                  candidate.manifest.city == city else {
                try? fileManager.removeItem(at: staging)
                continue
            }
            replaceAtomically(at: bundlePath(for: city), with: staging, copySource: false)
            refreshed = true
        }
        return refreshed
    }

    private func replaceAtomically(at destination: URL, with source: URL, copySource: Bool) {
        let staged: URL
        if copySource {
            staged = destination.appendingPathExtension("staging")
            try? fileManager.removeItem(at: staged)
            guard (try? fileManager.copyItem(at: source, to: staged)) != nil else { return }
        } else {
            staged = source
        }
        _ = try? fileManager.replaceItemAt(destination, withItemAt: staged)
        try? fileManager.removeItem(at: staged)
    }
}
