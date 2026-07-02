import ActivityKit
import Foundation

/// Live Activity content (§9). Compiled into both the app and the widget
/// extension. The countdown renders natively via Text(timerInterval:) —
/// zero updates, no push tokens.
struct SweepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var street: String
        var landmark: String?
        var start: Date
        var end: Date
        var fine: Int
    }

    var segmentId: String
}
