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
        guard let segment = currentSegment() else {
            let empty = SweepEntry(date: now, state: .none, untilText: "Not parked", street: "")
            completion(Timeline(entries: [empty], policy: .never))
            return
        }
        let store = PersistenceStore.appGroup()
        let holidays = bundle()?.holidays() ?? .empty
        let rules = OverrideDecorator.effectiveRules(segment: segment, overrides: store.overrides)
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

    private func currentSegment() -> SweepBundle.Segment? {
        let store = PersistenceStore.appGroup()
        guard let session = store.session else { return nil }
        return bundle()?.segment(id: session.segmentId)
    }

    private func entry(at date: Date) -> SweepEntry? {
        guard let segment = currentSegment() else { return nil }
        let store = PersistenceStore.appGroup()
        let rules = OverrideDecorator.effectiveRules(segment: segment, overrides: store.overrides)
        let verdict = VerdictEngine.verdict(rules: rules, city: segment.city, at: date,
                                            calendar: SweepCalendar.la,
                                            holidays: bundle()?.holidays() ?? .empty)
        let until: String
        if let next = verdict.next {
            switch verdict.state {
            case .sweepingNow:
                until = "until \(SweepFormat.hourLabel(next.end))"
            default:
                until = "until \(String(SweepFormat.dayName(next.start).prefix(3))) "
                    + SweepFormat.hourLabel(next.start)
            }
        } else {
            until = "no sweeping posted"
        }
        return SweepEntry(date: date, state: SweepFormat.uiState(verdict),
                          untilText: until, street: segment.street)
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
            VStack(alignment: .leading, spacing: 6) {
                Circle()
                    .fill(Tokens.statusColor(entry.state))
                    .frame(width: 10, height: 10)
                Text(entry.state.word)
                    .font(Tokens.display(20).weight(.semibold))
                    .foregroundStyle(Tokens.ink)
                    .minimumScaleFactor(0.7)
                Text(entry.untilText)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.sub)
                if !entry.street.isEmpty {
                    Text(entry.street)
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.sub)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Tokens.card, for: .widget)
        }
    }
}
