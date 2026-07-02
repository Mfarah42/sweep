import XCTest
@testable import SweepCore

/// §13.1–7: engine tests with a fixed clock and the LA calendar.
final class EngineTests: XCTestCase {

    let cal = SweepCalendar.la

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return cal.date(from: c)!
    }

    func components(_ d: Date) -> (day: Int, hour: Int) {
        let c = cal.dateComponents([.day, .hour], from: d)
        return (c.day!, c.hour!)
    }

    // §13.1 — weekly plain Tuesday, next window correct across a month boundary.
    func testWeeklyTuesdayAcrossMonthBoundary() {
        let rules = [ScheduleRule(weekday: 2, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: true)]
        // Wed Sep 30 2026 → next Tuesday is Oct 6.
        let windows = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                    from: date(2026, 9, 30), count: 2, calendar: cal)
        XCTAssertEqual(windows.first?.start, date(2026, 10, 6, 8))
        XCTAssertEqual(windows.first?.end, date(2026, 10, 6, 10))
        XCTAssertEqual(windows.dropFirst().first?.start, date(2026, 10, 13, 8))
    }

    // §13.2 — "1st & 3rd Wednesday" in a month whose 1st is a Wednesday (Jul 2026)
    // and one where it isn't (Aug 2026, 1st = Saturday).
    func testFirstAndThirdWednesday() {
        let rules = [ScheduleRule(weekday: 3, weeks: [1, 3], fromHour: 12, toHour: 14, holidayEnforced: true)]
        let july = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                 from: date(2026, 7, 1), count: 2, calendar: cal)
        XCTAssertEqual(july.map(\.start), [date(2026, 7, 1, 12), date(2026, 7, 15, 12)])

        let august = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                   from: date(2026, 8, 1), count: 2, calendar: cal)
        XCTAssertEqual(august.map(\.start), [date(2026, 8, 5, 12), date(2026, 8, 19, 12)])
    }

    // §13.3 — 5th-occurrence rule skips months with only four of that weekday.
    func testFifthOccurrenceSkipsShortMonths() {
        let rules = [ScheduleRule(weekday: 2, weeks: [5], fromHour: 8, toHour: 10, holidayEnforced: true)]
        // June 2026 has five Tuesdays; the 5th is Jun 30.
        let fromJune = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                     from: date(2026, 6, 1), count: 1, calendar: cal)
        XCTAssertEqual(fromJune.first?.start, date(2026, 6, 30, 8))
        // July and August 2026 have four Tuesdays each; nothing within 70 days.
        let fromJuly = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                     from: date(2026, 7, 1), count: 1, calendar: cal)
        XCTAssertTrue(fromJuly.isEmpty)
    }

    // §13.4 — verdict transitions at exactly T−12h, T, T_end (half-open interval).
    func testVerdictBoundaries() {
        let rules = [ScheduleRule(weekday: 2, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: true)]
        let start = date(2026, 10, 6, 8)

        // Just before T−12h → safe.
        let before = VerdictEngine.verdict(rules: rules, city: .sf,
                                           at: start.addingTimeInterval(-12 * 3600 - 1), calendar: cal)
        XCTAssertEqual(before.state, .safe)

        // Exactly T−12h → moveSoon.
        let at12 = VerdictEngine.verdict(rules: rules, city: .sf,
                                         at: start.addingTimeInterval(-12 * 3600), calendar: cal)
        XCTAssertEqual(at12.state, .moveSoon)

        // Exactly T → sweepingNow (interval is half-open [start, end)).
        let atStart = VerdictEngine.verdict(rules: rules, city: .sf, at: start, calendar: cal)
        XCTAssertEqual(atStart.state, .sweepingNow)

        // Exactly T_end → the window is over; next week's window, safe.
        let atEnd = VerdictEngine.verdict(rules: rules, city: .sf,
                                          at: date(2026, 10, 6, 10), calendar: cal)
        XCTAssertEqual(atEnd.state, .safe)
        XCTAssertEqual(atEnd.next?.start, date(2026, 10, 13, 8))
    }

    // §13.5 — Oakland holiday suspends; SF same date enforces with the flag.
    func testHolidaySemantics() {
        // July 4 2026 is a Saturday. Saturday rule, 8–10.
        let oakRules = [ScheduleRule(weekday: 6, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: false)]
        let oakHolidays = HolidayCalendar(suspendsByDate: ["2026-07-04": true])
        let oak = VerdictEngine.verdict(rules: oakRules, city: .oak,
                                        at: date(2026, 7, 3, 12), calendar: cal, holidays: oakHolidays)
        // Suspended window is emitted for the UI…
        XCTAssertTrue(oak.upcoming.contains {
            $0.suspendedForHoliday && $0.start == date(2026, 7, 4, 8)
        })
        // …but the verdict uses the following Saturday.
        XCTAssertEqual(oak.next?.start, date(2026, 7, 11, 8))
        XCTAssertEqual(oak.state, .safe)

        let sfRules = [ScheduleRule(weekday: 6, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: true)]
        let sfHolidays = HolidayCalendar(suspendsByDate: ["2026-07-04": false])
        let sf = VerdictEngine.verdict(rules: sfRules, city: .sf,
                                       at: date(2026, 7, 3, 12), calendar: cal, holidays: sfHolidays)
        XCTAssertEqual(sf.next?.start, date(2026, 7, 4, 8))
        XCTAssertTrue(sf.next?.holidayButEnforced ?? false)
        XCTAssertFalse(sf.next?.suspendedForHoliday ?? true)
    }

    // §13.6 — DST: wall-clock hours hold; durations differ, and that's correct.
    func testDSTSpringForwardAndFallBack() {
        let rules = [ScheduleRule(weekday: 0, weeks: nil, fromHour: 0, toHour: 6, holidayEnforced: true)]

        // Spring forward: Sun Mar 8 2026, 2 AM skipped → 5-hour window.
        let spring = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                   from: date(2026, 3, 7), count: 1, calendar: cal).first!
        XCTAssertEqual(components(spring.start).hour, 0)
        XCTAssertEqual(components(spring.end).hour, 6)
        XCTAssertEqual(components(spring.start).day, 8)
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 5 * 3600)

        // Fall back: Sun Nov 1 2026, 1 AM repeats → 7-hour window.
        let fall = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                 from: date(2026, 10, 31), count: 1, calendar: cal).first!
        XCTAssertEqual(components(fall.start).hour, 0)
        XCTAssertEqual(components(fall.end).hour, 6)
        XCTAssertEqual(components(fall.start).day, 1)
        XCTAssertEqual(fall.end.timeIntervalSince(fall.start), 7 * 3600)
    }

    // §13.7 — overnight rule split by the pipeline produces two windows on
    // consecutive days, and the engine never sees wraparound.
    func testOvernightSplitRules() {
        // Posted sign: Tuesday 10 PM – 2 AM → pipeline emits (Tue 22–24, Wed 0–2).
        let rules = [
            ScheduleRule(weekday: 2, weeks: nil, fromHour: 22, toHour: 24, holidayEnforced: true),
            ScheduleRule(weekday: 3, weeks: nil, fromHour: 0, toHour: 2, holidayEnforced: true),
        ]
        let windows = VerdictEngine.upcomingWindows(rules: rules, city: .sf,
                                                    from: date(2026, 10, 5), count: 2, calendar: cal)
        XCTAssertEqual(windows[0].start, date(2026, 10, 6, 22))
        XCTAssertEqual(windows[0].end, date(2026, 10, 7, 0))
        XCTAssertEqual(windows[1].start, date(2026, 10, 7, 0))
        XCTAssertEqual(windows[1].end, date(2026, 10, 7, 2))
        // Contiguous windows behave as one sweep for the verdict.
        let during = VerdictEngine.verdict(rules: rules, city: .sf,
                                           at: date(2026, 10, 6, 23), calendar: cal)
        XCTAssertEqual(during.state, .sweepingNow)
    }

    // §7.3 — side question is skipped when both sides sweep identically.
    func testRuleEquivalence() {
        let a = [ScheduleRule(weekday: 2, weeks: [1, 3], fromHour: 8, toHour: 10, holidayEnforced: true),
                 ScheduleRule(weekday: 5, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: true)]
        let b = Array(a.reversed())
        XCTAssertTrue(VerdictEngine.rulesAreEquivalent(a, b))
        let c = [ScheduleRule(weekday: 2, weeks: [2, 4], fromHour: 8, toHour: 10, holidayEnforced: true)]
        XCTAssertFalse(VerdictEngine.rulesAreEquivalent(a, c))
    }
}
