import SweepCore
import SwiftUI

@main
struct SweepApp: App {

    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    private let actionHandler = NotificationActionHandler()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .environmentObject(model.sessionManager)
                .environmentObject(model.plusStore)
                .tint(Tokens.clay)
                // v1 is light-only by design — paper is the brand (§7.1).
                .preferredColorScheme(.light)
                .onAppear {
                    actionHandler.model = model
                    UNUserNotificationCenter.current().delegate = actionHandler
                }
                .onOpenURL { _ in /* sweep://home — widgets deep link to parked home */ }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.onForeground()
            }
        }
    }
}

import UserNotifications
