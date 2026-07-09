import SweepCore
import SwiftUI

/// Settings (§7.6): city picker, reminder toggles, about-the-data, restore
/// purchases, font license, hidden demo mode (5 taps on the version string).
struct SettingsView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @EnvironmentObject var plusStore: PlusStore
    @Environment(\.dismiss) private var dismiss

    @State private var pendingCity: City?
    @State private var versionTaps = 0
    @State private var showDemoMode = false
    @State private var prefs = ReminderPrefs()

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        cityCard
                        appearanceCard
                        remindersCard
                        aboutDataCard
                        plusCard
                        if showDemoMode {
                            DemoModeCard()
                        }
                        footer
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { prefs = model.store.reminderPrefs }
            .alert("Switch city?", isPresented: .init(
                get: { pendingCity != nil },
                set: { if !$0 { pendingCity = nil } })) {
                Button("Switch & clear spot", role: .destructive) {
                    if let city = pendingCity {
                        sessionManager.city = city   // clears the session (§7.6)
                    }
                    pendingCity = nil
                }
                Button("Cancel", role: .cancel) { pendingCity = nil }
            } message: {
                Text("Switching cities clears your parked spot.")
            }
        }
        .preferredColorScheme(model.colorScheme)
    }

    private var appearanceCard: some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(Tokens.display(17).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                Picker("Appearance", selection: $model.appearance) {
                    ForEach(AppearancePref.allCases, id: \.self) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var cityCard: some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("City")
                    .font(Tokens.display(17).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                Picker("City", selection: .init(
                    get: { sessionManager.city },
                    set: { newCity in
                        if newCity != sessionManager.city {
                            if sessionManager.session != nil {
                                pendingCity = newCity
                            } else {
                                sessionManager.city = newCity
                            }
                        }
                    })) {
                    ForEach(City.allCases, id: \.self) { city in
                        Text(city.displayName).tag(city)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var remindersCard: some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reminders")
                    .font(Tokens.display(17).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                Toggle("Evening before, 8 PM", isOn: binding(\.nightBefore))
                Toggle("Two hours before", isOn: binding(\.twoHours))
                Toggle("Thirty minutes before", isOn: binding(\.thirtyMin))
                Toggle("Also add to Apple Reminders", isOn: appleRemindersBinding)
                Text("Puts the move-by deadline in your Reminders app too — "
                     + "handy for Siri and CarPlay.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.sub)
            }
            .tint(Tokens.clay)
        }
    }

    private var appleRemindersBinding: Binding<Bool> {
        Binding(
            get: { model.store.appleRemindersEnabled },
            set: { enabled in
                Task { @MainActor in
                    if enabled {
                        let granted = await model.sessionManager.remindersBridge?
                            .requestAccess() ?? false
                        model.store.appleRemindersEnabled = granted
                    } else {
                        model.store.appleRemindersEnabled = false
                        model.sessionManager.remindersBridge?
                            .sync(deadline: nil, street: nil, sideName: nil)
                    }
                    await model.sessionManager.refreshDerivedState()
                }
            })
    }

    private func binding(_ key: WritableKeyPath<ReminderPrefs, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: key] },
            set: { value in
                prefs[keyPath: key] = value
                model.store.reminderPrefs = prefs
                Task { await sessionManager.refreshDerivedState() }
            })
    }

    private var aboutDataCard: some View {
        let builtAt = (try? model.bundleManager.openBundle(for: sessionManager.city))?
            .manifest.builtAt ?? "—"
        return AlmanacCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("About the data")
                    .font(Tokens.display(17).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                Text("Source: \(sessionManager.city.dataSourceName)")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Tokens.sub)
                Text("Schedule updated \(builtAt.prefix(10))")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Tokens.sub)
                Text(sessionManager.city.holidayBehavior)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Tokens.sub)
                Text("Always check the posted sign.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tokens.clay)
            }
        }
    }

    private var plusCard: some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sweep Plus")
                        .font(Tokens.display(17).weight(.medium))
                        .foregroundStyle(Tokens.ink)
                    Spacer()
                    if plusStore.hasPlus {
                        PillTag("yours", color: Tokens.sage)
                    }
                }
                Text("Multiple cars, curb-card themes, and Longest Spot. "
                     + "Everything that prevents a ticket stays free forever.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Tokens.sub)
                if !plusStore.hasPlus {
                    Button(plusStore.product.map {
                        "Get Plus — \($0.displayPrice)"
                    } ?? "Get Plus — $9.99") {
                        Task { await plusStore.purchase() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.clay)
                }
                Button("Restore purchases") {
                    Task { await plusStore.restore() }
                }
                .font(.system(size: 13.5))
                .foregroundStyle(Tokens.sub)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button {
                versionTaps += 1
                if versionTaps >= 5 {
                    showDemoMode = true   // hidden QA time-scrub (§7.6)
                }
            } label: {
                Text("Sweep 1.0 (1)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.sub)
            }
            .buttonStyle(.plain)
            NavigationLink("Fraunces font license (SIL OFL)") {
                FontLicenseView()
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Tokens.sub)
        }
        .padding(.top, 8)
    }
}

/// Hidden demo mode: replaces the prototype's always-visible time slider.
struct DemoModeCard: View {

    @EnvironmentObject var model: AppModel
    @State private var offsetHours: Double = 0

    var body: some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Demo mode")
                    .font(Tokens.display(17).weight(.medium))
                    .foregroundStyle(Tokens.amber)
                Text(model.demoClock.map { "Clock: \($0.now.formatted())" } ?? "Clock: live")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.sub)
                Slider(value: $offsetHours, in: 0...(14 * 24), step: 1) {
                    Text("Time scrub")
                } onEditingChanged: { editing in
                    if !editing {
                        model.demoClock = offsetHours == 0 ? nil
                            : FixedClock(now: Date().addingTimeInterval(offsetHours * 3600))
                    }
                }
                Button("Reset to live clock") {
                    offsetHours = 0
                    model.demoClock = nil
                }
                .font(.system(size: 13))
                .foregroundStyle(Tokens.clay)
            }
        }
    }
}

struct FontLicenseView: View {
    var body: some View {
        ScrollView {
            Text((try? String(contentsOf: Bundle.main.url(forResource: "OFL",
                                                          withExtension: "txt") ?? URL(fileURLWithPath: "/"),
                              encoding: .utf8)) ?? "SIL Open Font License 1.1 — see scripts.sil.org/OFL")
                .font(.system(size: 12, design: .monospaced))
                .padding(16)
        }
        .background(Tokens.paper)
        .navigationTitle("Font license")
    }
}
