import SweepCore
import SwiftUI

/// Home — parked state (§7.4). One card group per parked car; a single car
/// renders exactly as it always has, Plus households get a stacked garage.
struct ParkedHomeView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @EnvironmentObject var plusStore: PlusStore

    var body: some View {
        VStack(spacing: 14) {
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

            ForEach(sessionManager.sessions) { session in
                CarSessionView(session: session,
                               showCarName: sessionManager.sessions.count > 1)
            }

            if plusStore.hasPlus {
                NavigationLink {
                    LongestSpotView()
                } label: {
                    AlmanacCard {
                        HStack {
                            Text("Longest spot nearby")
                                .font(Tokens.display(17).weight(.medium))
                                .foregroundStyle(Tokens.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Tokens.sub)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}

/// Everything for one parked car: verdict, reminders, coming-up, actions.
struct CarSessionView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    let session: ParkingSession
    let showCarName: Bool

    @State private var showFixSign = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let segments = sessionManager.segments(for: session)
        let segment = segments.first
        let verdict = sessionManager.verdicts[session.id]
        let state = SweepFormat.uiState(verdict)
        let hasCorrection = segments.contains {
            OverrideDecorator.hasCorrection(segmentId: $0.id, overrides: model.store.overrides)
        }

        VStack(spacing: 14) {
            verdictCard(segment: segment, verdict: verdict, state: state,
                        hasCorrection: hasCorrection)
            remindersCard(verdict: verdict, segment: segment)
            comingUpCard(verdict: verdict)
            actionRow(segment: segment, verdict: verdict)

            // Single car: the moved button lives in the pinned bottom bar so
            // it always fits the screen. Multi-car keeps it per section to
            // say WHICH car moved.
            if showCarName {
                Button("I moved \(session.displayCarName)") {
                    sessionManager.clearSession(id: session.id)
                }
                .buttonStyle(ClayButtonStyle(background: Tokens.ink, foreground: Tokens.paper))
            }
        }
        .onReceive(tick) { now = $0 }
        .sheet(isPresented: $showFixSign) {
            if let segment {
                FixSignView(segment: segment)
            }
        }
    }

    // MARK: - Watched-side helpers

    private var watchesBothSides: Bool { session.watchesBothSides }

    private var sideText: String {
        sessionManager.sideName(for: session) ?? ""
    }

    private var watchedRules: [ScheduleRule] {
        sessionManager.watchedRules(for: session)
    }

    /// Rules reordered so the one producing `next` leads — the schedule line
    /// then matches the headline instead of an arbitrary first pattern.
    private func orderedForDisplay(_ rules: [ScheduleRule], next: SweepWindow?) -> [ScheduleRule] {
        guard let next else { return rules }
        let cal = SweepCalendar.la
        let weekday = cal.component(.weekday, from: next.start) - 1
        let hour = cal.component(.hour, from: next.start)
        return rules.sorted { a, b in
            let aLeads = a.weekday == weekday && a.fromHour == hour
            let bLeads = b.weekday == weekday && b.fromHour == hour
            if aLeads != bLeads { return aLeads }
            return (a.weekday, a.fromHour) < (b.weekday, b.fromHour)
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
                    if showCarName {
                        PillTag(session.displayCarName, color: Tokens.sub)
                    }
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
                    (Text("\(segment.street) · \(sideText.lowercased()) · sweep in ")
                        + Text(SweepFormat.countdown(to: next.start, from: now))
                            .font(Tokens.displayItalic(15, relativeTo: .subheadline)))
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.sub)
                }

                if !watchedRules.isEmpty {
                    Text(footerLine(rules: orderedForDisplay(watchedRules, next: verdict?.next),
                                    verdict: verdict))
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.sub)
                }

                // §1.3: stale data degrades the copy honestly instead of
                // presenting a year-old schedule with full confidence.
                if let builtAt = (try? model.bundleManager.openBundle(for: sessionManager.city))?
                        .manifest.builtAt,
                   let stale = SweepFormat.staleNotice(builtAt: builtAt, now: model.clock.now) {
                    Text(stale)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Tokens.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center) {
                    Text("Always check the posted sign.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.clay)
                    Spacer()
                    // What the pole should say — eyeball-match it. Skipped in
                    // both-sides mode: each side has its own sign.
                    if let segment, !watchesBothSides {
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
    private func remindersCard(verdict: Verdict?, segment: SweepBundle.Segment?) -> some View {
        if let verdict, segment != nil,
           let context = sessionManager.context(for: session) {
            let planned = NotificationPlanner.plan(
                context: context, windows: verdict.upcoming, prefs: model.store.reminderPrefs,
                now: session.parkedAt, calendar: SweepCalendar.la,
                parkedAt: session.parkedAt)
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
            // A correction belongs to ONE side's sign; in both-sides mode the
            // app doesn't know which, so the flow steps back.
            if !watchesBothSides {
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
        }
        .foregroundStyle(Tokens.ink)
    }

    private func shareText(segment: SweepBundle.Segment, next: SweepWindow) -> String {
        let subject = showCarName ? session.displayCarName.capitalized : "The car"
        return "\(subject) is on \(segment.street) (\(sideText.lowercased())). "
            + "Safe until \(SweepFormat.dayName(next.start)) "
            + "\(SweepFormat.hourLabel(next.start)) — Sweep"
    }
}
