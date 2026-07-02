import ActivityKit
import SweepCore
import SwiftUI
import WidgetKit

/// Live Activity UI (§9). Countdown uses Text(timerInterval:) so it renders
/// natively with zero updates. Stages: counting down (amber inside T−2h) →
/// "Sweeping now" (rust, timer to end).
struct SweepLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SweepActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(Tokens.card)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityDot(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        ActivityHeadline(state: context.state)
                        Text(context.state.street)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimer(state: context.state)
                        .frame(width: 60)
                }
            } compactLeading: {
                ActivityDot(state: context.state)
            } compactTrailing: {
                ActivityTimer(state: context.state)
                    .frame(width: 48)
            } minimal: {
                ActivityDot(state: context.state)
            }
        }
    }
}

private func isSweeping(_ state: SweepActivityAttributes.ContentState) -> Bool {
    let now = Date()
    return now >= state.start && now < state.end
}

private func isUrgent(_ state: SweepActivityAttributes.ContentState) -> Bool {
    state.start.timeIntervalSinceNow <= 2 * 3600
}

struct ActivityDot: View {
    let state: SweepActivityAttributes.ContentState

    var body: some View {
        Circle()
            .fill(isSweeping(state) ? Tokens.rust : (isUrgent(state) ? Tokens.amber : Tokens.sage))
            .frame(width: 10, height: 10)
    }
}

struct ActivityTimer: View {
    let state: SweepActivityAttributes.ContentState

    var body: some View {
        if isSweeping(state) {
            Text(timerInterval: Date()...state.end, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(Tokens.rust)
        } else {
            Text(timerInterval: Date()...state.start, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(isUrgent(state) ? Tokens.amber : Tokens.ink)
        }
    }
}

struct ActivityHeadline: View {
    let state: SweepActivityAttributes.ContentState

    var body: some View {
        if isSweeping(state) {
            Text("Sweeping now")
                .font(Tokens.display(17).weight(.semibold))
                .foregroundStyle(Tokens.rust)
        } else {
            Text("Move by \(SweepFormat.hourLabel(state.start))")
                .font(Tokens.display(17).weight(.semibold))
                .foregroundStyle(Tokens.ink)
        }
    }
}

/// Lock screen: status dot + serif headline + street line + live timer (§9).
struct LockScreenActivityView: View {
    let state: SweepActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ActivityDot(state: state)
            VStack(alignment: .leading, spacing: 3) {
                ActivityHeadline(state: state)
                Text(state.landmark.map { "\(state.street) · \($0.lowercased())" } ?? state.street)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.sub)
                if isSweeping(state) {
                    Text("likely a $\(state.fine) ticket if it hasn't passed")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.rust)
                }
            }
            Spacer()
            ActivityTimer(state: state)
                .font(.system(size: 22, weight: .semibold))
        }
        .padding(14)
    }
}
