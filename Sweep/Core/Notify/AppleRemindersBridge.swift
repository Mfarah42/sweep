import Foundation
#if canImport(EventKit)
import EventKit
#endif

/// Optional mirror of the move-by deadline into the Apple Reminders app, for
/// people who live in Reminders (Siri, CarPlay, shared lists). Opt-in from
/// Settings; Sweep's own notifications remain the primary alarm and work
/// without this. One reminder at a time — upserted on park/reschedule,
/// removed on "I moved my car".
public final class AppleRemindersBridge {

    private let store: PersistenceStore
    #if canImport(EventKit)
    private let eventStore = EKEventStore()
    #endif

    public init(store: PersistenceStore) {
        self.store = store
    }

    public func requestAccess() async -> Bool {
        #if canImport(EventKit)
        return (try? await eventStore.requestFullAccessToReminders()) ?? false
        #else
        return false
        #endif
    }

    /// Make the Reminders app match the session: a deadline upserts the one
    /// Sweep reminder; nil removes it.
    public func sync(deadline: Date?, street: String?, sideName: String?) {
        #if canImport(EventKit)
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }

        let existing = store.appleReminderId.flatMap {
            eventStore.calendarItem(withIdentifier: $0) as? EKReminder
        }
        guard let deadline else {
            if let existing {
                try? eventStore.remove(existing, commit: true)
            }
            store.appleReminderId = nil
            return
        }

        let reminder = existing ?? EKReminder(eventStore: eventStore)
        if reminder.calendar == nil {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }
        let place = [street, sideName?.lowercased()].compactMap { $0 }.joined(separator: ", ")
        reminder.title = place.isEmpty ? "Move the car" : "Move the car — \(place)"
        reminder.notes = "Street sweeping. Added by Sweep."
        reminder.dueDateComponents = SweepCalendar.la.dateComponents(
            [.year, .month, .day, .hour, .minute, .timeZone], from: deadline)
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        // Alarm at last-call time; the due date itself shows in the list.
        reminder.addAlarm(EKAlarm(absoluteDate: deadline.addingTimeInterval(-30 * 60)))
        if (try? eventStore.save(reminder, commit: true)) != nil {
            store.appleReminderId = reminder.calendarItemIdentifier
        }
        #endif
    }
}
