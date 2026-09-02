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
                        guideCard
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

                // Curb-card themes (Plus §11). Swatch = paper + accent dot.
                HStack(spacing: 10) {
                    ForEach(SweepTheme.all) { theme in
                        let locked = theme.isPlus && !plusStore.hasPlus
                        Button {
                            guard !locked else { return }
                            model.themeId = theme.id
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: theme.paper.light))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(model.themeId == theme.id
                                                          ? Tokens.clay : Tokens.line,
                                                          lineWidth: model.themeId == theme.id ? 2 : 1))
                                        .frame(height: 36)
                                    Circle()
                                        .fill(Color(hex: theme.accent.light))
                                        .frame(width: 14, height: 14)
                                    if locked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Tokens.sub)
                                            .offset(x: 24, y: -10)
                                    }
                                }
                                Text(theme.name)
                                    .font(.system(size: 11.5,
                                                  weight: model.themeId == theme.id ? .semibold : .regular))
                                    .foregroundStyle(Tokens.ink)
                            }
                        }
                        .buttonStyle(.plain)
                        .opacity(locked ? 0.55 : 1)
                        .accessibilityLabel("\(theme.name) theme"
                            + (locked ? ", requires Sweep Plus" : ""))
                    }
                }
                if !plusStore.hasPlus {
                    Text("Themes are part of Sweep Plus.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.sub)
                }
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
                Text("Sweep picks the city on its own from where you park or "
                     + "which street you search. This just sets the default "
                     + "and the data notes below.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.sub)
            }
        }
    }

    private var guideCard: some View {
        NavigationLink {
            GuideView()
        } label: {
            AlmanacCard {
                HStack(spacing: 12) {
                    Image(systemName: "book")
                        .font(.system(size: 18))
                        .foregroundStyle(Tokens.clay)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How Sweep works")
                            .font(Tokens.display(17).weight(.medium))
                            .foregroundStyle(Tokens.ink)
                        Text("Two-minute guide: parking, sides, reminders, fixing a sign.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Tokens.sub)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Tokens.sub)
                }
            }
        }
        .buttonStyle(.plain)
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
                Toggle("All clear, when sweeping ends", isOn: binding(\.allClear))
                Toggle("Three-day rule warning", isOn: binding(\.threeDayRule))

                Divider().overlay(Tokens.line)

                Picker("Garbage day", selection: garbageDayBinding) {
                    Text("Off").tag(-1)
                    ForEach(0..<7) { d in
                        Text(["Sunday", "Monday", "Tuesday", "Wednesday",
                              "Thursday", "Friday", "Saturday"][d]).tag(d)
                    }
                }
                .pickerStyle(.menu)
                Text("Bins-out reminder the evening before, and a 7 AM nudge "
                     + "on pickup day. Set it once — it's the same day every week.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.sub)
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

    private var garbageDayBinding: Binding<Int> {
        Binding(
            get: { model.store.garbageDay ?? -1 },
            set: { day in
                model.store.garbageDay = day == -1 ? nil : day
                Task {
                    if day != -1 {
                        _ = await model.scheduler.requestAuthorizationIfNeeded()
                    }
                    await model.scheduler.syncGarbageReminders(
                        pickupWeekday: model.store.garbageDay)
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
                if let stale = SweepFormat.staleNotice(builtAt: builtAt,
                                                       now: model.clock.now) {
                    Text(stale)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                Text("Every ticket-saving alert is free, forever — that never "
                     + "changes. Plus adds the extras: a second car, curb-card "
                     + "themes, and Longest Spot, which finds the block you can "
                     + "stay on longest.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Tokens.sub)
                if !plusStore.hasPlus {
                    Button(plusStore.product.map {
                        "Get Plus — \($0.displayPrice)"
                    } ?? "Get Plus — $3") {
                        Task { await plusStore.purchase() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.clay)
                }
                if let notice = plusStore.notice {
                    Text(notice)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Tokens.amber)
                        .fixedSize(horizontal: false, vertical: true)
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
    @EnvironmentObject var plusStore: PlusStore
    @State private var offsetHours: Double = 0
    @State private var forcePlus = UserDefaults.standard.bool(
        forKey: PlusStore.debugForcePlusKey)

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

                #if DEBUG
                // Device testing without a per-device test-store purchase.
                // The key is only read in DEBUG builds; release ignores it.
                Toggle("Force Plus (debug builds only)", isOn: $forcePlus)
                    .tint(Tokens.amber)
                    .onChange(of: forcePlus) { _, on in
                        UserDefaults.standard.set(on, forKey: PlusStore.debugForcePlusKey)
                        Task { await plusStore.load() }
                    }
                #endif
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
