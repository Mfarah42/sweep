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
    }

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

        public init(segmentId: String, street: String, landmark: String?, city: City) {
            self.segmentId = segmentId
            self.street = street
            self.landmark = landmark
            self.city = city
        }
    }

    public static func plan(context: Context, windows: [SweepWindow], prefs: ReminderPrefs,
                            now: Date, calendar: Calendar) -> [Planned] {
        let targets = windows.filter { !$0.suspendedForHoliday }.prefix(2)
        var out: [Planned] = []

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
                        identifier: identifier(context.segmentId, window, .nightBefore),
                        fireDate: evening,
                        title: "Street sweeping tomorrow",
                        body: "\(place) — sweeper comes \(day) at \(hour). "
                            + "Park elsewhere tonight or move by morning.",
                        offset: .nightBefore, timeSensitive: false))
                }
            }
            if prefs.twoHours {
                let fire = window.start.addingTimeInterval(-2 * 3600)
                if fire > now {
                    out.append(Planned(
                        identifier: identifier(context.segmentId, window, .twoHours),
                        fireDate: fire,
                        title: "Move the car by \(hour)",
                        body: "\(context.street) sweeps in two hours. A ticket there is $\(fine).",
                        offset: .twoHours, timeSensitive: false))
                }
            }
            if prefs.thirtyMin {
                let fire = window.start.addingTimeInterval(-30 * 60)
                if fire > now {
                    out.append(Planned(
                        identifier: identifier(context.segmentId, window, .thirtyMin),
                        fireDate: fire,
                        title: "Last call — \(hour)",
                        body: "The sweeper is close. Move now and keep your $\(fine).",
                        offset: .thirtyMin, timeSensitive: true))
                }
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    /// `sweep.{segmentId}.{windowStartISO}.{offset}` (§8) — stable across runs.
    public static func identifier(_ segmentId: String, _ window: SweepWindow,
                                  _ offset: Offset) -> String {
        "\(identifierPrefix)\(segmentId).\(isoFormatter.string(from: window.start)).\(offset.rawValue)"
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
