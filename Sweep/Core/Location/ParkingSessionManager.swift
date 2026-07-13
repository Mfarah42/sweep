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
    /// Optional opt-in mirror into the Apple Reminders app.
    public var remindersBridge: AppleRemindersBridge?

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

    /// All watched segments — one normally, two in "both sides" mode.
    public func currentSegments() -> [SweepBundle.Segment] {
        guard let session, let bundle = try? bundleManager.openBundle(for: store.city) else {
            return []
        }
        return session.segmentIds.compactMap { bundle.segment(id: $0) }
    }

    public func effectiveRules(for segment: SweepBundle.Segment) -> [ScheduleRule] {
        OverrideDecorator.effectiveRules(segment: segment, overrides: store.overrides)
    }

    public func park(segment: SweepBundle.Segment, source: ParkingSession.Source) async {
        await park(segments: [segment], source: source)
    }

    /// Two segments = resident "both sides" mode: reminders for every sweep
    /// on the block, whichever side the car is on.
    public func park(segments: [SweepBundle.Segment], source: ParkingSession.Source) async {
        guard let primary = segments.first else { return }
        let s = ParkingSession(segmentId: primary.id,
                               blockId: primary.blockKey,
                               sideKey: primary.sideKey,
                               parkedAt: clock.now,
                               source: source,
                               secondarySegmentId: segments.dropFirst().first?.id)
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
            remindersBridge?.sync(deadline: nil, street: nil, sideName: nil)
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
        let segments = currentSegments()
        guard let session, let bundle = try? bundleManager.openBundle(for: store.city),
              let segment = segments.first else {
            verdict = nil
            await scheduler.clearAll()
            reloadWidgets()
            liveActivity?.syncLiveActivity(session: nil, verdict: nil, context: nil)
            remindersBridge?.sync(deadline: nil, street: nil, sideName: nil)
            return
        }
        // "Both sides": the union of the sides' rules drives everything —
        // the app doesn't know which side the car is on, so it must warn
        // for whichever sweep comes first.
        let rules = Array(Set(segments.flatMap { effectiveRules(for: $0) }))
        let holidays = bundle.holidays()
        let v = VerdictEngine.verdict(rules: rules, city: segment.city, at: clock.now,
                                      calendar: SweepCalendar.la, holidays: holidays)
        verdict = v

        let sideName = segments.count > 1 ? "both sides" : segment.displaySideName
        let context = NotificationPlanner.Context(
            segmentId: segment.id, street: segment.street,
            landmark: sideName, city: segment.city)
        let planned = NotificationPlanner.plan(
            context: context, windows: v.upcoming, prefs: store.reminderPrefs,
            now: clock.now, calendar: SweepCalendar.la, parkedAt: session.parkedAt)
        await scheduler.reschedule(planned)
        reloadWidgets()
        liveActivity?.syncLiveActivity(session: session, verdict: v, context: context)
        if store.appleRemindersEnabled {
            remindersBridge?.sync(deadline: v.next?.start, street: segment.street,
                                  sideName: sideName)
        }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
