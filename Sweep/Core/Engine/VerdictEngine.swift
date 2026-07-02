import Foundation

/// Pure, deterministic schedule engine (spec §5). Ported from the prototype:
/// day-by-day iteration, weekOccurrence = ceil(dayOfMonth / 7), wall-clock
/// window construction in the LA calendar so DST is correct by construction.
///
/// The spec signatures carry `city` for holiday semantics; the holiday table
/// itself is injected (`holidays:`) so the engine stays pure and testable —
/// callers load it from the city bundle.
public enum VerdictEngine {

    public static let horizonDays = 70
    public static let moveSoonLeadHours: Double = 12

    public static func upcomingWindows(rules: [ScheduleRule], city: City, from: Date,
                                       count: Int, calendar: Calendar,
                                       holidays: HolidayCalendar = .empty) -> [SweepWindow] {
        guard !rules.isEmpty, count > 0 else { return [] }

        var windows: [SweepWindow] = []
        var nonSuspended = 0
        var day = calendar.startOfDay(for: from)

        for _ in 0..<horizonDays {
            // Calendar.weekday is 1=Sunday…7=Saturday; schema is 0=Sunday…6.
            let weekday = calendar.component(.weekday, from: day) - 1
            let dayOfMonth = calendar.component(.day, from: day)
            let weekOccurrence = (dayOfMonth + 6) / 7   // ceil(dayOfMonth / 7), 1…5

            for rule in rules where rule.weekday == weekday {
                if let weeks = rule.weeks, !weeks.contains(weekOccurrence) { continue }
                guard let start = calendar.date(bySettingHour: rule.fromHour, minute: 0,
                                                second: 0, of: day) else { continue }
                let end: Date
                if rule.toHour >= 24 {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                    end = calendar.startOfDay(for: nextDay)
                } else {
                    guard let e = calendar.date(bySettingHour: rule.toHour, minute: 0,
                                                second: 0, of: day) else { continue }
                    end = e
                }
                guard end > from else { continue }   // window fully in the past

                let key = HolidayCalendar.dateKey(for: day, calendar: calendar)
                if let citySuspends = holidays.suspends(onDateKey: key) {
                    if citySuspends || !rule.holidayEnforced {
                        // Holiday, no sweeping — shown in UI, excluded from verdicts.
                        windows.append(SweepWindow(start: start, end: end,
                                                   suspendedForHoliday: true))
                        continue
                    }
                    windows.append(SweepWindow(start: start, end: end,
                                               holidayButEnforced: true))
                } else {
                    windows.append(SweepWindow(start: start, end: end))
                }
                nonSuspended += 1
            }
            if nonSuspended >= count { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        windows.sort { $0.start < $1.start }
        return windows
    }

    public static func verdict(rules: [ScheduleRule], city: City, at now: Date,
                               calendar: Calendar,
                               holidays: HolidayCalendar = .empty) -> Verdict {
        let upcoming = upcomingWindows(rules: rules, city: city, from: now,
                                       count: 4, calendar: calendar, holidays: holidays)
        guard let next = upcoming.first(where: { !$0.suspendedForHoliday }) else {
            return Verdict(state: .safe, next: nil, upcoming: upcoming)
        }
        let state: VerdictState
        if next.start <= now && now < next.end {          // half-open [start, end)
            state = .sweepingNow
        } else if next.start.timeIntervalSince(now) <= moveSoonLeadHours * 3600 {
            state = .moveSoon
        } else {
            state = .safe
        }
        return Verdict(state: state, next: next, upcoming: upcoming)
    }

    /// Side question is skipped when both sides sweep identically (§7.3).
    public static func rulesAreEquivalent(_ a: [ScheduleRule], _ b: [ScheduleRule]) -> Bool {
        func canonical(_ rules: [ScheduleRule]) -> [ScheduleRule] {
            Array(Set(rules)).sorted {
                ($0.weekday, $0.fromHour, $0.toHour) < ($1.weekday, $1.fromHour, $1.toHour)
            }
        }
        return canonical(a) == canonical(b)
    }
}
