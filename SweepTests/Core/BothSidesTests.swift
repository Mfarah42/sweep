import XCTest
@testable import SweepCore

/// Resident "both sides" mode: watch every sweep on the block without saying
/// which side the car is on.
final class BothSidesTests: XCTestCase {

    let cal = SweepCalendar.la

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    /// Old v1 session JSON (no secondarySegmentId) must keep decoding.
    func testSessionDecodingIsBackwardCompatible() throws {
        let v1JSON = #"{"segmentId":"oak:x:a","blockId":"Maybelle Ave|3700 block","sideKey":"a","parkedAt":773000000,"source":"manual"}"#
        let session = try JSONDecoder().decode(ParkingSession.self,
                                               from: Data(v1JSON.utf8))
        XCTAssertNil(session.secondarySegmentId)
        XCTAssertFalse(session.watchesBothSides)
        XCTAssertEqual(session.segmentIds, ["oak:x:a"])

        let both = ParkingSession(segmentId: "oak:x:a", blockId: "b", sideKey: "a",
                                  parkedAt: Date(), source: .manual,
                                  secondarySegmentId: "oak:x:b")
        XCTAssertTrue(both.watchesBothSides)
        XCTAssertEqual(both.segmentIds, ["oak:x:a", "oak:x:b"])
        // Round-trips through Codable.
        let decoded = try JSONDecoder().decode(ParkingSession.self,
                                               from: JSONEncoder().encode(both))
        XCTAssertEqual(decoded, both)
    }

    /// The union of both sides' rules must warn for whichever sweep comes
    /// first — the user's block: even side 2nd Fri 9–12, odd side 2nd Wed
    /// 12–16. From a Monday of the second week, the WEDNESDAY must drive
    /// the verdict even though the "primary" side sweeps Friday.
    func testUnionVerdictWarnsForEarlierSide() {
        let evenSide = [ScheduleRule(weekday: 5, weeks: [2], fromHour: 9, toHour: 12,
                                     holidayEnforced: false)]
        let oddSide = [ScheduleRule(weekday: 3, weeks: [2], fromHour: 12, toHour: 16,
                                    holidayEnforced: false)]
        let union = Array(Set(evenSide + oddSide))

        // Mon Jul 6 2026; 2nd Wed = Jul 8, 2nd Fri = Jul 10.
        let now = date(2026, 7, 6, 10)
        let evenOnly = VerdictEngine.verdict(rules: evenSide, city: .oak, at: now, calendar: cal)
        XCTAssertEqual(evenOnly.next?.start, date(2026, 7, 10, 9))

        let both = VerdictEngine.verdict(rules: union, city: .oak, at: now, calendar: cal)
        XCTAssertEqual(both.next?.start, date(2026, 7, 8, 12),
                       "both-sides verdict must follow the earlier sweep")
        // And the Friday window still appears in upcoming for the cards.
        XCTAssertTrue(both.upcoming.contains { $0.start == date(2026, 7, 10, 9) })
    }
}
