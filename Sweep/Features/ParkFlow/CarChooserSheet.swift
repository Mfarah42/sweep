import SweepCore
import SwiftUI

/// Plus multi-car: when a car is already parked and another spot is chosen,
/// ask which car this is — re-park an existing one (keeps its name) or add a
/// new named car. Free tier never sees this; parking simply replaces.
struct CarChooserSheet: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sessionManager: ParkingSessionManager
    @Environment(\.dismiss) private var dismiss
    let segments: [SweepBundle.Segment]
    let onDone: () -> Void

    @State private var askName = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Which car is this?")
                            .font(Tokens.display(24).weight(.medium))
                            .foregroundStyle(Tokens.ink)

                        ForEach(sessionManager.sessions) { existing in
                            Button {
                                park(replacing: existing.id, carName: nil)
                            } label: {
                                AlmanacCard {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Move \(existing.displayCarName) here")
                                            .font(Tokens.display(17).weight(.medium))
                                            .foregroundStyle(Tokens.ink)
                                        Text("was on \(existing.blockId.split(separator: "|").first.map(String.init) ?? "another block")")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Tokens.sub)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            newName = ""
                            askName = true
                        } label: {
                            AlmanacCard {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Tokens.clay)
                                    Text("Park another car")
                                        .font(Tokens.display(17).weight(.medium))
                                        .foregroundStyle(Tokens.clay)
                                }
                            }
                        }
                        .buttonStyle(.plain)
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
            .alert("Name this car", isPresented: $askName) {
                TextField("e.g. the Civic", text: $newName)
                Button("Park it") {
                    let fallback = "Car \(sessionManager.sessions.count + 1)"
                    park(replacing: nil,
                         carName: newName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? fallback : newName.trimmingCharacters(in: .whitespaces))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its reminders will carry the name so you always know "
                     + "which car has to move.")
            }
        }
    }

    private func park(replacing id: UUID?, carName: String?) {
        Task {
            await sessionManager.park(segments: segments, source: .manual,
                                      replacing: id, carName: carName)
            await model.scheduler.requestAuthorizationIfNeeded()
            await model.refreshAuthorizationStatus()
            onDone()
        }
    }
}
