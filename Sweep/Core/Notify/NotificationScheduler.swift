import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Thin seam over UNUserNotificationCenter so §13.8 can run against a fake.
public protocol NotificationClient {
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String]) async
    func add(_ planned: NotificationPlanner.Planned) async
    func registerCategories()
}

/// Schedules the planner's output (spec §8). Reschedules are idempotent:
/// remove everything with the `sweep.` prefix, then re-add.
public final class NotificationScheduler {

    public static let categoryId = "SWEEP_ALERT"
    public static let actionMoved = "SWEEP_MOVED"
    public static let actionSnooze = "SWEEP_SNOOZE_15"

    private let client: NotificationClient

    public init(client: NotificationClient) {
        self.client = client
    }

    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        await client.requestAuthorization()
    }

    public func reschedule(_ planned: [NotificationPlanner.Planned]) async {
        let stale = await client.pendingIdentifiers()
            .filter { $0.hasPrefix(NotificationPlanner.identifierPrefix) }
        await client.removePending(identifiers: stale)
        for p in planned {
            await client.add(p)
        }
    }

    public func clearAll() async {
        await reschedule([])
    }

    /// One-off snooze (§8 actions): re-deliver in 15 minutes.
    public func snooze(_ planned: NotificationPlanner.Planned, now: Date) async {
        let again = NotificationPlanner.Planned(
            identifier: planned.identifier + ".snooze",
            fireDate: now.addingTimeInterval(15 * 60),
            title: planned.title, body: planned.body,
            offset: planned.offset, timeSensitive: planned.timeSensitive)
        await client.add(again)
    }
}

#if canImport(UserNotifications)
public final class SystemNotificationClient: NotificationClient {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func add(_ planned: NotificationPlanner.Planned) async {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        content.categoryIdentifier = NotificationScheduler.categoryId
        if planned.timeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        // Calendar trigger in LA wall-clock (§8) — survives timezone travel.
        let comps = SweepCalendar.la.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .timeZone], from: planned.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: planned.identifier,
                                            content: content, trigger: trigger)
        try? await center.add(request)
    }

    public func registerCategories() {
        let moved = UNNotificationAction(identifier: NotificationScheduler.actionMoved,
                                         title: "I moved it")
        let snooze = UNNotificationAction(identifier: NotificationScheduler.actionSnooze,
                                          title: "Snooze 15 min")
        let category = UNNotificationCategory(identifier: NotificationScheduler.categoryId,
                                              actions: [moved, snooze],
                                              intentIdentifiers: [])
        center.setNotificationCategories([category])
    }
}
#endif
