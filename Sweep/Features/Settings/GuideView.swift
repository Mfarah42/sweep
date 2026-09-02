import SweepCore
import SwiftUI

/// "How Sweep works" — a short, scannable guide reachable from the empty
/// home screen and from Settings. Plain answers to the questions people
/// actually ask: what to tap, why it asks about sides, what to do when the
/// sign disagrees, and why a reminder might not have fired.
struct GuideView: View {

    private struct Step: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let steps: [Step] = [
        Step(symbol: "car.fill",
             title: "1. Park, then tap “I just parked”",
             body: "Do it right after you park, while you're still at the car. "
                 + "Sweep takes one location fix, works out whether you're in "
                 + "San Francisco or Oakland, and finds your block. Indoors or "
                 + "no GPS? Type the street or address instead — both cities are "
                 + "searched, so you never have to switch anything first."),
        Step(symbol: "arrow.left.and.right",
             title: "2. Pick your side of the street",
             body: "Many blocks sweep each side on different days, so Sweep asks "
                 + "which side you're on. It describes sides by the door numbers "
                 + "(even or odd) or by what you can see — never by compass "
                 + "directions. If both sides sweep at the same time it skips the "
                 + "question. Live on the block? “Both sides” watches the whole thing."),
        Step(symbol: "checkmark.circle.fill",
             title: "3. Read the verdict",
             body: "Safe, Move soon, or Sweeping now — plus the exact time the next "
                 + "sweep starts and a countdown. Coming-up rows show the sweeps "
                 + "after that. The posted sign always wins if it disagrees."),
        Step(symbol: "bell.fill",
             title: "4. Let the reminders do the remembering",
             body: "Allow notifications when Sweep asks. You'll get a heads-up the "
                 + "evening before, a two-hour warning, and a last call thirty "
                 + "minutes out. Alerts are Time Sensitive, so they break through "
                 + "most Focus modes. Didn't get one? Check Settings → Notifications "
                 + "→ Sweep on your phone, and that the toggles are on in Sweep's "
                 + "own Settings."),
        Step(symbol: "figure.walk",
             title: "5. Moved the car? Say so",
             body: "Tap “I moved my car” and every reminder for that spot is "
                 + "cancelled. Park again and the cycle starts fresh."),
        Step(symbol: "exclamationmark.triangle.fill",
             title: "6. Sign says otherwise?",
             body: "City data can lag the street. Tap “Sign says otherwise?” and "
                 + "type what the sign says. Your block is corrected on your phone "
                 + "and every alert follows the sign from then on."),
        Step(symbol: "rectangle.3.group.fill",
             title: "7. Widgets and the lock screen",
             body: "Add the Sweep widget to your home or lock screen for the verdict "
                 + "at a glance. In the final hours before a sweep, a Live Activity "
                 + "counts down on the lock screen."),
        Step(symbol: "sparkles",
             title: "Sweep Plus (optional)",
             body: "Every ticket-saving alert above is free forever. Plus is a one-time "
                 + "purchase that adds a second car, curb-card themes, and Longest "
                 + "Spot, which finds the nearby block you can stay on longest."),
    ]

    var body: some View {
        ZStack {
            Tokens.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tell it once. It watches the schedule so you don't have to.")
                        .font(Tokens.displayItalic(20))
                        .foregroundStyle(Tokens.sub)
                        .padding(.bottom, 2)
                    ForEach(steps) { step in
                        AlmanacCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: step.symbol)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Tokens.clay)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(step.title)
                                        .font(Tokens.display(17).weight(.medium))
                                        .foregroundStyle(Tokens.ink)
                                    Text(step.body)
                                        .font(.system(size: 14.5))
                                        .foregroundStyle(Tokens.sub)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    Text("Sweep is an independent app and isn't affiliated with SFMTA "
                         + "or the City of Oakland. Always check the posted sign.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.sub)
                        .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .navigationTitle("How Sweep works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
