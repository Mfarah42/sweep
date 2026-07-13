import XCTest
@testable import SweepCore

/// The three guardian extras: stale-bundle honesty (§1.3), the 72-hour rule
/// warning, and the all-clear when sweeping ends.
final class GuardianExtrasTests: XCTestCase {

    let cal = SweepCalendar.la

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    // MARK: - Stale bundle (§1.3)

    func testStaleNoticeAppearsAfterSixtyDays() {
        let now = date(2026, 7, 9, 12)
        // Fresh bundle → no notice.
        XCTAssertNil(SweepFormat.staleNotice(builtAt: "2026-07-01T00:00:00Z", now: now))
        // 59 days → still fresh.
        XCTAssertNil(SweepFormat.staleNotice(builtAt: "2026-05-11T00:00:00Z", now: now))
        // 90 days → degrade honestly, naming the month.
        let notice = SweepFormat.staleNotice(builtAt: "2026-04-09T00:00:00Z", now: now)
        XCTAssertEqual(notice, "Schedule data is from April 2026 — "
                       + "the posted sign outranks the app.")
        // Garbage manifest → no crash, no notice.
        XCTAssertNil(SweepFormat.staleNotice(builtAt: "fixture", now: now))
    }

    // MARK: - 72-hour rule

    func testThreeDayWarningPlansAtSixtyEightHours() {
        let ctx = NotificationPlanner.Context(segmentId: "oak:x:a", street: "Maybelle Ave",
                                              landmark: "even side", city: .oak)
        let parkedAt = date(2026, 7, 6, 18)
        let now = date(2026, 7, 6, 18)
        let planned = NotificationPlanner.plan(context: ctx, windows: [],
                                               prefs: ReminderPrefs(), now: now,
                                               calendar: cal, parkedAt: parkedAt)
        let threeDay = planned.filter { $0.offset == .threeDay }
        XCTAssertEqual(threeDay.count, 1)
        XCTAssertEqual(threeDay[0].fireDate, parkedAt.addingTimeInterval(68 * 3600))
        XCTAssertTrue(threeDay[0].body.contains("72 hours"))
        XCTAssertTrue(threeDay[0].body.contains("Oakland"))

        // Toggled off → none. No parkedAt → none.
        XCTAssertTrue(NotificationPlanner.plan(
            context: ctx, windows: [], prefs: ReminderPrefs(threeDayRule: false),
            now: now, calendar: cal, parkedAt: parkedAt).isEmpty)
        XCTAssertTrue(NotificationPlanner.plan(
            context: ctx, windows: [], prefs: ReminderPrefs(),
            now: now, calendar: cal).isEmpty)
    }

    // MARK: - All clear

    func testAllClearFiresAtWindowEndWithNextWindow() {
        let ctx = NotificationPlanner.Context(segmentId: "oak:x:a", street: "Maybelle Ave",
                                              landmark: "even side", city: .oak)
        let rules = [ScheduleRule(weekday: 5, weeks: [2], fromHour: 9, toHour: 12,
                                  holidayEnforced: false)]
        let now = date(2026, 7, 9, 20)
        let windows = VerdictEngine.upcomingWindows(rules: rules, city: .oak, from: now,
                                                    count: 3, calendar: cal)
        let planned = NotificationPlanner.plan(context: ctx, windows: windows,
                                               prefs: ReminderPrefs(), now: now, calendar: cal)
        let clear = planned.filter { $0.offset == .allClear }
        XCTAssertEqual(clear.count, 1)
        XCTAssertEqual(clear[0].fireDate, date(2026, 7, 10, 12))   // window end
        XCTAssertTrue(clear[0].title.contains("All clear"))
        XCTAssertTrue(clear[0].body.contains("Friday"),
                      "should name the following sweep (Aug 14 is a Friday)")

        XCTAssertTrue(NotificationPlanner.plan(
            context: ctx, windows: windows, prefs: ReminderPrefs(allClear: false),
            now: now, calendar: cal)
            .allSatisfy { $0.offset != .allClear })
    }

    // MARK: - Prefs migration

    func testOldPrefsJSONDefaultsNewTogglesOn() throws {
        let v1JSON = #"{"nightBefore":false,"twoHours":true,"thirtyMin":true}"#
        let prefs = try JSONDecoder().decode(ReminderPrefs.self, from: Data(v1JSON.utf8))
        XCTAssertFalse(prefs.nightBefore, "existing choices survive")
        XCTAssertTrue(prefs.allClear)
        XCTAssertTrue(prefs.threeDayRule)
    }
}
