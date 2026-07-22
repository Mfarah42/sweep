import MapKit
import SweepCore
import SwiftUI

/// Park flow (§7.3): locate → confirm block → side chooser.
struct ParkFlowView: View {

    enum Step {
        case locating
        case confirm(CurbSnapper.SnapResult)
        case side(street: String, blockLabel: String)
        case manual(notice: String?)
    }

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @EnvironmentObject var plusStore: PlusStore
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .locating
    @State private var pulse = false
    @State private var chooserSegments: [SweepBundle.Segment] = []
    @State private var showCarChooser = false

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
                case .manual(let notice):
                    ManualBlockSearchView(notice: notice) { street, label in
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
        .sheet(isPresented: $showCarChooser) {
            CarChooserSheet(segments: chooserSegments) {
                showCarChooser = false
                dismiss()
            }
        }
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
        case .fix(let point, let accuracy):
            guard let bundle = try? model.bundleManager.openBundle(for: sessionManager.city) else {
                step = .manual(notice: nil)
                return
            }
            // Search radius scales with fix quality; a fuzzy fix must not
            // read as "you're outside the city".
            let radius = min(max(CurbSnapper.fineRadiusMeters, accuracy + 25), 150)
            let candidates = bundle.segments(near: point, marginMeters: radius + 20)
            if let result = CurbSnapper.snap(fix: point, candidates: candidates,
                                             fineRadius: radius) {
                // Auto-advance only when both the fix and the match are
                // tight; otherwise let the user confirm the block.
                if result.confidence == .high, accuracy <= 35,
                   result.block.distanceMeters <= CurbSnapper.fineRadiusMeters {
                    advanceToSide(street: result.block.street,
                                  blockLabel: result.block.blockLabel)
                } else {
                    step = .confirm(result)
                }
                return
            }
            // Last resort: a very wide net before claiming anything.
            if let far = CurbSnapper.snap(fix: point,
                                          candidates: bundle.segments(near: point, marginMeters: 300),
                                          fineRadius: 250) {
                step = .confirm(far)
            } else {
                step = .manual(notice: "Your GPS fix (±\(Int(accuracy)) m) didn't "
                               + "land near any mapped block — find yours below.")
            }
        case .denied:
            step = .manual(notice: "Location is off for Sweep. Turn it on in "
                           + "Settings, or find your block below.")
        case .unavailable:
            step = .manual(notice: "Couldn't get a solid GPS fix — this happens "
                           + "indoors or when Precise Location is off. "
                           + "Find your block below.")
        }
    }

    /// Skip the side question entirely when both sides sweep identically
    /// (§7.3). Compares logical sides, not raw segments — a block label can
    /// span multiple source features, giving several segments per side.
    private func advanceToSide(street: String, blockLabel: String) {
        guard let bundle = try? model.bundleManager.openBundle(for: sessionManager.city) else {
            step = .manual(notice: nil)
            return
        }
        let sides = BlockSides.group(bundle.blockSegments(street: street, blockLabel: blockLabel))
        guard !sides.isEmpty else {
            step = .manual(notice: nil)
            return
        }
        let overrides = model.store.overrides
        if sides.count == 1 || BlockSides.sidesAreEquivalent(sides, overrides: overrides) {
            let holidays = bundle.holidays()
            finish(segment: sides[0].parkTarget(at: model.clock.now,
                                                calendar: SweepCalendar.la,
                                                holidays: holidays,
                                                overrides: overrides))
        } else {
            step = .side(street: street, blockLabel: blockLabel)
        }
    }

    private func finish(segment: SweepBundle.Segment) {
        // Plus with a car already parked → ask which car this is.
        if plusStore.hasPlus && !sessionManager.sessions.isEmpty {
            chooserSegments = [segment]
            showCarChooser = true
            return
        }
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
/// `notice` tells the user WHY they landed here instead of failing silently.
struct ManualBlockSearchView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    var notice: String?
    let onPick: (String, String) -> Void
    @State private var query = ""
    @State private var results: [BlockSearch.Hit] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Which street are you on?")
                    .font(Tokens.display(24).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                if let notice {
                    Text(notice)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Tokens.amber)
                }
                TextField(SweepFormat.searchPlaceholder(for: sessionManager.city), text: $query)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                        .fill(Tokens.card)
                        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                            .strokeBorder(Tokens.line)))
                    .onChange(of: query) { _, q in
                        results = (try? model.bundleManager.openBundle(for: sessionManager.city))
                            .map { BlockSearch.hits(bundle: $0, query: q) } ?? []
                    }
                ForEach(results) { hit in
                    Button {
                        onPick(hit.street, hit.blockLabel)
                    } label: {
                        BlockHitRow(hit: hit)
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
