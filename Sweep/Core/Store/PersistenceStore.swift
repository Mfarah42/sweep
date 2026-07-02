import Foundation

/// App Group persistence map (spec §10). UserDefaults-backed, injectable for
/// tests. All keys are versioned.
public final class PersistenceStore {

    public enum Keys {
        public static let session = "parking.session.v1"
        public static let reminders = "prefs.reminders.v1"
        public static let city = "prefs.city.v1"
        public static let overrides = "overrides.v1"
        public static let plus = "purchase.plus.v1"
    }

    public static let appGroupId = "group.com.TEAM.sweep"   // single-config placeholder

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// App Group suite in the real app; falls back to standard for previews.
    public static func appGroup() -> PersistenceStore {
        PersistenceStore(defaults: UserDefaults(suiteName: appGroupId) ?? .standard)
    }

    // MARK: - Parking session

    public var session: ParkingSession? {
        get { read(Keys.session) }
        set { write(Keys.session, newValue) }
    }

    // MARK: - Prefs

    public var reminderPrefs: ReminderPrefs {
        get { read(Keys.reminders) ?? ReminderPrefs() }
        set { write(Keys.reminders, newValue) }
    }

    public var city: City {
        get { City(rawValue: defaults.string(forKey: Keys.city) ?? "") ?? .sf }
        set { defaults.set(newValue.rawValue, forKey: Keys.city) }
    }

    // MARK: - Sign corrections (§7.5)

    public var overrides: [String: ScheduleRuleOverride] {
        get { read(Keys.overrides) ?? [:] }
        set { write(Keys.overrides, newValue) }
    }

    // MARK: - Plus (mirror only; StoreKit is source of truth, §10)

    public var hasPlus: Bool {
        get { defaults.bool(forKey: Keys.plus) }
        set { defaults.set(newValue, forKey: Keys.plus) }
    }

    // MARK: - Codable plumbing

    private func read<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ key: String, _ value: T?) {
        if let value, let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public struct ParkingSession: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case gps
        case manual
    }

    public let segmentId: String
    public let blockId: String
    public let sideKey: String
    public let parkedAt: Date
    public let source: Source

    public init(segmentId: String, blockId: String, sideKey: String,
                parkedAt: Date, source: Source) {
        self.segmentId = segmentId
        self.blockId = blockId
        self.sideKey = sideKey
        self.parkedAt = parkedAt
        self.source = source
    }
}

public struct ReminderPrefs: Codable, Equatable, Sendable {
    public var nightBefore: Bool
    public var twoHours: Bool
    public var thirtyMin: Bool

    public init(nightBefore: Bool = true, twoHours: Bool = true, thirtyMin: Bool = true) {
        self.nightBefore = nightBefore
        self.twoHours = twoHours
        self.thirtyMin = thirtyMin
    }
}
