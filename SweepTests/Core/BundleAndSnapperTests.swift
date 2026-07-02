import XCTest
@testable import SweepCore

final class BundleReaderTests: XCTestCase {

    func fixturePath(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "sweepbundle",
                                    subdirectory: "Fixtures")
        return try XCTUnwrap(url).path
    }

    func testManifestAndSegments() throws {
        let bundle = try SweepBundle(path: fixturePath("sf"))
        XCTAssertEqual(bundle.manifest.city, .sf)
        XCTAssertEqual(bundle.manifest.schemaVersion, "1")
        XCTAssertEqual(bundle.manifest.builtAt, "2026-01-01T00:00:00Z")

        let holidays = bundle.holidays()
        XCTAssertEqual(holidays.suspends(onDateKey: "2026-11-26"), true)   // Thanksgiving
        XCTAssertEqual(holidays.suspends(onDateKey: "2026-07-04"), false)  // enforced in SF

        // A segment pulled by search must round-trip geometry and rules.
        let hits = bundle.searchBlocks(matching: "St")
        XCTAssertFalse(hits.isEmpty)
        let segs = bundle.blockSegments(street: hits[0].street, blockLabel: hits[0].blockLabel)
        XCTAssertFalse(segs.isEmpty)
        XCTAssertFalse(segs[0].geometry.isEmpty)
        XCTAssertFalse(segs[0].rules.isEmpty)
        XCTAssertTrue(segs[0].rules.allSatisfy { $0.toHour > $0.fromHour })
        // Sanity: SF coordinates.
        XCTAssertEqual(segs[0].geometry[0].lat, 37.7, accuracy: 0.4)
        XCTAssertEqual(segs[0].geometry[0].lon, -122.4, accuracy: 0.4)
    }

    func testSpatialQueryFindsNearbySegments() throws {
        let bundle = try SweepBundle(path: fixturePath("oak"))
        // Use a fixture segment's own first vertex as the fix.
        let any = bundle.searchBlocks(matching: "")
        let seg = bundle.blockSegments(street: any[0].street, blockLabel: any[0].blockLabel)[0]
        let near = bundle.segments(near: seg.geometry[0])
        XCTAssertTrue(near.contains { $0.id == seg.id })
    }
}

/// §13.9 — CurbSnapper fixture of 5 segments; high / ambiguous / too-far fixes.
final class CurbSnapperTests: XCTestCase {

    // Two parallel N-S streets ~160 m apart at SF latitude, two blocks each,
    // plus one segment of a cross street. 0.0001° lat ≈ 11 m; 0.0001° lon ≈ 8.8 m.
    func makeSegment(_ id: String, _ street: String, _ block: String,
                     _ pts: [(Double, Double)]) -> SweepBundle.Segment {
        SweepBundle.Segment(id: id, city: .sf, street: street, blockLabel: block,
                            sideKey: String(id.suffix(1)), doorParity: nil, doorRange: nil,
                            landmark: nil, landmarkHint: nil, landmarkConfidence: nil,
                            geometry: pts.map { GeoPoint(lat: $0.0, lon: $0.1) },
                            rules: [])
    }

    var fixtures: [SweepBundle.Segment] {
        [
            makeSegment("sf:1:a", "9th Ave", "Irving–Judah",
                        [(37.7630, -122.4660), (37.7640, -122.4660)]),
            makeSegment("sf:1:b", "9th Ave", "Irving–Judah",
                        [(37.7630, -122.4661), (37.7640, -122.4661)]),
            makeSegment("sf:2:a", "9th Ave", "Judah–Kirkham",
                        [(37.7620, -122.4660), (37.7630, -122.4660)]),
            makeSegment("sf:3:a", "10th Ave", "Irving–Judah",
                        [(37.7630, -122.4678), (37.7640, -122.4678)]),
            makeSegment("sf:4:a", "Irving St", "9th–10th",
                        [(37.7640, -122.4660), (37.7640, -122.4678)]),
        ]
    }

    func testHighConfidenceFix() {
        // Right next to the 9th Ave Irving–Judah block, mid-block: ~2 m off
        // side a, 10th Ave is ~150 m west, the cross street ~55 m north.
        let fix = GeoPoint(lat: 37.7635, lon: -122.46602)
        let result = CurbSnapper.snap(fix: fix, candidates: fixtures)!
        XCTAssertEqual(result.block.street, "9th Ave")
        XCTAssertEqual(result.block.blockLabel, "Irving–Judah")
        XCTAssertEqual(result.confidence, .high)
        // Both sides of the block are in the candidate group; GPS never picks one.
        XCTAssertEqual(result.block.segmentIds, ["sf:1:a", "sf:1:b"])
    }

    func testAmbiguousFixNearBlockCorner() {
        // At the Irving/9th corner: the 9th Ave block and the cross street are
        // both within a few meters — runner-up must be surfaced.
        let fix = GeoPoint(lat: 37.76398, lon: -122.46605)
        let result = CurbSnapper.snap(fix: fix, candidates: fixtures)!
        XCTAssertEqual(result.confidence, .ambiguous)
        XCTAssertNotNil(result.runnerUp)
    }

    func testTooFarReturnsNil() {
        // ~500 m away — outside the 35 m fine radius for everything.
        let fix = GeoPoint(lat: 37.7680, lon: -122.4660)
        XCTAssertNil(CurbSnapper.snap(fix: fix, candidates: fixtures))
    }
}

/// §13.8 — reschedule idempotency: planning twice yields the same pending set.
final class NotificationPlannerTests: XCTestCase {

    let cal = SweepCalendar.la

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testPlanIsIdempotentAndIdentifiersAreStable() {
        let rules = [ScheduleRule(weekday: 2, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: true)]
        let now = date(2026, 10, 4, 9)
        let windows = VerdictEngine.upcomingWindows(rules: rules, city: .sf, from: now,
                                                    count: 2, calendar: cal)
        let ctx = NotificationPlanner.Context(segmentId: "sf:432000:b", street: "9th Ave",
                                              landmark: "Ocean side", city: .sf)
        let prefs = ReminderPrefs()
        let a = NotificationPlanner.plan(context: ctx, windows: windows, prefs: prefs,
                                         now: now, calendar: cal)
        let b = NotificationPlanner.plan(context: ctx, windows: windows, prefs: prefs,
                                         now: now, calendar: cal)
        XCTAssertEqual(a.map(\.identifier), b.map(\.identifier))
        XCTAssertEqual(Set(a.map(\.identifier)).count, a.count, "identifiers must be unique")
        XCTAssertTrue(a.allSatisfy { $0.identifier.hasPrefix("sweep.sf:432000:b.") })
        // 2 windows × 3 offsets, all in the future from `now`.
        XCTAssertEqual(a.count, 6)
        // Evening-before fires at 8 PM the previous LA day.
        let evening = a.first { $0.offset == .nightBefore }!
        XCTAssertEqual(cal.component(.hour, from: evening.fireDate), 20)
        XCTAssertEqual(cal.component(.day, from: evening.fireDate), 5)
        // 30-min alert is time-sensitive; copy carries the fine.
        let lastCall = a.first { $0.offset == .thirtyMin }!
        XCTAssertTrue(lastCall.timeSensitive)
        XCTAssertTrue(lastCall.body.contains("$97"))
    }

    func testEveningBeforeSkippedWhenAfterStart() {
        // Window starts at 7 AM; evening-before (8 PM prior day) is valid.
        // Window starting at 6 PM: evening before is 8 PM the prior day — still
        // before start, valid. A window at 9 PM the SAME day it was planned:
        // evening 8 PM fires before it. The skip case: window start before
        // 8 PM of the previous day is impossible, so test the now-cutoff:
        // planning at 9 PM the evening before must not schedule a past evening.
        let rules = [ScheduleRule(weekday: 2, weeks: nil, fromHour: 8, toHour: 10, holidayEnforced: true)]
        let now = date(2026, 10, 5, 21)   // Monday 9 PM, window Tuesday 8 AM
        let windows = VerdictEngine.upcomingWindows(rules: rules, city: .sf, from: now,
                                                    count: 1, calendar: cal)
        let ctx = NotificationPlanner.Context(segmentId: "x", street: "9th Ave",
                                              landmark: nil, city: .sf)
        let planned = NotificationPlanner.plan(context: ctx, windows: windows,
                                               prefs: ReminderPrefs(), now: now, calendar: cal)
        XCTAssertFalse(planned.contains {
            $0.offset == .nightBefore && cal.component(.day, from: $0.fireDate) == 5
        })
    }
}

final class OverrideTests: XCTestCase {
    func testOvernightOverrideSplits() {
        let o = ScheduleRuleOverride(weekday: 2, fromHour: 22, toHour: 2, createdAt: Date())
        let rules = o.rules(for: .oak)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual((rules[0].weekday, rules[0].fromHour, rules[0].toHour).0, 2)
        XCTAssertEqual(rules[0].toHour, 24)
        XCTAssertEqual(rules[1].weekday, 3)
        XCTAssertEqual(rules[1].fromHour, 0)
        XCTAssertEqual(rules[1].toHour, 2)
        XCTAssertTrue(rules.allSatisfy { $0.holidayEnforced == false })   // oak default
    }
}
