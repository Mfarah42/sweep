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
                .id(model.themeId)   // repaint everything on theme change
                .environmentObject(model)
                .environmentObject(model.sessionManager)
                .environmentObject(model.plusStore)
                .tint(Tokens.clay)
                // nil follows the system; Settings offers Light/Dark overrides.
                .preferredColorScheme(model.colorScheme)
                .onAppear {
                    actionHandler.model = model
                    UNUserNotificationCenter.current().delegate = actionHandler
                }
                .onOpenURL { url in
                    // sweep://home just foregrounds; sweep://park jumps into
                    // the park flow (same path as the Action Button intent).
                    if url.host == "park" {
                        NotificationCenter.default.post(name: .sweepStartParkFlow, object: nil)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.onForeground()
            }
        }
    }
}

import UserNotifications
