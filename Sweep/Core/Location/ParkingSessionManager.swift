import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Hook for the app target to start/stop the Live Activity (§9) — ActivityKit
/// is iOS-only, so the controller lives in the app, not in SweepCore.
public protocol LiveActivityControlling: AnyObject {
    func syncLiveActivity(session: ParkingSession?, verdict: Verdict?, context: NotificationPlanner.Context?)
}

/// Owns the single parking session (§6.3). On set/clear: recompute verdict,
/// reschedule notifications, refresh widgets, sync the Live Activity.
@MainActor
public final class ParkingSessionManager: ObservableObject {

    @Published public private(set) var session: ParkingSession?
    @Published public private(set) var verdict: Verdict?

    public weak var liveActivity: LiveActivityControlling?

    private let store: PersistenceStore
    private let bundleManager: BundleManager
    private let scheduler: NotificationScheduler
    public var clock: Clock

    public init(store: PersistenceStore, bundleManager: BundleManager,
                scheduler: NotificationScheduler, clock: Clock = SystemClock()) {
        self.store = store
        self.bundleManager = bundleManager
        self.scheduler = scheduler
        self.clock = clock
        self.session = store.session
    }

    public var city: City {
        get { store.city }
        set {
            store.city = newValue
            clearSession()   // switching cities clears the session (§7.6)
        }
    }

    public func currentSegment() -> SweepBundle.Segment? {
        guard let session, let bundle = try? bundleManager.openBundle(for: store.city) else {
            return nil
        }
        return bundle.segment(id: session.segmentId)
    }

    public func effectiveRules(for segment: SweepBundle.Segment) -> [ScheduleRule] {
        OverrideDecorator.effectiveRules(segment: segment, overrides: store.overrides)
    }

    public func park(segment: SweepBundle.Segment, source: ParkingSession.Source) async {
        let s = ParkingSession(segmentId: segment.id,
                               blockId: segment.blockKey,
                               sideKey: segment.sideKey,
                               parkedAt: clock.now,
                               source: source)
        store.session = s
        session = s
        await refreshDerivedState()
    }

    public func clearSession() {
        store.session = nil
        session = nil
        verdict = nil
        Task {
            await scheduler.clearAll()
            reloadWidgets()
            liveActivity?.syncLiveActivity(session: nil, verdict: nil, context: nil)
        }
    }

    public func saveCorrection(_ override: ScheduleRuleOverride, for segmentId: String) async {
        var all = store.overrides
        all[segmentId] = override
        store.overrides = all
        await refreshDerivedState()
    }

    /// Recompute verdict + notifications; called on park, correction, bundle
    /// refresh, significant time change, and every foreground (§8).
    public func refreshDerivedState() async {
        guard let session, let bundle = try? bundleManager.openBundle(for: store.city),
              let segment = bundle.segment(id: session.segmentId) else {
            verdict = nil
            await scheduler.clearAll()
            reloadWidgets()
            liveActivity?.syncLiveActivity(session: nil, verdict: nil, context: nil)
            return
        }
        let rules = effectiveRules(for: segment)
        let holidays = bundle.holidays()
        let v = VerdictEngine.verdict(rules: rules, city: segment.city, at: clock.now,
                                      calendar: SweepCalendar.la, holidays: holidays)
        verdict = v

        let context = NotificationPlanner.Context(
            segmentId: segment.id, street: segment.street,
            landmark: segment.landmark, city: segment.city)
        let planned = NotificationPlanner.plan(
            context: context, windows: v.upcoming, prefs: store.reminderPrefs,
            now: clock.now, calendar: SweepCalendar.la)
        await scheduler.reschedule(planned)
        reloadWidgets()
        liveActivity?.syncLiveActivity(session: session, verdict: v, context: context)
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
