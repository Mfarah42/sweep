import XCTest
@testable import SweepCore

/// The footer must never under-describe a schedule (§1.3): a Mon/Wed/Fri
/// block once displayed as "Mondays" because only the first rule was read.
final class ScheduleLineTests: XCTestCase {

    func rule(_ weekday: Int, weeks: [Int]? = nil, from: Int = 2, to: Int = 3) -> ScheduleRule {
        ScheduleRule(weekday: weekday, weeks: weeks, fromHour: from, toHour: to,
                     holidayEnforced: false)
    }

    func testSingleDayWeekly() {
        XCTAssertEqual(SweepFormat.scheduleLine(rules: [rule(2, from: 8, to: 10)]),
                       "Tuesdays, 8 AM–10 AM · every week")
    }

    func testMultiDayPatternListsAllDays() {
        let rules = [rule(1), rule(3), rule(5)]
        XCTAssertEqual(SweepFormat.scheduleLine(rules: rules),
                       "Mon, Wed & Fri, 2 AM–3 AM · every week")
    }

    func testWeekSubset() {
        XCTAssertEqual(SweepFormat.scheduleLine(rules: [rule(5, weeks: [2], from: 9, to: 12)]),
                       "Fridays, 9 AM–12 PM · 2nd weeks")
        XCTAssertEqual(SweepFormat.scheduleLine(rules: [rule(2, weeks: [1, 3], from: 12, to: 16)]),
                       "Tuesdays, 12 PM–4 PM · 1st & 3rd weeks")
    }

    func testSignLinesMatchPostedSignFormat() {
        // 2nd Friday, 9–12 (the user's block).
        XCTAssertEqual(SweepFormat.signLines(rules: [rule(5, weeks: [2], from: 9, to: 12)]),
                       ["9 AM – 12 PM", "2ND FRI"])
        // Mon/Wed/Fri weekly.
        XCTAssertEqual(SweepFormat.signLines(rules: [rule(1), rule(3), rule(5)]),
                       ["2 AM – 3 AM", "MON, WED & FRI"])
        XCTAssertEqual(SweepFormat.signLines(rules: [rule(2, weeks: [1, 3], from: 12, to: 16)]),
                       ["12 PM – 4 PM", "1ST & 3RD TUE"])
        XCTAssertEqual(SweepFormat.signLines(rules: []), [])
    }

    func testMixedPatternsDescribeFirstOnly() {
        // Overnight split (Tue 22–24 + Wed 0–2): the two rules have different
        // hours, so the line describes the posted start pattern.
        let rules = [ScheduleRule(weekday: 2, weeks: nil, fromHour: 22, toHour: 24, holidayEnforced: true),
                     ScheduleRule(weekday: 3, weeks: nil, fromHour: 0, toHour: 2, holidayEnforced: true)]
        XCTAssertEqual(SweepFormat.scheduleLine(rules: rules),
                       "Tuesdays, 10 PM–12 AM · every week")
    }
}
