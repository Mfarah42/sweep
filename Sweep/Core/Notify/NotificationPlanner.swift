import Foundation

/// Pure notification planning (spec §8): next 2 non-suspended windows ×
/// enabled offsets, deterministic identifiers so rescheduling is idempotent —
/// the scheduler removes everything with the `sweep.` prefix and re-adds.
public enum NotificationPlanner {

    public static let identifierPrefix = "sweep."

    public enum Offset: String, CaseIterable, Sendable {
        case nightBefore = "evening"
        case twoHours = "2h"
        case thirtyMin = "30m"
        case allClear = "clear"
        case threeDay = "72h"
    }

    /// SF and Oakland enforce a 72-hour limit in one spot; warn with a
    /// 4-hour head start.
    public static let threeDayWarningHours: Double = 68

    public struct Planned: Equatable, Sendable {
        public let identifier: String
        public let fireDate: Date
        public let title: String
        public let body: String
        public let offset: Offset
        public let timeSensitive: Bool

        public init(identifier: String, fireDate: Date, title: String, body: String,
                    offset: Offset, timeSensitive: Bool) {
            self.identifier = identifier
            self.fireDate = fireDate
            self.title = title
            self.body = body
            self.offset = offset
            self.timeSensitive = timeSensitive
        }
    }

    public struct Context: Sendable {
        public let segmentId: String
        public let street: String
        public let landmark: String?
        public let city: City
        /// Distinguishes cars parked on the same segment (multi-car): folded
        /// into identifiers so two cars' alerts never collide.
        public let sessionKey: String
        /// "the Civic" — prefixes copy when the household has several cars.
        public let carName: String?

        public init(segmentId: String, street: String, landmark: String?, city: City,
                    sessionKey: String = "", carName: String? = nil) {
            self.segmentId = segmentId
            self.street = street
            self.landmark = landmark
            self.city = city
            self.sessionKey = sessionKey
            self.carName = carName
        }
    }

    public static func plan(context: Context, windows: [SweepWindow], prefs: ReminderPrefs,
                            now: Date, calendar: Calendar,
                            parkedAt: Date? = nil) -> [Planned] {
        let nonSuspended = windows.filter { !$0.suspendedForHoliday }
        let targets = nonSuspended.prefix(2)
        var out: [Planned] = []
        // Multi-car: name the car in every body so alerts are unambiguous.
        let carTag = context.carName.map { "\($0): " } ?? ""

        // "All clear" at the end of the next window — take your spot back.
        if prefs.allClear, let next = nonSuspended.first, next.end > now {
            let following = nonSuspended.first { $0.start > next.end }
            let untilText = following.map {
                " The spot is fair game until \(dayName($0.start, calendar)) "
                    + "\(hourLabel($0.start, calendar))."
            } ?? ""
            out.append(Planned(
                identifier: identifier(context, next, .allClear),
                fireDate: next.end,
                title: "All clear on \(context.street)",
                body: "\(carTag)Sweeping's done.\(untilText)",
                offset: .allClear, timeSensitive: false))
        }

        // 72-hour rule: both cities can ticket or tow after three days in
        // one spot, sweeping or not.
        if prefs.threeDayRule, let parkedAt {
            let fire = parkedAt.addingTimeInterval(threeDayWarningHours * 3600)
            if fire > now {
                out.append(Planned(
                    identifier: "\(identifierPrefix)\(context.sessionKey)\(context.segmentId)."
                        + "\(isoFormatter.string(from: parkedAt)).\(Offset.threeDay.rawValue)",
                    fireDate: fire,
                    title: "Three days in one spot",
                    body: "\(context.city.displayName) can ticket or tow after "
                        + "72 hours. \(context.carName.map { "The \($0)" } ?? "The car")'s "
                        + "been on \(context.street) since \(dayName(parkedAt, calendar)).",
                    offset: .threeDay, timeSensitive: false))
            }
        }

        for window in targets {
            let day = dayName(window.start, calendar)
            let hour = hourLabel(window.start, calendar)
            let place = context.landmark.map { "\(context.street), \($0.lowercased())" }
                ?? context.street
            let fine = context.city.fine

            if prefs.nightBefore {
                // Evening before, 8 PM local; skip if that is after the start.
                if let eveningDay = calendar.date(byAdding: .day, value: -1, to: window.start),
                   let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0,
                                               of: eveningDay),
                   evening < window.start, evening > now {
                    out.append(Planned(
                        identifier: identifier(context, window, .nightBefore),
                        fireDate: evening,
                        title: "Street sweeping tomorrow",
                        body: "\(carTag)\(place) — sweeper comes \(day) at \(hour). "
                            + "Park elsewhere tonight or move by morning.",
                        offset: .nightBefore, timeSensitive: false))
                }
            }
            if prefs.twoHours {
                let fire = window.start.addingTimeInterval(-2 * 3600)
                if fire > now {
                    out.append(Planned(
                        identifier: identifier(context, window, .twoHours),
                        fireDate: fire,
                        title: "Move \(context.carName ?? "the car") by \(hour)",
                        body: "\(context.street) sweeps in two hours. A ticket there is $\(fine).",
                        offset: .twoHours, timeSensitive: false))
                }
            }
            if prefs.thirtyMin {
                let fire = window.start.addingTimeInterval(-30 * 60)
                if fire > now {
                    out.append(Planned(
                        identifier: identifier(context, window, .thirtyMin),
                        fireDate: fire,
                        title: "Last call — \(hour)",
                        body: "\(carTag)The sweeper is close. Move now and keep your $\(fine).",
                        offset: .thirtyMin, timeSensitive: true))
                }
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    /// `sweep.{sessionKey}{segmentId}.{windowStartISO}.{offset}` (§8) —
    /// stable across runs, unique per car.
    public static func identifier(_ context: Context, _ window: SweepWindow,
                                  _ offset: Offset) -> String {
        "\(identifierPrefix)\(context.sessionKey)\(context.segmentId)."
            + "\(isoFormatter.string(from: window.start)).\(offset.rawValue)"
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func dayName(_ date: Date, _ calendar: Calendar) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[calendar.component(.weekday, from: date) - 1]
    }

    public static func hourLabel(_ date: Date, _ calendar: Calendar) -> String {
        let h = calendar.component(.hour, from: date)
        switch h {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case ..<12: return "\(h) AM"
        default: return "\(h - 12) PM"
        }
    }
}
