import SwiftUI

/// Watermark illustration for the empty home screen: the little three-wheeled
/// parking-enforcement cart, ticket fluttering behind it. Drawn from shapes
/// (no assets) in ink tones at low opacity, so it prints onto the paper and
/// adapts to dark mode automatically. Decorative only — hidden from VoiceOver.
public struct EnforcementCartIllustration: View {

    public init() {}

    public var body: some View {
        ZStack {
            // The ticket, drifting off behind the cart.
            ticket
                .frame(width: 34, height: 46)
                .rotationEffect(.degrees(14))
                .offset(x: 104, y: -34)

            cart
        }
        .frame(width: 260, height: 150)
        .opacity(0.1)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var cart: some View {
        ZStack {
            // Road
            Path { p in
                p.move(to: CGPoint(x: 0, y: 144))
                p.addLine(to: CGPoint(x: 260, y: 144))
            }
            .stroke(Tokens.ink, style: StrokeStyle(lineWidth: 3, dash: [14, 10]))

            // Beacon light
            Capsule()
                .fill(Tokens.ink)
                .frame(width: 18, height: 12)
                .offset(x: -40, y: -56)

            // Cab at the back (tall, boxy — the classic interceptor silhouette)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 110, height: 64)
                .offset(x: -40, y: -16)

            // Body with a low hood out front
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 212, height: 42)
                .offset(x: 4, y: 15)

            // Cab windows (paper punches through the ink)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Tokens.paper)
                .frame(width: 38, height: 26)
                .offset(x: -64, y: -24)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Tokens.paper)
                .frame(width: 30, height: 26)
                .offset(x: -18, y: -24)

            // "P" badge on the hood
            Circle()
                .fill(Tokens.paper)
                .frame(width: 24, height: 24)
                .offset(x: 66, y: 15)
            Text("P")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Tokens.ink)
                .offset(x: 66, y: 15)

            // Wheels
            wheel.offset(x: -62, y: 40)
            wheel.offset(x: 74, y: 40)
        }
    }

    private var wheel: some View {
        ZStack {
            Circle().fill(Tokens.ink).frame(width: 38, height: 38)
            Circle().fill(Tokens.paper).frame(width: 14, height: 14)
        }
    }

    private var ticket: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Tokens.paper)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Tokens.ink, lineWidth: 2.5)
            VStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(Tokens.ink).frame(width: 20, height: 3)
                }
            }
        }
    }
}
