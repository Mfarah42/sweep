import SweepCore
import SwiftUI
import WidgetKit

/// Home/lock screen widgets (§9): verdict word + "until {Day} {h}" + street.
/// Timeline entries at every state transition, reading session + bundle from
/// the App Group. Tapping deep-links into the parked home screen.
struct SweepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SweepWidget", provider: SweepTimelineProvider()) { entry in
            SweepWidgetView(entry: entry)
                .widgetURL(URL(string: "sweep://home"))
        }
        .configurationDisplayName("Sweep")
        .description("Is the car safe where it's parked?")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct SweepEntry: TimelineEntry {
    let date: Date
    let state: VerdictStateUI
    let untilText: String
    let street: String
    /// The deadline: next sweep start (or end, while sweeping). Rendered with
    /// a self-updating relative countdown — "the last day to move the car".
    var moveBy: Date?
}

struct SweepTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> SweepEntry {
        SweepEntry(date: Date(), state: .safe, untilText: "until Tue 8 AM", street: "9th Ave")
    }

    func getSnapshot(in context: Context, completion: @escaping (SweepEntry) -> Void) {
        completion(entry(at: Date()) ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SweepEntry>) -> Void) {
        let now = Date()
        let segments = currentSegments()
        guard let segment = segments.first else {
            let empty = SweepEntry(date: now, state: .none, untilText: "Not parked", street: "")
            completion(Timeline(entries: [empty], policy: .never))
            return
        }
        let store = PersistenceStore.appGroup()
        let holidays = bundle()?.holidays() ?? .empty
        let rules = Array(Set(segments.flatMap {
            OverrideDecorator.effectiveRules(segment: $0, overrides: store.overrides)
        }))
        let windows = VerdictEngine.upcomingWindows(rules: rules, city: segment.city, from: now,
                                                    count: 5, calendar: SweepCalendar.la,
                                                    holidays: holidays)
            .filter { !$0.suspendedForHoliday }

        // Entries at every state transition (§9): now, start−12h, start, end, +futures.
        var moments: Set<Date> = [now]
        for w in windows.prefix(4) {
            moments.insert(w.start.addingTimeInterval(-12 * 3600))
            moments.insert(w.start)
            moments.insert(w.end)
        }
        let entries = moments.sorted().filter { $0 >= now }
            .compactMap { entry(at: $0) }
        completion(Timeline(entries: entries.isEmpty ? [placeholder(in: context)] : entries,
                            policy: .atEnd))
    }

    private func bundle() -> SweepBundle? {
        guard let manager = BundleManager.appGroup() else { return nil }
        return try? manager.openBundle(for: PersistenceStore.appGroup().city)
    }

    /// All watched segments — two in "both sides" resident mode.
    private func currentSegments() -> [SweepBundle.Segment] {
        let store = PersistenceStore.appGroup()
        guard let session = store.session, let bundle = bundle() else { return [] }
        return session.segmentIds.compactMap { bundle.segment(id: $0) }
    }

    private func currentSegment() -> SweepBundle.Segment? {
        currentSegments().first
    }

    private func entry(at date: Date) -> SweepEntry? {
        let segments = currentSegments()
        guard let segment = segments.first else { return nil }
        let store = PersistenceStore.appGroup()
        // Union across watched sides — same rule set the app's verdict uses.
        let rules = Array(Set(segments.flatMap {
            OverrideDecorator.effectiveRules(segment: $0, overrides: store.overrides)
        }))
        let verdict = VerdictEngine.verdict(rules: rules, city: segment.city, at: date,
                                            calendar: SweepCalendar.la,
                                            holidays: bundle()?.holidays() ?? .empty)
        let until: String
        var moveBy: Date?
        if let next = verdict.next {
            switch verdict.state {
            case .sweepingNow:
                until = "until \(SweepFormat.hourLabel(next.end))"
                moveBy = next.end
            default:
                until = "until \(String(SweepFormat.dayName(next.start).prefix(3))) "
                    + SweepFormat.hourLabel(next.start)
                moveBy = next.start
            }
        } else {
            until = "no sweeping posted"
        }
        return SweepEntry(date: date, state: SweepFormat.uiState(verdict),
                          untilText: until, street: segment.street, moveBy: moveBy)
    }
}

struct SweepWidgetView: View {

    @Environment(\.widgetFamily) private var family
    let entry: SweepEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.state.word) \(entry.untilText)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.state.word).font(.headline)
                Text(entry.untilText).font(.caption)
                if !entry.street.isEmpty {
                    Text(entry.street).font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Tokens.statusColor(entry.state))
                        .frame(width: 9, height: 9)
                    Text(entry.state.word)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.statusColor(entry.state))
                        .textCase(.uppercase)
                }
                Spacer(minLength: 2)
                if let moveBy = entry.moveBy {
                    Text(entry.state == .sweepingNow ? "Sweeping ends" : "Move by")
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.sub)
                    Text(moveBy, format: .dateTime.weekday(.abbreviated).hour())
                        .font(Tokens.display(19).weight(.semibold))
                        .foregroundStyle(Tokens.ink)
                        .minimumScaleFactor(0.7)
                    // Self-updating countdown — no timeline churn needed.
                    Text(moveBy, style: .relative)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.statusColor(entry.state))
                        .minimumScaleFactor(0.7)
                } else {
                    Text(entry.untilText)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.sub)
                }
                if !entry.street.isEmpty {
                    Text(entry.street)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.sub)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Tokens.card, for: .widget)
        }
    }
}
