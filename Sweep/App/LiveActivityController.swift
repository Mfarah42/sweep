import ActivityKit
import Foundation
import SweepCore

/// Starts/stops the Live Activity (§9): begins when next.start − now ≤ 8 h
/// (ActivityKit lifetime budget); ends at window end via dismissal policy so
/// the app doesn't need to be running.
final class LiveActivityController: LiveActivityControlling {

    static let leadTime: TimeInterval = 8 * 3600

    func syncLiveActivity(session: ParkingSession?, verdict: Verdict?,
                          context: NotificationPlanner.Context?) {
        Task { await sync(session: session, verdict: verdict, context: context) }
    }

    private func sync(session: ParkingSession?, verdict: Verdict?,
                      context: NotificationPlanner.Context?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let current = Activity<SweepActivityAttributes>.activities.first

        guard let session, let context, let next = verdict?.next,
              next.start.timeIntervalSinceNow <= Self.leadTime,
              next.end.timeIntervalSinceNow > 0 else {
            // No session, or the next window is too far out — end anything live.
            if let current {
                await current.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let state = SweepActivityAttributes.ContentState(
            street: context.street, landmark: context.landmark,
            start: next.start, end: next.end, fine: context.city.fine)
        let content = ActivityContent(state: state, staleDate: next.end)

        if let current {
            if current.attributes.segmentId == session.segmentId {
                await current.update(content)
            } else {
                await current.end(nil, dismissalPolicy: .immediate)
                try? Activity.request(
                    attributes: SweepActivityAttributes(segmentId: session.segmentId),
                    content: content)
            }
        } else {
            try? Activity.request(
                attributes: SweepActivityAttributes(segmentId: session.segmentId),
                content: content)
        }
    }
}
