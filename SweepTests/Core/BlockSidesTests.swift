import XCTest
@testable import SweepCore

/// Regression for the Maybelle Ave bug: a block label spanning multiple source
/// features has several segments per side; comparing raw segments paired two
/// same-side segments and skipped the side question even though the sides
/// sweep on different days.
final class BlockSidesTests: XCTestCase {

    let cal = SweepCalendar.la

    func segment(_ id: String, side: String, rules: [ScheduleRule],
                 doorRange: String? = nil) -> SweepBundle.Segment {
        SweepBundle.Segment(id: id, city: .oak, street: "Maybelle Ave",
                            blockLabel: "3700 block", sideKey: side,
                            doorParity: side == "a" ? "even" : "odd",
                            doorRange: doorRange, landmark: nil, landmarkHint: nil,
                            landmarkConfidence: "auto",
                            geometry: [GeoPoint(lat: 37.79, lon: -122.19)],
                            rules: rules)
    }

    // Friday 2nd week (even side) vs Wednesday 2nd week (odd side), two
    // features each — exactly the live Maybelle Ave data shape.
    var maybelle: [SweepBundle.Segment] {
        let friday = [ScheduleRule(weekday: 5, weeks: [2], fromHour: 9, toHour: 12, holidayEnforced: false)]
        let wednesday = [ScheduleRule(weekday: 3, weeks: [2], fromHour: 12, toHour: 16, holidayEnforced: false)]
        return [
            segment("oak:f1:a", side: "a", rules: friday, doorRange: "3728–3752"),
            segment("oak:f1:b", side: "b", rules: wednesday, doorRange: "3717–3743"),
            segment("oak:f2:a", side: "a", rules: friday, doorRange: "3754–3898"),
            segment("oak:f2:b", side: "b", rules: wednesday, doorRange: "3745–3899"),
        ]
    }

    func testMultiFeatureBlockKeepsSideQuestion() {
        let sides = BlockSides.group(maybelle)
        XCTAssertEqual(sides.map(\.sideKey), ["a", "b"])
        XCTAssertEqual(sides.map { $0.segments.count }, [2, 2])
        XCTAssertFalse(BlockSides.sidesAreEquivalent(sides, overrides: [:]),
                       "different weekdays per side must keep the side question")
        // Merged door ranges span both features.
        XCTAssertEqual(sides[0].doorRange, "3728–3898")
        XCTAssertEqual(sides[1].doorRange, "3717–3899")
    }

    func testIdenticalSidesSkipQuestion() {
        let rules = [ScheduleRule(weekday: 2, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: true)]
        let sides = BlockSides.group([
            segment("oak:f1:a", side: "a", rules: rules),
            segment("oak:f1:b", side: "b", rules: rules),
            segment("oak:f2:a", side: "a", rules: rules),
        ])
        XCTAssertTrue(BlockSides.sidesAreEquivalent(sides, overrides: [:]))
    }

    func testParkTargetPicksEarliestNextSweep() {
        // Same side, two features: one sweeps Tuesday, the other Friday.
        // From a Monday, the Tuesday segment is the conservative target.
        let tuesday = segment("oak:f1:a", side: "a",
                              rules: [ScheduleRule(weekday: 2, weeks: nil, fromHour: 8,
                                                   toHour: 10, holidayEnforced: false)])
        let friday = segment("oak:f2:a", side: "a",
                             rules: [ScheduleRule(weekday: 5, weeks: nil, fromHour: 8,
                                                  toHour: 10, holidayEnforced: false)])
        let side = BlockSides.group([friday, tuesday])[0]
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let target = side.parkTarget(at: monday, calendar: cal, holidays: .empty, overrides: [:])
        XCTAssertEqual(target.id, "oak:f1:a")
    }
}
