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
                if sessionManager.session == nil {
                    // Watermark cart in the empty space below the cards.
                    VStack {
                        Spacer()
                        EnforcementCartIllustration()
                            .padding(.bottom, 28)
                    }
                }
                ScrollView {
                    if sessionManager.session == nil {
                        HomeEmptyView(showParkFlow: $showParkFlow)
                    } else {
                        ParkedHomeView()
                    }
                }
            }
            // "I moved my car" must never hide below the fold — it's pinned
            // while the cards scroll behind it. Plus surfaces "Park another
            // car" here too, so the paid feature is visible, not a secret.
            .safeAreaInset(edge: .bottom) {
                if sessionManager.session != nil {
                    parkedBottomBar
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
            .onReceive(NotificationCenter.default.publisher(for: .sweepStartParkFlow)) { _ in
                // Action Button / Siri / sweep://park — straight to locating.
                showParkFlow = true
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    @EnvironmentObject private var plusStore: PlusStore
    @State private var askWhichCarMoved = false

    private var parkedBottomBar: some View {
        VStack(spacing: 8) {
            Button("I moved my car") {
                if sessionManager.sessions.count > 1 {
                    askWhichCarMoved = true
                } else {
                    sessionManager.clearAllSessions()
                }
            }
            .buttonStyle(ClayButtonStyle(background: Tokens.ink, foreground: Tokens.paper))
            .confirmationDialog("Which car moved?", isPresented: $askWhichCarMoved,
                                titleVisibility: .visible) {
                ForEach(sessionManager.sessions) { session in
                    Button("I moved \(session.displayCarName)") {
                        sessionManager.clearSession(id: session.id)
                    }
                }
                Button("All of them") {
                    sessionManager.clearAllSessions()
                }
                Button("Cancel", role: .cancel) {}
            }
            if plusStore.hasPlus {
                Button {
                    showParkFlow = true
                } label: {
                    Label("Park another car", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                            .strokeBorder(Tokens.clay, lineWidth: 1.5))
                        .foregroundStyle(Tokens.clay)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Tokens.paper
                .opacity(0.97)
                .overlay(Rectangle().fill(Tokens.line).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom))
    }
}

/// Home — empty state (§7.2).
struct HomeEmptyView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @EnvironmentObject var plusStore: PlusStore
    @Binding var showParkFlow: Bool
    @State private var searchText = ""
    @State private var results: [BlockSearch.Hit] = []

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
                    TextField(SweepFormat.searchPlaceholder(for: sessionManager.city),
                              text: $searchText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: Tokens.radiusControl)
                            .strokeBorder(Tokens.line))
                        .onChange(of: searchText) { _, q in
                            search(q)
                        }
                    ForEach(results.prefix(8)) { hit in
                        NavigationLink {
                            BlockConfirmView(street: hit.street, blockLabel: hit.blockLabel)
                        } label: {
                            BlockHitRow(hit: hit)
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
        guard let bundle = try? model.bundleManager.openBundle(for: sessionManager.city) else {
            results = []
            return
        }
        results = BlockSearch.hits(bundle: bundle, query: query)
    }
}
