import SweepCore
import SwiftUI

/// Step 3 (§7.3): the two-card side chooser. Only shown when the sides differ.
/// Renders one card per logical side — a block label can span multiple source
/// features, so each side may merge several segments (BlockSides).
struct SidePickerView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @EnvironmentObject var plusStore: PlusStore
    let street: String
    let blockLabel: String
    let onDone: () -> Void

    @State private var selectedSideKey: String?
    @State private var watchBoth = false
    @State private var chooserSegments: [SweepBundle.Segment] = []
    @State private var showCarChooser = false

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

                bothSidesCard(sides: sides)

                Text("Both verdicts stay visible, so if you tap the wrong one "
                     + "you'll see it — not find out from a "
                     + "$\(sessionManager.city.fine) ticket.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.sub)

                Button("Set my reminders") {
                    let targets: [SweepBundle.Segment]
                    if watchBoth {
                        targets = sides.map {
                            $0.parkTarget(at: now, calendar: SweepCalendar.la,
                                          holidays: holidays, overrides: model.store.overrides)
                        }
                    } else if let side = sides.first(where: { $0.sideKey == selectedSideKey }) {
                        targets = [side.parkTarget(at: now, calendar: SweepCalendar.la,
                                                   holidays: holidays,
                                                   overrides: model.store.overrides)]
                    } else {
                        return
                    }
                    // Plus with a car already parked → ask which car this is.
                    if plusStore.hasPlus && !sessionManager.sessions.isEmpty {
                        chooserSegments = targets
                        showCarChooser = true
                        return
                    }
                    Task {
                        await sessionManager.park(segments: targets, source: .manual)
                        await model.scheduler.requestAuthorizationIfNeeded()
                        await model.refreshAuthorizationStatus()
                        onDone()
                    }
                }
                .buttonStyle(ClayButtonStyle())
                .disabled(selectedSideKey == nil && !watchBoth)
                .opacity(selectedSideKey == nil && !watchBoth ? 0.5 : 1)
            }
            .padding(16)
        }
        .sheet(isPresented: $showCarChooser) {
            CarChooserSheet(segments: chooserSegments) {
                showCarChooser = false
                onDone()
            }
        }
    }

    @ViewBuilder
    private func sideCard(_ side: BlockSide, holidays: HolidayCalendar, now: Date) -> some View {
        let rules = side.mergedRules(overrides: model.store.overrides)
        let verdict = VerdictEngine.verdict(rules: rules, city: sessionManager.city, at: now,
                                            calendar: SweepCalendar.la, holidays: holidays)
        // Parity leads the title when the data has it — the door number next
        // to the car is the one instantly verifiable cue. Door line omitted
        // when parity is unknown — never guess (§4.4.3).
        let doors: String? = side.doorParity.flatMap { parity in
            side.doorRange.map { "doors \($0) (\(parity))" }
        }
        SideCard(
            landmark: SweepFormat.sideTitle(parity: side.doorParity,
                                            landmark: side.landmark,
                                            confidence: side.landmarkConfidence),
            hint: SweepFormat.sideBackup(parity: side.doorParity,
                                         landmark: side.landmark,
                                         landmarkHint: side.landmarkHint,
                                         confidence: side.landmarkConfidence),
            doors: doors,
            signLines: SweepFormat.signLines(rules: rules),
            miniVerdict: SweepFormat.miniVerdict(verdict, now: now),
            miniState: SweepFormat.uiState(verdict),
            selected: !watchBoth && selectedSideKey == side.sideKey) {
                selectedSideKey = side.sideKey
                watchBoth = false
            }
    }

    /// Resident mode: watch every sweep on the block, whichever side the car
    /// is on. Reminders fire for both sides' windows; the verdict follows
    /// whichever sweep comes first.
    @ViewBuilder
    private func bothSidesCard(sides: [BlockSide]) -> some View {
        if sides.count > 1 {
            Button {
                watchBoth = true
                selectedSideKey = nil
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Both sides")
                        .font(Tokens.display(17).weight(.medium))
                        .foregroundStyle(Tokens.ink)
                    Text("Live here? Watch the whole block — reminders before "
                         + "every sweep, whichever side you're on.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.radiusSideCard, style: .continuous)
                        .fill(Tokens.card)
                        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSideCard,
                                                  style: .continuous)
                            .strokeBorder(watchBoth ? Tokens.clay : Tokens.line,
                                          lineWidth: watchBoth ? 2 : 1))
                        .shadow(color: watchBoth ? Tokens.clay.opacity(0.13) : .clear,
                                radius: 3, y: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Both sides: reminders before every sweep on this block")
            .accessibilityAddTraits(watchBoth ? .isSelected : [])
        }
    }
}
