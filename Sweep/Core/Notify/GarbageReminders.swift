import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Weekly bins reminders. Garbage day is a per-address constant the user
/// enters once, so these are repeating calendar notifications with their own
/// `sweep-bins.` prefix — parking reschedules (which wipe `sweep.`) never
/// touch them, and moving the car doesn't cancel trash night.
public struct RepeatingReminder: Equatable, Sendable {
    public let identifier: String
    /// 0=Sunday…6=Saturday, matching the rest of the app.
    public let weekday: Int
    public let hour: Int
    public let title: String
    public let body: String
}

public enum GarbageReminders {

    public static let identifierPrefix = "sweep-bins."
    public static let eveningId = identifierPrefix + "evening"
    public static let morningId = identifierPrefix + "morning"

    /// The two weekly reminders for a pickup weekday (0=Sunday…6=Saturday):
    /// bins-out the evening before at 8 PM, and a 7 AM pickup-day nudge.
    public static func plan(pickupWeekday: Int) -> [RepeatingReminder] {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday",
                    "Thursday", "Friday", "Saturday"]
        let evening = (pickupWeekday + 6) % 7   // the night before, wraps Sun→Sat
        return [
            RepeatingReminder(
                identifier: eveningId,
                weekday: evening, hour: 20,
                title: "Bins out tonight",
                body: "Garbage pickup is tomorrow (\(days[pickupWeekday])). "
                    + "Roll the carts out before the morning."),
            RepeatingReminder(
                identifier: morningId,
                weekday: pickupWeekday, hour: 7,
                title: "Pickup day",
                body: "The trucks come today — are the bins out?"),
        ]
    }
}

#if canImport(UserNotifications)
extension NotificationScheduler {
    /// Make the pending set match the setting: nil clears both reminders.
    public func syncGarbageReminders(pickupWeekday: Int?) async {
        await clearGarbageReminders()
        guard let pickupWeekday else { return }
        for reminder in GarbageReminders.plan(pickupWeekday: pickupWeekday) {
            await addRepeating(reminder)
        }
    }

    private func clearGarbageReminders() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [GarbageReminders.eveningId, GarbageReminders.morningId])
    }

    private func addRepeating(_ reminder: RepeatingReminder) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        var comps = DateComponents()
        comps.weekday = reminder.weekday + 1   // Calendar: 1=Sunday…7=Saturday
        comps.hour = reminder.hour
        comps.minute = 0
        comps.timeZone = SweepCalendar.la.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: reminder.identifier,
                                            content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
#endif
