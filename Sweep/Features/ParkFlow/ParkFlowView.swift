import MapKit
import SweepCore
import SwiftUI

/// Park flow (§7.3): locate → confirm block → side chooser.
struct ParkFlowView: View {

    enum Step {
        case locating
        case confirm(CurbSnapper.SnapResult)
        case side(street: String, blockLabel: String)
        case manual
    }

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .locating
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.paper.ignoresSafeArea()
                switch step {
                case .locating:
                    locatingView
                case .confirm(let result):
                    BlockConfirmContent(result: result) { street, label in
                        advanceToSide(street: street, blockLabel: label)
                    }
                case .side(let street, let blockLabel):
                    SidePickerView(street: street, blockLabel: blockLabel) {
                        dismiss()
                    }
                case .manual:
                    ManualBlockSearchView { street, label in
                        advanceToSide(street: street, blockLabel: label)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Tokens.sub)
                }
            }
        }
        .task { await locate() }
    }

    private var locatingView: some View {
        Text("Finding your block…")
            .font(Tokens.displayItalic(22))
            .foregroundStyle(Tokens.sub)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }

    private func locate() async {
        let fixer = LocationFixer()
        let outcome = await fixer.acquireFix()
        switch outcome {
        case .fix(let point):
            guard let bundle = try? model.bundleManager.openBundle(for: sessionManager.city),
                  let result = CurbSnapper.snap(fix: point,
                                                candidates: bundle.segments(near: point)) else {
                step = .manual
                return
            }
            if result.confidence == .high {
                advanceToSide(street: result.block.street, blockLabel: result.block.blockLabel)
            } else {
                step = .confirm(result)
            }
        case .denied, .unavailable:
            step = .manual
        }
    }

    /// Skip the side question entirely when both sides sweep identically (§7.3).
    private func advanceToSide(street: String, blockLabel: String) {
        guard let bundle = try? model.bundleManager.openBundle(for: sessionManager.city) else {
            step = .manual
            return
        }
        let sides = bundle.blockSegments(street: street, blockLabel: blockLabel)
        if sides.count >= 2,
           VerdictEngine.rulesAreEquivalent(
                sessionManager.effectiveRules(for: sides[0]),
                sessionManager.effectiveRules(for: sides[1])) {
            finish(segment: sides[0])
        } else if sides.count == 1 {
            finish(segment: sides[0])
        } else {
            step = .side(street: street, blockLabel: blockLabel)
        }
    }

    private func finish(segment: SweepBundle.Segment) {
        Task {
            await sessionManager.park(segment: segment, source: .gps)
            // Ask for notification permission at the end of the first
            // successful park flow, not before (§8).
            await model.scheduler.requestAuthorizationIfNeeded()
            await model.refreshAuthorizationStatus()
            dismiss()
        }
    }
}

/// Step 2 (§7.3): "Found you here" + non-interactive map + block picker.
struct BlockConfirmContent: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    let result: CurbSnapper.SnapResult
    let onConfirm: (String, String) -> Void

    var body: some View {
        // Runner-up listed first when ambiguous (§6.2.4).
        let choices = [result.runnerUp, result.block].compactMap { $0 }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Found you here")
                    .font(Tokens.display(24).weight(.medium))
                    .foregroundStyle(Tokens.ink)

                BlockMapSnapshot(street: result.block.street,
                                 blockLabel: result.block.blockLabel)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusControl))

                Text("Not quite? Pick your block:")
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.sub)

                ForEach(choices, id: \.blockLabel) { block in
                    Button {
                        onConfirm(block.street, block.blockLabel)
                    } label: {
                        AlmanacCard {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(block.street)
                                    .font(Tokens.display(19).weight(.medium))
                                    .foregroundStyle(Tokens.ink)
                                Text(block.blockLabel)
                                    .font(.system(size: 13.5))
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
}

/// Small non-interactive MapKit snapshot of the block (both sides drawn; no
/// user location dot persisted).
struct BlockMapSnapshot: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    let street: String
    let blockLabel: String

    var body: some View {
        let sides = (try? model.bundleManager.openBundle(for: sessionManager.city))?
            .blockSegments(street: street, blockLabel: blockLabel) ?? []
        let points = sides.flatMap(\.geometry)
        if let mid = points.dropFirst(points.count / 2).first {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: mid.lat, longitude: mid.lon),
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)))) {
                ForEach(sides, id: \.id) { side in
                    MapPolyline(coordinates: side.geometry.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    })
                    .stroke(Tokens.clay, lineWidth: 4)
                }
            }
            .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: Tokens.radiusControl).fill(Tokens.line)
        }
    }
}

/// Fall-through when GPS is denied/inaccurate (§6.2): manual block search.
struct ManualBlockSearchView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    let onPick: (String, String) -> Void
    @State private var query = ""
    @State private var results: [(street: String, blockLabel: String)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Which street are you on?")
                    .font(Tokens.display(24).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                TextField("Street name…", text: $query)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                        .fill(Tokens.card)
                        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                            .strokeBorder(Tokens.line)))
                    .onChange(of: query) { _, q in
                        results = q.count >= 2
                            ? ((try? model.bundleManager.openBundle(for: sessionManager.city))?
                                .searchBlocks(matching: q) ?? [])
                            : []
                    }
                ForEach(results, id: \.blockLabel) { hit in
                    Button {
                        onPick(hit.street, hit.blockLabel)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.street)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Tokens.ink)
                            Text(hit.blockLabel)
                                .font(.system(size: 13))
                                .foregroundStyle(Tokens.sub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(16)
        }
    }
}

/// Entry from the home block-search card: jumps straight to confirm/side.
struct BlockConfirmView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @Environment(\.dismiss) private var dismiss
    let street: String
    let blockLabel: String

    var body: some View {
        ZStack {
            Tokens.paper.ignoresSafeArea()
            SidePickerView(street: street, blockLabel: blockLabel) {
                dismiss()
            }
        }
    }
}
