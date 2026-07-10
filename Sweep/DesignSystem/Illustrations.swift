import SwiftUI

/// Watermark illustration for the empty home screen: the little cab-forward
/// parking-enforcement interceptor (tall box, raked windshield, amber beacon,
/// dark glass, black skirt), ticket fluttering off behind. Drawn from shapes
/// (no assets) in token colors at low opacity so it prints onto the paper and
/// adapts to dark mode automatically. Decorative only — hidden from VoiceOver.
public struct EnforcementCartIllustration: View {

    public init() {}

    public var body: some View {
        ZStack {
            // The ticket, drifting off behind the cart.
            ticket
                .frame(width: 34, height: 46)
                .rotationEffect(.degrees(14))
                .offset(x: 124, y: -52)

            cart
        }
        .frame(width: 300, height: 180)
        .opacity(0.13)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var cart: some View {
        ZStack {
            // Road
            Path { p in
                p.move(to: CGPoint(x: 0, y: 158))
                p.addLine(to: CGPoint(x: 300, y: 158))
            }
            .stroke(Tokens.ink, style: StrokeStyle(lineWidth: 3, dash: [14, 10]))
            .frame(width: 300, height: 180)

            // Beacon: small base + amber light
            RoundedRectangle(cornerRadius: 2)
                .fill(Tokens.ink)
                .frame(width: 16, height: 7)
                .offset(x: -40, y: -66)
            Capsule()
                .fill(Tokens.amber)
                .frame(width: 20, height: 13)
                .offset(x: -40, y: -75)

            // Body: one tall cab-forward box (outlined cream, like the inspo)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Tokens.paper)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Tokens.ink, lineWidth: 5))
                .frame(width: 200, height: 108)
                .offset(x: 6, y: -8)

            // Dark glass: windshield, door window, rear side window
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 40, height: 38)
                .offset(x: -62, y: -30)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 42, height: 38)
                .offset(x: -12, y: -30)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 38, height: 38)
                .offset(x: 36, y: -30)

            // Mirror on the front pillar
            RoundedRectangle(cornerRadius: 3)
                .fill(Tokens.ink)
                .frame(width: 10, height: 14)
                .offset(x: -92, y: -22)

            // Headlight on the front face
            Circle()
                .strokeBorder(Tokens.ink, lineWidth: 4)
                .frame(width: 18, height: 18)
                .offset(x: -80, y: 8)

            // Livery text on the rear panel
            VStack(spacing: 2) {
                Text("PARKING")
                Text("ENFORCEMENT")
            }
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(Tokens.ink)
            .offset(x: 44, y: 8)

            // Black skirt / bumper line
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 192, height: 11)
                .offset(x: 6, y: 38)

            // Wheels
            wheel.offset(x: -52, y: 46)
            wheel.offset(x: 62, y: 46)
        }
        .frame(width: 300, height: 180)
    }

    private var wheel: some View {
        ZStack {
            Circle().fill(Tokens.ink).frame(width: 42, height: 42)
            Circle().fill(Tokens.paper).frame(width: 18, height: 18)
            Circle().fill(Tokens.ink).frame(width: 5, height: 5)
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
