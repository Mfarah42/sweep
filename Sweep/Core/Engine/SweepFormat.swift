import Foundation

/// UI-facing verdict state including the "nothing scheduled" case.
/// Status colors always pair with distinct text — never color alone (§7.1).
public enum VerdictStateUI: Sendable {
    case safe
    case moveSoon
    case sweepingNow
    case none

    public var word: String {
        switch self {
        case .safe: return "Safe"
        case .moveSoon: return "Move soon"
        case .sweepingNow: return "Sweeping now"
        case .none: return "No schedule"
        }
    }
}

/// Pure formatting shared by app + widgets. Lives in SweepCore so the copy
/// rules are unit-testable (§13) — the classic failure here was a footer that
/// said "Mondays" for a Mon/Wed/Fri block.
public enum SweepFormat {

    public static func hourLabel(_ date: Date, calendar: Calendar = SweepCalendar.la) -> String {
        NotificationPlanner.hourLabel(date, calendar)
    }

    public static func dayName(_ date: Date, calendar: Calendar = SweepCalendar.la) -> String {
        NotificationPlanner.dayName(date, calendar)
    }

    /// "Jul 10" — disambiguates rows that share a weekday (LA wall-clock).
    public static func shortDate(_ date: Date, calendar: Calendar = SweepCalendar.la) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(months[c.month! - 1]) \(c.day!)"
    }

    /// "6d 4h" / "14h" / "35m" countdown text.
    public static func countdown(to target: Date, from now: Date) -> String {
        let seconds = max(0, target.timeIntervalSince(now))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    /// Footer schedule line: "Tuesdays, 8–10 AM · 1st & 3rd weeks", or for
    /// multi-day rules "Mon, Wed & Fri, 2–3 AM · every week" (§7.4). Never
    /// under-describe: all weekdays of the primary window pattern are listed.
    public static func scheduleLine(rules: [ScheduleRule], calendar: Calendar = SweepCalendar.la) -> String {
        guard let first = rules.first else { return "No posted schedule" }
        // Group by identical (weeks, hours) pattern; describe the pattern the
        // first rule belongs to (extra patterns show in Coming up).
        let samePattern = rules.filter {
            $0.weeks == first.weeks && $0.fromHour == first.fromHour && $0.toHour == first.toHour
        }
        let weekdays = Array(Set(samePattern.map(\.weekday))).sorted()

        let dayText: String
        if weekdays.count == 1 {
            let full = ["Sundays", "Mondays", "Tuesdays", "Wednesdays",
                        "Thursdays", "Fridays", "Saturdays"]
            dayText = full[weekdays[0]]
        } else {
            let short = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let names = weekdays.map { short[$0] }
            dayText = names.dropLast().joined(separator: ", ") + " & " + names.last!
        }
        let hours = "\(hourText(first.fromHour))–\(hourText(first.toHour))"
        if let weeks = first.weeks {
            let ordinals = ["1st", "2nd", "3rd", "4th", "5th"]
            let label = weeks.compactMap { $0 >= 1 && $0 <= 5 ? ordinals[$0 - 1] : nil }
                .joined(separator: " & ")
            return "\(dayText), \(hours) · \(label) weeks"
        }
        return "\(dayText), \(hours) · every week"
    }

    public static func hourText(_ hour: Int) -> String {
        switch hour {
        case 0, 24: return "12 AM"
        case 12: return "12 PM"
        case ..<12: return "\(hour) AM"
        default: return "\(hour - 12) PM"
        }
    }

    public static func uiState(_ verdict: Verdict?) -> VerdictStateUI {
        guard let verdict, verdict.next != nil else { return .none }
        switch verdict.state {
        case .safe: return .safe
        case .moveSoon: return .moveSoon
        case .sweepingNow: return .sweepingNow
        }
    }

    /// Mini-verdict phrase for side cards: "safe 6d" / "sweep in 14h" / "sweeping now".
    public static func miniVerdict(_ verdict: Verdict, now: Date) -> String {
        guard let next = verdict.next else { return "no sweeping posted" }
        switch verdict.state {
        case .sweepingNow: return "sweeping now"
        case .moveSoon: return "sweep in \(countdown(to: next.start, from: now))"
        case .safe: return "safe \(countdown(to: next.start, from: now))"
        }
    }

    /// Neutral example, not a real user's address (§7.2). Oakland's data has
    /// door ranges so an address example teaches the feature; SF's doesn't,
    /// so suggest a street there.
    public static func searchPlaceholder(for city: City) -> String {
        switch city {
        case .oak: return "Address or street, e.g. 1935 Lakeshore Ave"
        case .sf: return "Street name, e.g. Irving St"
        }
    }
}
