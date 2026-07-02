import BackgroundTasks
import Foundation
import SweepCore
import SwiftUI

/// Composition root: wires stores, bundles, notifications, background refresh.
@MainActor
final class AppModel: ObservableObject {

    let store: PersistenceStore
    let bundleManager: BundleManager
    let scheduler: NotificationScheduler
    let sessionManager: ParkingSessionManager
    let plusStore: PlusStore
    let liveActivity = LiveActivityController()

    /// Demo mode (§7.6): hidden time-scrub clock for QA. Nil = real time.
    @Published var demoClock: FixedClock? {
        didSet {
            sessionManager.clock = demoClock ?? SystemClock()
            Task { await sessionManager.refreshDerivedState() }
        }
    }

    @Published var notificationsDenied = false

    var clock: Clock { demoClock ?? SystemClock() }

    init() {
        store = PersistenceStore.appGroup()
        bundleManager = BundleManager.appGroup()
            ?? BundleManager(containerDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("bundles"))
        let client = SystemNotificationClient()
        scheduler = NotificationScheduler(client: client)
        sessionManager = ParkingSessionManager(store: store, bundleManager: bundleManager,
                                               scheduler: scheduler)
        plusStore = PlusStore(store: store)
        sessionManager.liveActivity = liveActivity
        client.registerCategories()

        bundleManager.installShippedBundles(from: .main)
        registerBackgroundRefresh()

        NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.sessionManager.refreshDerivedState() }
            }
    }

    func onForeground() {
        Task {
            await sessionManager.refreshDerivedState()
            await refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }

    // MARK: - Background bundle refresh (§4.7)

    private func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BundleManager.refreshTaskIdentifier, using: nil) { [weak self] task in
                guard let self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    let refreshed = await self.bundleManager.refreshFromRemote()
                    if refreshed {
                        await self.sessionManager.refreshDerivedState()
                    }
                    task.setTaskCompleted(success: true)
                    self.scheduleBackgroundRefresh()
                }
            }
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BundleManager.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 7 * 24 * 3600)   // ~weekly
        try? BGTaskScheduler.shared.submit(request)
    }
}

import UserNotifications

/// Handles notification actions (§8): "I moved it" clears the session,
/// "Snooze 15 min" reschedules a one-off.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {

    weak var model: AppModel?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let model else { return }
        switch response.actionIdentifier {
        case NotificationScheduler.actionMoved:
            await MainActor.run { model.sessionManager.clearSession() }
        case NotificationScheduler.actionSnooze:
            let content = response.notification.request.content
            let planned = NotificationPlanner.Planned(
                identifier: response.notification.request.identifier,
                fireDate: Date(), title: content.title, body: content.body,
                offset: .thirtyMin, timeSensitive: true)
            await model.scheduler.snooze(planned, now: Date())
        default:
            break
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
