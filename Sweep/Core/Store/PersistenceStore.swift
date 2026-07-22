import Foundation

/// App Group persistence map (spec §10). UserDefaults-backed, injectable for
/// tests. All keys are versioned.
public final class PersistenceStore {

    public enum Keys {
        public static let session = "parking.session.v1"
        public static let sessions = "parking.sessions.v2"
        public static let reminders = "prefs.reminders.v1"
        public static let city = "prefs.city.v1"
        public static let overrides = "overrides.v1"
        public static let plus = "purchase.plus.v1"
        public static let appleReminders = "prefs.appleReminders.v1"
        public static let appleReminderId = "reminders.ekid.v1"
        public static let appearance = "prefs.appearance.v1"
        public static let garbageDay = "prefs.garbageDay.v1"
    }

    public static let appGroupId = "group.com.TEAM.sweep"   // single-config placeholder

    private let defaults: UserDefaults
    /// Test hook for migration assertions on raw keys.
    public var defaultsForTesting: UserDefaults { defaults }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// App Group suite in the real app; falls back to standard for previews.
    public static func appGroup() -> PersistenceStore {
        PersistenceStore(defaults: UserDefaults(suiteName: appGroupId) ?? .standard)
    }

    // MARK: - Parking sessions (multi-car since v2)

    /// All parked cars. Reads migrate a v1 single session transparently;
    /// writes go to v2 and clear the legacy key.
    public var sessions: [ParkingSession] {
        get {
            if let v2: [ParkingSession] = read(Keys.sessions) { return v2 }
            if let v1: ParkingSession = read(Keys.session) { return [v1] }
            return []
        }
        set {
            write(Keys.sessions, newValue.isEmpty ? nil : newValue)
            defaults.removeObject(forKey: Keys.session)
        }
    }

    /// Legacy single-session view — the first car. Kept for callers that
    /// only care whether anything is parked.
    public var session: ParkingSession? {
        get { sessions.first }
        set {
            if let newValue {
                sessions = [newValue]
            } else {
                sessions = []
            }
        }
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

    public var appearance: AppearancePref {
        get { AppearancePref(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.appearance) }
    }

    /// Garbage pickup weekday, 0=Sunday…6=Saturday; nil = not set. A weekly
    /// constant the user enters once — no city feed required (WM/Recology
    /// publish no open data here).
    public var garbageDay: Int? {
        get {
            defaults.object(forKey: Keys.garbageDay) == nil
                ? nil : defaults.integer(forKey: Keys.garbageDay)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.garbageDay)
            } else {
                defaults.removeObject(forKey: Keys.garbageDay)
            }
        }
    }

    /// Opt-in mirror of the move-by deadline into the Apple Reminders app.
    public var appleRemindersEnabled: Bool {
        get { defaults.bool(forKey: Keys.appleReminders) }
        set { defaults.set(newValue, forKey: Keys.appleReminders) }
    }

    /// EventKit identifier of the one Sweep-managed reminder.
    public var appleReminderId: String? {
        get { defaults.string(forKey: Keys.appleReminderId) }
        set { defaults.set(newValue, forKey: Keys.appleReminderId) }
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

public struct ParkingSession: Codable, Equatable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case gps
        case manual
    }

    /// Stable identity for the multi-car UI and per-car notification ids.
    /// Sessions saved before v2 get one on first decode and keep it once
    /// re-persisted.
    public let id: UUID
    public let segmentId: String
    public let blockId: String
    public let sideKey: String
    public let parkedAt: Date
    public let source: Source
    /// "Both sides" resident mode: a second segment on the same block whose
    /// windows are watched too. Optional so v1 sessions keep decoding.
    public var secondarySegmentId: String?
    /// Sweep Plus multi-car: "the Civic". nil = the (only) car.
    public var carName: String?

    public init(id: UUID = UUID(), segmentId: String, blockId: String, sideKey: String,
                parkedAt: Date, source: Source, secondarySegmentId: String? = nil,
                carName: String? = nil) {
        self.id = id
        self.segmentId = segmentId
        self.blockId = blockId
        self.sideKey = sideKey
        self.parkedAt = parkedAt
        self.source = source
        self.secondarySegmentId = secondarySegmentId
        self.carName = carName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        segmentId = try c.decode(String.self, forKey: .segmentId)
        blockId = try c.decode(String.self, forKey: .blockId)
        sideKey = try c.decode(String.self, forKey: .sideKey)
        parkedAt = try c.decode(Date.self, forKey: .parkedAt)
        source = try c.decode(Source.self, forKey: .source)
        secondarySegmentId = try c.decodeIfPresent(String.self, forKey: .secondarySegmentId)
        carName = try c.decodeIfPresent(String.self, forKey: .carName)
    }

    public var segmentIds: [String] {
        [segmentId] + (secondarySegmentId.map { [$0] } ?? [])
    }

    public var watchesBothSides: Bool {
        secondarySegmentId != nil
    }

    /// "the Civic" / "your car" for running copy.
    public var displayCarName: String {
        carName ?? "your car"
    }

    /// Short stable key for notification identifiers.
    public var notificationKey: String {
        String(id.uuidString.prefix(8))
    }
}

/// System-following by default; Light keeps the paper brand permanent.
public enum AppearancePref: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public struct ReminderPrefs: Codable, Equatable, Sendable {
    public var nightBefore: Bool
    public var twoHours: Bool
    public var thirtyMin: Bool
    /// "All clear" when the sweep window ends — take your spot back.
    public var allClear: Bool
    /// SF and Oakland can ticket/tow after 72 hours in one spot.
    public var threeDayRule: Bool

    public init(nightBefore: Bool = true, twoHours: Bool = true, thirtyMin: Bool = true,
                allClear: Bool = true, threeDayRule: Bool = true) {
        self.nightBefore = nightBefore
        self.twoHours = twoHours
        self.thirtyMin = thirtyMin
        self.allClear = allClear
        self.threeDayRule = threeDayRule
    }

    /// Tolerant decode: prefs saved by older versions lack the new keys —
    /// they default on rather than nuking the user's existing toggles.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nightBefore = try c.decodeIfPresent(Bool.self, forKey: .nightBefore) ?? true
        twoHours = try c.decodeIfPresent(Bool.self, forKey: .twoHours) ?? true
        thirtyMin = try c.decodeIfPresent(Bool.self, forKey: .thirtyMin) ?? true
        allClear = try c.decodeIfPresent(Bool.self, forKey: .allClear) ?? true
        threeDayRule = try c.decodeIfPresent(Bool.self, forKey: .threeDayRule) ?? true
    }
}
