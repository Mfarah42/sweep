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

    // MARK: - Sign preview

    /// The lines a posted street-sweeping sign would carry for these rules,
    /// e.g. ["9 AM – 12 PM", "2ND & 4TH FRI"] — rendered in the UI as a mini
    /// sign so users can eyeball-match the physical pole. Describes the first
    /// rule's pattern (same convention as scheduleLine).
    public static func signLines(rules: [ScheduleRule]) -> [String] {
        guard let first = rules.first else { return [] }
        let samePattern = rules.filter {
            $0.weeks == first.weeks && $0.fromHour == first.fromHour && $0.toHour == first.toHour
        }
        let weekdays = Array(Set(samePattern.map(\.weekday))).sorted()
        let short = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        let names = weekdays.map { short[$0] }
        let dayText = names.count == 1 ? names[0]
            : names.dropLast().joined(separator: ", ") + " & " + names.last!

        var dayLine = dayText
        if let weeks = first.weeks {
            let ordinals = ["1ST", "2ND", "3RD", "4TH", "5TH"]
            let label = weeks.compactMap { $0 >= 1 && $0 <= 5 ? ordinals[$0 - 1] : nil }
                .joined(separator: " & ")
            dayLine = "\(label) \(dayText)"
        }
        return ["\(hourText(first.fromHour)) – \(hourText(first.toHour))", dayLine]
    }

    // MARK: - Side naming

    /// What we call a curb side. Door parity is the only thing a person can
    /// verify instantly by looking at the house next to the car, so it leads
    /// whenever the data has it — "Airport side" only means "the side facing
    /// the airport direction," which nobody can feel standing on the block.
    /// Curated editorial names win (they reference things you can see);
    /// parity-less sides (SF) fall back to the landmark name.
    public static func sideTitle(parity: String?, landmark: String?,
                                 confidence: String?) -> String {
        if confidence == "editorial", let landmark {
            return landmark
        }
        if let parity, parity == "even" || parity == "odd" {
            return "\(parity.capitalized) side"
        }
        return landmark ?? "This side"
    }

    /// Secondary cue under the title. Arterial hints ("toward MacArthur
    /// Blvd") and editorial hints describe something visible from the block,
    /// so they stay; bare compass-derived geo names (Airport/Berkeley) don't
    /// help on the spot and are dropped when parity already leads.
    public static func sideBackup(parity: String?, landmark: String?,
                                  landmarkHint: String?, confidence: String?) -> String? {
        if confidence == "editorial" {
            return landmarkHint
        }
        if let landmarkHint {
            return landmarkHint          // "toward MacArthur Blvd"
        }
        if parity == "even" || parity == "odd" {
            return nil                   // parity leads; geo name adds nothing
        }
        return nil
    }
}

extension SweepBundle.Segment {
    /// Side name for running copy ("Maybelle Ave · even side · sweep in …",
    /// notifications, share text).
    public var displaySideName: String? {
        let title = SweepFormat.sideTitle(parity: doorParity, landmark: landmark,
                                          confidence: landmarkConfidence)
        return title == "This side" ? landmark : title
    }
}
