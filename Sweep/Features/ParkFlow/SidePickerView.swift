import SweepCore
import SwiftUI

/// Step 3 (§7.3): the two-card side chooser. Only shown when the sides differ.
struct SidePickerView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    let street: String
    let blockLabel: String
    let onDone: () -> Void

    @State private var selectedId: String?

    var body: some View {
        let sides = (try? model.bundleManager.openBundle(for: sessionManager.city))?
            .blockSegments(street: street, blockLabel: blockLabel) ?? []
        // If the sides turn out equivalent (manual entry path), park on either.
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

                ForEach(sides, id: \.id) { side in
                    sideCard(side, now: now)
                }

                Text("Both verdicts stay visible, so if you tap the wrong one "
                     + "you'll see it — not find out from a "
                     + "$\(sessionManager.city.fine) ticket.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.sub)

                Button("Set my reminders") {
                    guard let side = sides.first(where: { $0.id == selectedId }) else { return }
                    Task {
                        await sessionManager.park(segment: side, source: .manual)
                        await model.scheduler.requestAuthorizationIfNeeded()
                        await model.refreshAuthorizationStatus()
                        onDone()
                    }
                }
                .buttonStyle(ClayButtonStyle())
                .disabled(selectedId == nil)
                .opacity(selectedId == nil ? 0.5 : 1)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func sideCard(_ side: SweepBundle.Segment, now: Date) -> some View {
        let rules = sessionManager.effectiveRules(for: side)
        let holidays = (try? model.bundleManager.openBundle(for: sessionManager.city))?
            .holidays() ?? .empty
        let verdict = VerdictEngine.verdict(rules: rules, city: side.city, at: now,
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
            selected: selectedId == side.id) {
                selectedId = side.id
            }
    }
}
