import SweepCore
import SwiftUI

/// Home — parked state (§7.4).
struct ParkedHomeView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @State private var showFixSign = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let segment = sessionManager.currentSegment()
        let verdict = sessionManager.verdict
        let state = SweepFormat.uiState(verdict)
        let hasCorrection = segment.map {
            OverrideDecorator.hasCorrection(segmentId: $0.id, overrides: model.store.overrides)
        } ?? false

        VStack(spacing: 14) {
            verdictCard(segment: segment, verdict: verdict, state: state,
                        hasCorrection: hasCorrection)

            if model.notificationsDenied {
                AlmanacCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminders are off — Sweep can't warn you before the sweeper comes")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Tokens.rust)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                }
            }

            remindersCard(verdict: verdict)
            comingUpCard(verdict: verdict)
            actionRow(segment: segment, verdict: verdict)

            Button("I moved my car") {
                sessionManager.clearSession()
            }
            .buttonStyle(ClayButtonStyle(background: Tokens.ink, foreground: Tokens.paper))
        }
        .padding(16)
        .onReceive(tick) { now = $0 }
        .sheet(isPresented: $showFixSign) {
            if let segment {
                FixSignView(segment: segment)
            }
        }
    }

    // MARK: - Verdict card

    @ViewBuilder
    private func verdictCard(segment: SweepBundle.Segment?, verdict: Verdict?,
                             state: VerdictStateUI, hasCorrection: Bool) -> some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusBadge(state: state)
                    Spacer()
                    if hasCorrection {
                        PillTag("your sign")
                    }
                }

                Text(headline(verdict: verdict, state: state))
                    .font(Tokens.verdictHeadline)
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if state == .sweepingNow {
                    Text("likely a $\(sessionManager.city.fine) ticket if it hasn't passed")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.rust)
                }

                if let segment, let next = verdict?.next {
                    (Text("\(segment.street) · \((segment.displaySideName ?? "").lowercased()) · sweep in ")
                        + Text(SweepFormat.countdown(to: next.start, from: now))
                            .font(Tokens.displayItalic(15, relativeTo: .subheadline)))
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.sub)
                }

                if let segment {
                    let rules = sessionManager.effectiveRules(for: segment)
                    Text(footerLine(rules: rules, verdict: verdict))
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.sub)
                }

                HStack(alignment: .center) {
                    Text("Always check the posted sign.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.clay)
                    Spacer()
                    if let segment {
                        // What the pole should say — eyeball-match it.
                        SignPreview(lines: SweepFormat.signLines(
                            rules: sessionManager.effectiveRules(for: segment)))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func headline(verdict: Verdict?, state: VerdictStateUI) -> String {
        guard let verdict, let next = verdict.next else {
            return "Nothing scheduled here"
        }
        let hour = SweepFormat.hourLabel(next.start)
        switch state {
        case .safe:
            return "Safe until \(SweepFormat.dayName(next.start)) \(hour)"
        case .moveSoon:
            let cal = SweepCalendar.la
            let today = cal.isDate(next.start, inSameDayAs: now)
            return "Move by \(hour) \(today ? "today" : "tomorrow")"
        case .sweepingNow:
            return "Sweeping until \(SweepFormat.hourLabel(next.end))"
        case .none:
            return "Nothing scheduled here"
        }
    }

    private func footerLine(rules: [ScheduleRule], verdict: Verdict?) -> String {
        var line = SweepFormat.scheduleLine(rules: rules)
        if let next = verdict?.next, next.holidayButEnforced {
            line += " · holiday, but this city still sweeps"
        }
        return line
    }

    // MARK: - Reminders card

    @ViewBuilder
    private func remindersCard(verdict: Verdict?) -> some View {
        if let verdict, let segment = sessionManager.currentSegment() {
            let context = NotificationPlanner.Context(
                segmentId: segment.id, street: segment.street,
                landmark: segment.displaySideName, city: segment.city)
            let planned = NotificationPlanner.plan(
                context: context, windows: verdict.upcoming, prefs: model.store.reminderPrefs,
                now: sessionManager.session?.parkedAt ?? now, calendar: SweepCalendar.la)
            if !planned.isEmpty {
                AlmanacCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminders")
                            .font(Tokens.display(17).weight(.medium))
                            .foregroundStyle(Tokens.ink)
                        ForEach(planned, id: \.identifier) { p in
                            HStack {
                                Image(systemName: "bell")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.fireDate < now ? Tokens.line : Tokens.clay)
                                Text("\(SweepFormat.dayName(p.fireDate)) "
                                     + "\(SweepFormat.shortDate(p.fireDate)), "
                                     + "\(SweepFormat.hourLabel(p.fireDate)) — \(p.title)")
                                    .font(.system(size: 13.5))
                                    .strikethrough(p.fireDate < now)
                                    .foregroundStyle(p.fireDate < now ? Tokens.sub : Tokens.ink)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Coming up card

    @ViewBuilder
    private func comingUpCard(verdict: Verdict?) -> some View {
        if let verdict, !verdict.upcoming.isEmpty {
            AlmanacCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coming up")
                        .font(Tokens.display(17).weight(.medium))
                        .foregroundStyle(Tokens.ink)
                    ForEach(Array(verdict.upcoming.prefix(3).enumerated()), id: \.offset) { _, w in
                        HStack {
                            Text("\(SweepFormat.dayName(w.start)) \(SweepFormat.shortDate(w.start)), "
                                 + "\(SweepFormat.hourLabel(w.start))–\(SweepFormat.hourLabel(w.end))")
                                .font(.system(size: 13.5))
                                .foregroundStyle(w.suspendedForHoliday ? Tokens.sage : Tokens.ink)
                            Spacer()
                            if w.suspendedForHoliday {
                                Text("holiday — no sweeping")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Tokens.sage)
                            } else if w.holidayButEnforced {
                                Text("holiday, still sweeps")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Tokens.amber)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionRow(segment: SweepBundle.Segment?, verdict: Verdict?) -> some View {
        HStack(spacing: 10) {
            if let segment, let next = verdict?.next {
                ShareLink(item: shareText(segment: segment, next: next)) {
                    Label("Share the spot", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                            .strokeBorder(Tokens.line))
                }
            }
            Button {
                showFixSign = true
            } label: {
                Text("Sign says otherwise?")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                        .strokeBorder(Tokens.line))
            }
        }
        .foregroundStyle(Tokens.ink)
    }

    private func shareText(segment: SweepBundle.Segment, next: SweepWindow) -> String {
        "The car is on \(segment.street) (\((segment.displaySideName ?? "").lowercased())). "
            + "Safe until \(SweepFormat.dayName(next.start)) "
            + "\(SweepFormat.hourLabel(next.start)) — Sweep"
    }
}
