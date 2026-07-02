import SweepCore
import SwiftUI

struct HomeView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @State private var showParkFlow = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.paper.ignoresSafeArea()
                ScrollView {
                    if sessionManager.session == nil {
                        HomeEmptyView(showParkFlow: $showParkFlow)
                    } else {
                        ParkedHomeView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Sweep")
                        .font(Tokens.display(20).weight(.semibold))
                        .foregroundStyle(Tokens.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Tokens.sub)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showParkFlow) {
                ParkFlowView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

/// Home — empty state (§7.2).
struct HomeEmptyView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @EnvironmentObject var plusStore: PlusStore
    @Binding var showParkFlow: Bool
    @State private var searchText = ""
    @State private var results: [(street: String, blockLabel: String)] = []

    var body: some View {
        VStack(spacing: 16) {
            AlmanacCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where's your car?")
                        .font(Tokens.verdictHeadline)
                        .foregroundStyle(Tokens.ink)
                    Text("Tell Sweep once when you park. It watches the "
                         + "\(sessionManager.city.displayName) sweeping schedule "
                         + "so you don't have to.")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.sub)
                    Button("I just parked") {
                        showParkFlow = true
                    }
                    .buttonStyle(ClayButtonStyle())
                    Text("Your spot never leaves this device.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Tokens.sub)
                        .frame(maxWidth: .infinity)
                }
            }

            AlmanacCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Or find your block")
                        .font(Tokens.display(17).weight(.medium))
                        .foregroundStyle(Tokens.ink)
                    TextField("Street name…", text: $searchText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                            .strokeBorder(Tokens.line))
                        .onChange(of: searchText) { _, q in
                            search(q)
                        }
                    ForEach(results.prefix(8), id: \.blockLabel) { hit in
                        NavigationLink {
                            BlockConfirmView(street: hit.street, blockLabel: hit.blockLabel)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.street)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Tokens.ink)
                                Text(hit.blockLabel)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Tokens.sub)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
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

    private func search(_ query: String) {
        guard query.count >= 2,
              let bundle = try? model.bundleManager.openBundle(for: sessionManager.city) else {
            results = []
            return
        }
        results = bundle.searchBlocks(matching: query)
    }
}
