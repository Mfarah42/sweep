import SweepCore
import SwiftUI

/// Step 3 (§7.3): the two-card side chooser. Only shown when the sides differ.
/// Renders one card per logical side — a block label can span multiple source
/// features, so each side may merge several segments (BlockSides).
struct SidePickerView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    let street: String
    let blockLabel: String
    let onDone: () -> Void

    @State private var selectedSideKey: String?

    var body: some View {
        let bundle = try? model.bundleManager.openBundle(for: sessionManager.city)
        let sides = BlockSides.group(bundle?.blockSegments(street: street,
                                                           blockLabel: blockLabel) ?? [])
        let holidays = bundle?.holidays() ?? .empty
        let now = model.clock.now

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(street)
                        .font(Tokens.display(24).weight(.medium))
                        .foregroundStyle(Tokens.ink)
                    Text(blockLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.sub)
                }

                Text("No compass needed — go by the view, or the door numbers "
                     + "next to your car.")
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.sub)

                ForEach(sides) { side in
                    sideCard(side, holidays: holidays, now: now)
                }

                Text("Both verdicts stay visible, so if you tap the wrong one "
                     + "you'll see it — not find out from a "
                     + "$\(sessionManager.city.fine) ticket.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.sub)

                Button("Set my reminders") {
                    guard let side = sides.first(where: { $0.sideKey == selectedSideKey }) else { return }
                    let target = side.parkTarget(at: now, calendar: SweepCalendar.la,
                                                 holidays: holidays,
                                                 overrides: model.store.overrides)
                    Task {
                        await sessionManager.park(segment: target, source: .manual)
                        await model.scheduler.requestAuthorizationIfNeeded()
                        await model.refreshAuthorizationStatus()
                        onDone()
                    }
                }
                .buttonStyle(ClayButtonStyle())
                .disabled(selectedSideKey == nil)
                .opacity(selectedSideKey == nil ? 0.5 : 1)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func sideCard(_ side: BlockSide, holidays: HolidayCalendar, now: Date) -> some View {
        let rules = side.mergedRules(overrides: model.store.overrides)
        let verdict = VerdictEngine.verdict(rules: rules, city: sessionManager.city, at: now,
                                            calendar: SweepCalendar.la, holidays: holidays)
        // Auto landmark names show doors more prominently (§4.4.2); either way
        // door line is omitted when parity is unknown — never guess (§4.4.3).
        let doors: String? = side.doorParity.map { parity in
            if let range = side.doorRange {
                return "doors \(range) (\(parity))"
            }
            return "\(parity) door numbers"
        }
        SideCard(
            landmark: side.landmark ?? "This side",
            hint: side.landmarkHint,
            doors: doors,
            miniVerdict: SweepFormat.miniVerdict(verdict, now: now),
            miniState: SweepFormat.uiState(verdict),
            selected: selectedSideKey == side.sideKey) {
                selectedSideKey = side.sideKey
            }
    }
}
