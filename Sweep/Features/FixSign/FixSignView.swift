import SweepCore
import SwiftUI

/// Fix-the-sign (§7.5). Signs beat data: the correction replaces this block's
/// rules on this phone. Overnight signs are allowed (split on save).
struct FixSignView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @Environment(\.dismiss) private var dismiss
    let segment: SweepBundle.Segment

    @State private var weekday = 2
    @State private var fromHour = 8
    @State private var toHour = 10

    private let days = ["Sunday", "Monday", "Tuesday", "Wednesday",
                        "Thursday", "Friday", "Saturday"]

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What does the sign say?")
                            .font(Tokens.display(24).weight(.medium))
                            .foregroundStyle(Tokens.ink)
                        Text("\(segment.street) · \((segment.displaySideName ?? "").lowercased())")
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.sub)

                        AlmanacCard {
                            VStack(spacing: 12) {
                                Picker("Day", selection: $weekday) {
                                    ForEach(0..<7) { d in
                                        Text(days[d]).tag(d)
                                    }
                                }
                                .pickerStyle(.menu)
                                HStack {
                                    Picker("From", selection: $fromHour) {
                                        ForEach(0..<24) { h in
                                            Text(SweepFormat.hourText(h)).tag(h)
                                        }
                                    }
                                    Text("until")
                                        .foregroundStyle(Tokens.sub)
                                    Picker("Until", selection: $toHour) {
                                        ForEach(1..<25) { h in
                                            Text(SweepFormat.hourText(h)).tag(h)
                                        }
                                    }
                                }
                                .pickerStyle(.menu)
                                if toHour <= fromHour {
                                    Text("Overnight sign — Sweep will watch both nights.")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Tokens.amber)
                                }
                            }
                        }

                        Text("Signs beat data. Your correction fixes this block on "
                             + "your phone and quietly flags it for a schedule check "
                             + "on our side.")
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.sub)

                        Button("Save what the sign says") {
                            let override = ScheduleRuleOverride(
                                weekday: weekday, fromHour: fromHour, toHour: toHour,
                                createdAt: model.clock.now)
                            Task {
                                await sessionManager.saveCorrection(override, for: segment.id)
                                dismiss()
                            }
                        }
                        .buttonStyle(ClayButtonStyle())
                    }
                    .padding(16)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Tokens.sub)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
