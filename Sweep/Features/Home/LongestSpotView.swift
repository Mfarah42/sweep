import SweepCore
import SwiftUI

/// "Longest spot" mode (§11, Plus): rank nearby blocks by time-until-next-
/// sweep. Pure engine + snapper composition — a simple ranked list, no map.
struct LongestSpotView: View {

    struct Ranked: Identifiable {
        let id: String
        let street: String
        let blockLabel: String
        let nextSweep: Date?
        let distanceMeters: Double
    }

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @State private var ranked: [Ranked]?
    @State private var failed = false

    var body: some View {
        ZStack {
            Tokens.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Longest spot nearby")
                        .font(Tokens.display(24).weight(.medium))
                        .foregroundStyle(Tokens.ink)
                    if let ranked {
                        ForEach(ranked) { block in
                            AlmanacCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(block.street)
                                            .font(Tokens.display(17).weight(.medium))
                                            .foregroundStyle(Tokens.ink)
                                        Text("\(block.blockLabel) · \(Int(block.distanceMeters)) m away")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Tokens.sub)
                                    }
                                    Spacer()
                                    Text(block.nextSweep.map {
                                        SweepFormat.countdown(to: $0, from: model.clock.now)
                                    } ?? "no sweep posted")
                                        .font(Tokens.displayItalic(16))
                                        .foregroundStyle(Tokens.sage)
                                }
                            }
                        }
                        Text("Always check the posted sign.")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.clay)
                    } else if failed {
                        Text("Couldn't get a location fix.")
                            .foregroundStyle(Tokens.sub)
                    } else {
                        Text("Looking around you…")
                            .font(Tokens.displayItalic(16))
                            .foregroundStyle(Tokens.sub)
                    }
                }
                .padding(16)
            }
        }
        .task { await rank() }
    }

    private func rank() async {
        let fixer = LocationFixer()
        guard case .fix(let point) = await fixer.acquireFix(),
              let bundle = try? model.bundleManager.openBundle(for: sessionManager.city) else {
            failed = true
            return
        }
        let now = model.clock.now
        let holidays = bundle.holidays()
        // Wider coarse net than parking: everything within ~250 m.
        let candidates = bundle.segments(near: point, marginMeters: 250)
        var byBlock: [String: Ranked] = [:]
        for seg in candidates {
            let d = CurbSnapper.distanceMeters(from: point, toPolyline: seg.geometry)
            guard d <= 250 else { continue }
            let rules = sessionManager.effectiveRules(for: seg)
            let verdict = VerdictEngine.verdict(rules: rules, city: seg.city, at: now,
                                                calendar: SweepCalendar.la, holidays: holidays)
            let next = verdict.next?.start
            let key = seg.blockKey + "|" + seg.sideKey
            if let existing = byBlock[key], existing.distanceMeters <= d { continue }
            byBlock[key] = Ranked(id: key, street: seg.street,
                                  blockLabel: seg.blockLabel + " · "
                                    + (seg.landmark ?? "side \(seg.sideKey)").lowercased(),
                                  nextSweep: next, distanceMeters: d)
        }
        ranked = byBlock.values
            .sorted { ($0.nextSweep ?? .distantFuture) > ($1.nextSweep ?? .distantFuture) }
            .prefix(12).map { $0 }
    }
}
