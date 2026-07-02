import SweepCore
import SwiftUI

// MARK: - AlmanacCard: the standard paper card surface

public struct AlmanacCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                    .fill(Tokens.card)
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                        .strokeBorder(Tokens.line, lineWidth: 1)))
    }
}

// MARK: - Status dot + word

public struct StatusBadge: View {
    let state: VerdictStateUI

    public init(state: VerdictStateUI) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Tokens.statusColor(state))
                .frame(width: 8, height: 8)
            Text(state.word)
                .font(Tokens.statusWord)
                .foregroundStyle(Tokens.statusColor(state))
                .textCase(.uppercase)
                .kerning(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pill tag ("your sign", etc.)

public struct PillTag: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = Tokens.clay) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }
}

// MARK: - Primary button

public struct ClayButtonStyle: ButtonStyle {
    let background: Color

    public init(background: Color = Tokens.clay) {
        self.background = background
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusControl, style: .continuous)
                .fill(background.opacity(configuration.isPressed ? 0.85 : 1)))
    }
}

// MARK: - SidePicker card (§7.3)

public struct SideCard: View {
    let landmark: String
    let hint: String?
    let doors: String?
    let miniVerdict: String
    let miniState: VerdictStateUI
    let selected: Bool
    let onTap: () -> Void

    public init(landmark: String, hint: String?, doors: String?, miniVerdict: String,
                miniState: VerdictStateUI, selected: Bool, onTap: @escaping () -> Void) {
        self.landmark = landmark
        self.hint = hint
        self.doors = doors
        self.miniVerdict = miniVerdict
        self.miniState = miniState
        self.selected = selected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                Text(landmark)
                    .font(Tokens.display(17, relativeTo: .body).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                if let hint {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.sub)
                }
                if let doors {
                    Text(doors)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Tokens.sub)
                }
                HStack(spacing: 5) {
                    Circle().fill(Tokens.statusColor(miniState)).frame(width: 7, height: 7)
                    Text(miniVerdict)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Tokens.statusColor(miniState))
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Tokens.radiusSideCard, style: .continuous)
                    .fill(Tokens.card)
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSideCard, style: .continuous)
                        .strokeBorder(selected ? Tokens.clay : Tokens.line,
                                      lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? Tokens.clay.opacity(0.13) : .clear,
                            radius: 3, y: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel([landmark, hint, doors, miniVerdict]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Formatting helpers shared by app + widgets

public enum SweepFormat {

    public static func hourLabel(_ date: Date, calendar: Calendar = SweepCalendar.la) -> String {
        NotificationPlanner.hourLabel(date, calendar)
    }

    public static func dayName(_ date: Date, calendar: Calendar = SweepCalendar.la) -> String {
        NotificationPlanner.dayName(date, calendar)
    }

    /// "Jul 10" — disambiguates rows that share a weekday (LA wall-clock).
    public static func shortDate(_ date: Date, calendar: Calendar = SweepCalendar.la) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(months[c.month! - 1]) \(c.day!)"
    }

    /// "6d 4h" / "14h" / "35m" countdown text.
    public static func countdown(to target: Date, from now: Date) -> String {
        let seconds = max(0, target.timeIntervalSince(now))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    /// Footer schedule line: "Tuesdays, 8–10 AM · 1st & 3rd weeks" (§7.4).
    public static func scheduleLine(rules: [ScheduleRule], calendar: Calendar = SweepCalendar.la) -> String {
        guard let rule = rules.first else { return "No posted schedule" }
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let day = days[rule.weekday] + "s"
        let hours = "\(hourText(rule.fromHour))–\(hourText(rule.toHour))"
        if let weeks = rule.weeks {
            let ordinals = ["1st", "2nd", "3rd", "4th", "5th"]
            let label = weeks.compactMap { $0 >= 1 && $0 <= 5 ? ordinals[$0 - 1] : nil }
                .joined(separator: " & ")
            return "\(day), \(hours) · \(label) weeks"
        }
        return "\(day), \(hours) · every week"
    }

    public static func hourText(_ hour: Int) -> String {
        switch hour {
        case 0, 24: return "12 AM"
        case 12: return "12 PM"
        case ..<12: return "\(hour) AM"
        default: return "\(hour - 12) PM"
        }
    }

    public static func uiState(_ verdict: Verdict?) -> VerdictStateUI {
        guard let verdict, verdict.next != nil else { return .none }
        switch verdict.state {
        case .safe: return .safe
        case .moveSoon: return .moveSoon
        case .sweepingNow: return .sweepingNow
        }
    }

    /// Mini-verdict phrase for side cards: "safe 6d" / "sweep in 14h" / "sweeping now".
    public static func miniVerdict(_ verdict: Verdict, now: Date) -> String {
        guard let next = verdict.next else { return "no sweeping posted" }
        switch verdict.state {
        case .sweepingNow: return "sweeping now"
        case .moveSoon: return "sweep in \(countdown(to: next.start, from: now))"
        case .safe: return "safe \(countdown(to: next.start, from: now))"
        }
    }
}
