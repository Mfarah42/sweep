import AppIntents
import Foundation

/// "I just parked" without unlocking anything: assignable to the Action
/// Button, invokable by Siri ("I just parked in Sweep"), and offered in
/// Shortcuts/Spotlight. Opens the app straight into the park flow — locating
/// needs the UI (side question, notification prompt).
struct ParkIntent: AppIntent {
    static let title: LocalizedStringResource = "I Just Parked"
    static let description = IntentDescription(
        "Finds your block and sets street-sweeping reminders.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .sweepStartParkFlow, object: nil)
        return .result()
    }
}

extension Notification.Name {
    /// Fired by ParkIntent (and sweep://park) once the app is frontmost.
    static let sweepStartParkFlow = Notification.Name("sweepStartParkFlow")
}

struct SweepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ParkIntent(),
            phrases: [
                "I just parked in \(.applicationName)",
                "Tell \(.applicationName) I parked",
            ],
            shortTitle: "I Just Parked",
            systemImageName: "car.fill")
    }
}
