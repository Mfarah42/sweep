import Foundation

public enum City: String, Codable, CaseIterable, Sendable {
    case sf
    case oak

    public var displayName: String {
        switch self {
        case .sf: return "San Francisco"
        case .oak: return "Oakland"
        }
    }

    /// Street-cleaning fine, whole dollars. Shown as "${fine}" across the UI.
    public var fine: Int {
        switch self {
        case .sf: return 97
        case .oak: return 66
        }
    }

    public var dataSourceName: String {
        switch self {
        case .sf: return "SFMTA via DataSF"
        case .oak: return "City of Oakland GIS"
        }
    }

    /// Holiday behavior line for Settings > About the data (§7.6).
    public var holidayBehavior: String {
        switch self {
        case .sf: return "San Francisco sweeps through most holidays."
        case .oak: return "Oakland suspends sweeping on city holidays."
        }
    }
}

public struct ScheduleRule: Codable, Hashable, Sendable {
    /// 0=Sunday … 6=Saturday
    public let weekday: Int
    /// Subset of 1…5, nil = every week.
    public let weeks: [Int]?
    /// 0…23 local wall-clock.
    public let fromHour: Int
    /// 1…24, always > fromHour (overnight windows are split by the pipeline).
    public let toHour: Int
    public let holidayEnforced: Bool

    public init(weekday: Int, weeks: [Int]?, fromHour: Int, toHour: Int, holidayEnforced: Bool) {
        self.weekday = weekday
        self.weeks = weeks
        self.fromHour = fromHour
        self.toHour = toHour
        self.holidayEnforced = holidayEnforced
    }
}

public struct SweepWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let suspendedForHoliday: Bool
    public let holidayButEnforced: Bool

    public init(start: Date, end: Date, suspendedForHoliday: Bool = false,
                holidayButEnforced: Bool = false) {
        self.start = start
        self.end = end
        self.suspendedForHoliday = suspendedForHoliday
        self.holidayButEnforced = holidayButEnforced
    }
}

public enum VerdictState: Equatable, Sendable {
    case safe
    case moveSoon
    case sweepingNow
}

public struct Verdict: Equatable, Sendable {
    public let state: VerdictState
    public let next: SweepWindow?
    public let upcoming: [SweepWindow]
}

public protocol Clock {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// Fixed or scrubbed clock for tests and the hidden demo mode (§7.6).
public struct FixedClock: Clock {
    public var now: Date
    public init(now: Date) { self.now = now }
}

public enum SweepCalendar {
    /// ALL schedule math runs in America/Los_Angeles on an explicit Gregorian
    /// calendar — never Calendar.current (spec §2 hard rule).
    public static let la: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }()
}

/// Holiday table for one city: "yyyy-MM-dd" (LA wall-clock date) → suspends.
/// Loaded from the bundle's holidays table; .empty means "no holiday data".
public struct HolidayCalendar: Sendable {
    public static let empty = HolidayCalendar(suspendsByDate: [:])

    /// date key → true when the city suspends sweeping that day.
    public let suspendsByDate: [String: Bool]

    public init(suspendsByDate: [String: Bool]) {
        self.suspendsByDate = suspendsByDate
    }

    public func suspends(onDateKey key: String) -> Bool? {
        suspendsByDate[key]
    }

    public static func dateKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
