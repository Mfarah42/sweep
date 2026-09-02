import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Hook for the app target to start/stop the Live Activity (§9) — ActivityKit
/// is iOS-only, so the controller lives in the app, not in SweepCore.
public protocol LiveActivityControlling: AnyObject {
    func syncLiveActivity(session: ParkingSession?, verdict: Verdict?, context: NotificationPlanner.Context?)
}

/// Owns the parked cars (§6.3; multi-car since Plus). On any change:
/// recompute per-car verdicts, reschedule the union of notifications,
/// refresh widgets, and point the Live Activity + Apple Reminders mirror at
/// the most urgent car.
@MainActor
public final class ParkingSessionManager: ObservableObject {

    @Published public private(set) var sessions: [ParkingSession] = []
    @Published public private(set) var verdicts: [UUID: Verdict] = [:]

    /// Legacy single-car views: the first session / the most urgent verdict.
    public var session: ParkingSession? { sessions.first }
    @Published public private(set) var verdict: Verdict?

    public weak var liveActivity: LiveActivityControlling?
    /// Optional opt-in mirror into the Apple Reminders app.
    public var remindersBridge: AppleRemindersBridge?

    let store: PersistenceStore
    private let bundleManager: BundleManager
    private let scheduler: NotificationScheduler
    public var clock: Clock

    public init(store: PersistenceStore, bundleManager: BundleManager,
                scheduler: NotificationScheduler, clock: Clock = SystemClock()) {
        self.store = store
        self.bundleManager = bundleManager
        self.scheduler = scheduler
        self.clock = clock
        self.sessions = store.sessions
    }

    public var city: City {
        get { store.city }
        set {
            store.city = newValue
            clearAllSessions()   // switching cities clears the sessions (§7.6)
        }
    }

    /// The city is inferred from where the user parks or which street they
    /// pick — never something they have to remember to toggle. Adopting the
    /// same city is a no-op; a different one follows the §7.6 rule (one city
    /// at a time, so an existing spot in the other city is cleared first).
    public func adoptCity(_ newCity: City) {
        guard newCity != store.city else { return }
        if sessions.isEmpty {
            store.city = newCity
        } else {
            city = newCity
        }
    }

    // MARK: - Segments

    public func currentSegment() -> SweepBundle.Segment? {
        session.flatMap { segments(for: $0).first }
    }

    /// First session's segments — legacy accessor for single-car UI paths.
    public func currentSegments() -> [SweepBundle.Segment] {
        session.map { segments(for: $0) } ?? []
    }

    public func segments(for session: ParkingSession) -> [SweepBundle.Segment] {
        guard let bundle = try? bundleManager.openBundle(for: store.city) else { return [] }
        return session.segmentIds.compactMap { bundle.segment(id: $0) }
    }

    public func effectiveRules(for segment: SweepBundle.Segment) -> [ScheduleRule] {
        OverrideDecorator.effectiveRules(segment: segment, overrides: store.overrides)
    }

    /// Union of one session's sides' rules.
    public func watchedRules(for session: ParkingSession) -> [ScheduleRule] {
        Array(Set(segments(for: session).flatMap { effectiveRules(for: $0) }))
            .sorted { ($0.weekday, $0.fromHour) < ($1.weekday, $1.fromHour) }
    }

    // MARK: - Parking

    public func park(segment: SweepBundle.Segment, source: ParkingSession.Source) async {
        await park(segments: [segment], source: source)
    }

    /// Free-tier behavior and the first car: this becomes the only session.
    public func park(segments: [SweepBundle.Segment], source: ParkingSession.Source) async {
        guard let s = makeSession(segments: segments, source: source, carName: nil) else { return }
        store.sessions = [s]
        sessions = [s]
        await refreshDerivedState()
    }

    /// Plus multi-car: re-park an existing car (keeps its name) or add a new
    /// named car alongside the others.
    public func park(segments: [SweepBundle.Segment], source: ParkingSession.Source,
                     replacing sessionId: UUID?, carName: String?) async {
        var all = store.sessions
        if let sessionId, let index = all.firstIndex(where: { $0.id == sessionId }) {
            guard let s = makeSession(segments: segments, source: source,
                                      carName: all[index].carName, id: sessionId) else { return }
            all[index] = s
        } else {
            guard let s = makeSession(segments: segments, source: source, carName: carName) else { return }
            all.append(s)
        }
        store.sessions = all
        sessions = all
        await refreshDerivedState()
    }

    private func makeSession(segments: [SweepBundle.Segment], source: ParkingSession.Source,
                             carName: String?, id: UUID = UUID()) -> ParkingSession? {
        guard let primary = segments.first else { return nil }
        return ParkingSession(id: id,
                              segmentId: primary.id,
                              blockId: primary.blockKey,
                              sideKey: primary.sideKey,
                              parkedAt: clock.now,
                              source: source,
                              secondarySegmentId: segments.dropFirst().first?.id,
                              carName: carName)
    }

    // MARK: - Clearing

    /// "I moved my car" for one car.
    public func clearSession(id: UUID) {
        var all = store.sessions
        all.removeAll { $0.id == id }
        store.sessions = all
        sessions = all
        Task { await refreshDerivedState() }
    }

    public func clearSession() {
        clearAllSessions()
    }

    public func clearAllSessions() {
        store.sessions = []
        sessions = []
        verdicts = [:]
        verdict = nil
        Task {
            await scheduler.clearAll()
            reloadWidgets()
            liveActivity?.syncLiveActivity(session: nil, verdict: nil, context: nil)
            remindersBridge?.sync(deadline: nil, street: nil, sideName: nil)
        }
    }

    public func saveCorrection(_ override: ScheduleRuleOverride, for segmentId: String) async {
        var all = store.overrides
        all[segmentId] = override
        store.overrides = all
        await refreshDerivedState()
    }

    // MARK: - Derived state

    /// Side label for one session's running copy.
    public func sideName(for session: ParkingSession) -> String? {
        if session.watchesBothSides { return "both sides" }
        return segments(for: session).first?.displaySideName
    }

    /// Notification context for one session. Car names only decorate copy
    /// when the household actually has several cars.
    public func context(for session: ParkingSession) -> NotificationPlanner.Context? {
        guard let segment = segments(for: session).first else { return nil }
        return NotificationPlanner.Context(
            segmentId: segment.id, street: segment.street,
            landmark: sideName(for: session), city: segment.city,
            sessionKey: sessions.count > 1 ? session.notificationKey + "." : "",
            carName: sessions.count > 1 ? session.carName : nil)
    }

    /// Recompute verdicts + notifications; called on park, move, correction,
    /// bundle refresh, significant time change, and every foreground (§8).
    public func refreshDerivedState() async {
        guard let bundle = try? bundleManager.openBundle(for: store.city),
              !sessions.isEmpty else {
            verdicts = [:]
            verdict = nil
            await scheduler.clearAll()
            reloadWidgets()
            liveActivity?.syncLiveActivity(session: nil, verdict: nil, context: nil)
            remindersBridge?.sync(deadline: nil, street: nil, sideName: nil)
            return
        }
        let holidays = bundle.holidays()
        var newVerdicts: [UUID: Verdict] = [:]
        var allPlanned: [NotificationPlanner.Planned] = []
        var mostUrgent: (session: ParkingSession, verdict: Verdict,
                         context: NotificationPlanner.Context)?

        for session in sessions {
            guard let context = context(for: session) else { continue }
            let rules = watchedRules(for: session)
            let v = VerdictEngine.verdict(rules: rules, city: context.city, at: clock.now,
                                          calendar: SweepCalendar.la, holidays: holidays)
            newVerdicts[session.id] = v
            allPlanned += NotificationPlanner.plan(
                context: context, windows: v.upcoming, prefs: store.reminderPrefs,
                now: clock.now, calendar: SweepCalendar.la, parkedAt: session.parkedAt)

            let start = v.next?.start ?? .distantFuture
            if mostUrgent == nil
                || start < (mostUrgent!.verdict.next?.start ?? .distantFuture) {
                mostUrgent = (session, v, context)
            }
        }

        verdicts = newVerdicts
        verdict = mostUrgent?.verdict
        await scheduler.reschedule(allPlanned.sorted { $0.fireDate < $1.fireDate })
        reloadWidgets()
        // Live Activity + Apple Reminders track the car that needs moving first.
        liveActivity?.syncLiveActivity(session: mostUrgent?.session,
                                       verdict: mostUrgent?.verdict,
                                       context: mostUrgent?.context)
        if store.appleRemindersEnabled, let urgent = mostUrgent {
            let name = [urgent.context.carName, urgent.context.landmark]
                .compactMap { $0 }.joined(separator: ", ")
            remindersBridge?.sync(deadline: urgent.verdict.next?.start,
                                  street: urgent.context.street,
                                  sideName: name.isEmpty ? nil : name)
        }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
