import XCTest
@testable import SweepCore

/// Sweep Plus multi-car: sessions array, migration, per-car notifications.
final class MultiCarTests: XCTestCase {

    let cal = SweepCalendar.la

    func freshStore() -> PersistenceStore {
        let suite = "multicar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PersistenceStore(defaults: defaults)
    }

    func session(_ car: String?) -> ParkingSession {
        ParkingSession(segmentId: "oak:x:a", blockId: "Maybelle Ave|3700 block",
                       sideKey: "a", parkedAt: Date(), source: .manual, carName: car)
    }

    func testV1SingleSessionMigratesIntoSessionsArray() throws {
        let store = freshStore()
        // Simulate a pre-multi-car install: only the v1 key exists.
        let v1JSON = #"{"segmentId":"oak:x:a","blockId":"b","sideKey":"a","parkedAt":773000000,"source":"manual"}"#
        store.defaultsForTesting.set(Data(v1JSON.utf8), forKey: PersistenceStore.Keys.session)

        let migrated = store.sessions
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated[0].segmentId, "oak:x:a")
        XCTAssertNil(migrated[0].carName)

        // Writing v2 clears the legacy key.
        store.sessions = migrated
        XCTAssertNil(store.defaultsForTesting.data(forKey: PersistenceStore.Keys.session))
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testSessionIdIsStableOncePersisted() throws {
        let store = freshStore()
        let original = session("the Civic")
        store.sessions = [original]
        XCTAssertEqual(store.sessions[0].id, original.id)
        XCTAssertEqual(store.sessions[0].id, store.sessions[0].id)
        XCTAssertEqual(store.sessions[0].carName, "the Civic")
    }

    func testTwoCarsGetTwoSessions() {
        let store = freshStore()
        store.sessions = [session("the Civic"), session("the truck")]
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions.map(\.carName), ["the Civic", "the truck"])
        // Legacy accessor still answers "is anything parked".
        XCTAssertNotNil(store.session)
    }

    /// Two cars on the SAME segment (household street parking) must never
    /// collide on notification identifiers, and copy must name the car.
    func testPerCarIdentifiersAndCopy() {
        let rules = [ScheduleRule(weekday: 5, weeks: [2], fromHour: 9, toHour: 12,
                                  holidayEnforced: false)]
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 10))!
        let windows = VerdictEngine.upcomingWindows(rules: rules, city: .oak, from: now,
                                                    count: 2, calendar: cal)
        let civic = NotificationPlanner.Context(
            segmentId: "oak:x:a", street: "Maybelle Ave", landmark: "even side",
            city: .oak, sessionKey: "aaaa1111.", carName: "the Civic")
        let truck = NotificationPlanner.Context(
            segmentId: "oak:x:a", street: "Maybelle Ave", landmark: "even side",
            city: .oak, sessionKey: "bbbb2222.", carName: "the truck")

        let a = NotificationPlanner.plan(context: civic, windows: windows,
                                         prefs: ReminderPrefs(), now: now, calendar: cal,
                                         parkedAt: now)
        let b = NotificationPlanner.plan(context: truck, windows: windows,
                                         prefs: ReminderPrefs(), now: now, calendar: cal,
                                         parkedAt: now)
        XCTAssertTrue(Set(a.map(\.identifier)).isDisjoint(with: b.map(\.identifier)),
                      "same segment, different cars → disjoint identifiers")
        XCTAssertTrue(a.allSatisfy { $0.identifier.contains("aaaa1111.") })
        XCTAssertTrue(a.contains { $0.body.contains("the Civic") || $0.title.contains("the Civic") })
        XCTAssertTrue(b.contains { $0.title.contains("the truck") })

        // Single-car household: no car naming noise.
        let solo = NotificationPlanner.Context(
            segmentId: "oak:x:a", street: "Maybelle Ave", landmark: "even side", city: .oak)
        let s = NotificationPlanner.plan(context: solo, windows: windows,
                                         prefs: ReminderPrefs(), now: now, calendar: cal)
        XCTAssertTrue(s.allSatisfy { !$0.body.contains("Civic") })
        XCTAssertTrue(s.contains { $0.title == "Move the car by 9 AM" })
    }
}
