import SwiftUI

/// Watermark illustration for the empty home screen: a tiny, slightly wonky
/// parking-enforcement cart with a cab-forward profile, oversized wheels, an
/// eager face, and a ticket escaping out the back. Drawn entirely from shapes
/// in token colors so it stays at home on the app's paper in either color mode.
/// Decorative only — hidden from VoiceOver.
public struct EnforcementCartIllustration: View {

    public init() {}

    public var body: some View {
        ZStack {
            ticketMotion

            ticket
                .frame(width: 38, height: 50)
                .rotationEffect(.degrees(13))
                .offset(x: 124, y: -52)

            road
            vehicle
        }
        .frame(width: 300, height: 180)
        .opacity(0.13)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var vehicle: some View {
        ZStack {
            antenna
            beaconRays

            // A proper cab-forward silhouette gives the little cart a nose,
            // raked windshield, high roof, and rounded equipment compartment.
            CartBodyShape()
                .fill(Tokens.paper)
                .overlay {
                    CartBodyShape()
                        .stroke(Tokens.ink,
                                style: StrokeStyle(lineWidth: 5,
                                                   lineJoin: .round))
                }
                .frame(width: 224, height: 110)
                .offset(x: 4, y: -7)

            glazing
            driver
            bodyDetails

            wheel(size: 44)
                .rotationEffect(.degrees(-7))
                .offset(x: -58, y: 47)
            wheel(size: 48)
                .rotationEffect(.degrees(8))
                .offset(x: 68, y: 46)

            // Fenders tuck the tires visually into the body.
            WheelArchShape()
                .stroke(Tokens.ink,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 52, height: 25)
                .offset(x: -58, y: 36)
            WheelArchShape()
                .stroke(Tokens.ink,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 56, height: 27)
                .offset(x: 68, y: 34)

            beacon
        }
        .frame(width: 300, height: 180)
        .rotationEffect(.degrees(-0.8))
    }

    private var glazing: some View {
        ZStack {
            WindshieldShape()
                .fill(Tokens.ink)
                .frame(width: 43, height: 42)
                .offset(x: -67, y: -31)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 44, height: 40)
                .offset(x: -18, y: -31)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 38, height: 35)
                .offset(x: 29, y: -33)

            // One chunky wiper is more legible than tiny realistic hardware at
            // watermark opacity.
            Path { path in
                path.move(to: CGPoint(x: 2, y: 12))
                path.addLine(to: CGPoint(x: 24, y: 2))
            }
            .stroke(Tokens.paper,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 26, height: 14)
            .offset(x: -67, y: -22)
        }
    }

    private var driver: some View {
        ZStack {
            // A tiny round-headed attendant peeking over the wheel.
            Circle()
                .fill(Tokens.paper)
                .frame(width: 12, height: 12)
                .offset(x: -23, y: -36)
            Capsule()
                .fill(Tokens.paper)
                .frame(width: 21, height: 11)
                .offset(x: -21, y: -22)

            Circle()
                .stroke(Tokens.paper, lineWidth: 2.5)
                .frame(width: 14, height: 14)
                .offset(x: -5, y: -17)
            Capsule()
                .fill(Tokens.paper)
                .frame(width: 2.5, height: 13)
                .rotationEffect(.degrees(-35))
                .offset(x: -8, y: -17)
        }
    }

    private var bodyDetails: some View {
        ZStack {
            // Enforcement livery and the practical little door hardware keep
            // the cart believable even though its proportions are playful.
            Capsule()
                .fill(Tokens.clay)
                .frame(width: 137, height: 8)
                .offset(x: 29, y: 5)

            VStack(spacing: 0) {
                Text("PARKING")
                Text("ENFORCEMENT")
            }
            .font(.system(size: 7, weight: .black, design: .rounded))
            .foregroundStyle(Tokens.ink)
            .offset(x: 61, y: 22)

            Capsule()
                .fill(Tokens.ink)
                .frame(width: 2.5, height: 55)
                .offset(x: 7, y: 10)
            Capsule()
                .fill(Tokens.ink)
                .frame(width: 13, height: 3)
                .offset(x: -2, y: -5)
            Circle()
                .stroke(Tokens.ink, lineWidth: 2.5)
                .frame(width: 11, height: 11)
                .offset(x: 91, y: 20)

            // Mirror and arm.
            Capsule()
                .fill(Tokens.ink)
                .frame(width: 3.5, height: 14)
                .rotationEffect(.degrees(38))
                .offset(x: -91, y: -25)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Tokens.ink)
                .frame(width: 11, height: 15)
                .rotationEffect(.degrees(-8))
                .offset(x: -98, y: -22)

            // Oversized headlight + tiny marker: one bright, eager eye.
            ZStack {
                Circle().fill(Tokens.amber)
                Circle().stroke(Tokens.ink, lineWidth: 3)
                Circle()
                    .fill(Tokens.paper)
                    .frame(width: 5, height: 5)
                    .offset(x: -3, y: -3)
            }
            .frame(width: 20, height: 20)
            .offset(x: -94, y: 6)

            Capsule()
                .fill(Tokens.amber)
                .overlay(Capsule().stroke(Tokens.ink, lineWidth: 2))
                .frame(width: 8, height: 12)
                .offset(x: -104, y: -10)

            Capsule()
                .fill(Tokens.rust)
                .frame(width: 8, height: 20)
                .offset(x: 111, y: 5)

            // The lower grille curves into a quiet smile.
            Path { path in
                path.move(to: CGPoint(x: 1, y: 2))
                path.addQuadCurve(to: CGPoint(x: 25, y: 2),
                                  control: CGPoint(x: 13, y: 14))
            }
            .stroke(Tokens.ink,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 26, height: 14)
            .offset(x: -94, y: 23)

            // Split rocker panels leave room for the wheels.
            Capsule()
                .fill(Tokens.ink)
                .frame(width: 29, height: 8)
                .offset(x: -101, y: 39)
            Capsule()
                .fill(Tokens.ink)
                .frame(width: 72, height: 8)
                .offset(x: 5, y: 42)
            Capsule()
                .fill(Tokens.ink)
                .frame(width: 25, height: 8)
                .offset(x: 105, y: 39)
        }
    }

    private var antenna: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 2, y: 34))
                path.addQuadCurve(to: CGPoint(x: 13, y: 2),
                                  control: CGPoint(x: 4, y: 16))
            }
            .stroke(Tokens.ink,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 15, height: 36)
            .offset(x: 76, y: -71)

            Circle()
                .fill(Tokens.clay)
                .overlay(Circle().stroke(Tokens.ink, lineWidth: 2))
                .frame(width: 8, height: 8)
                .offset(x: 82, y: -88)
        }
    }

    private var beacon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Tokens.ink)
                .frame(width: 19, height: 7)
                .offset(y: 7)
            Capsule()
                .fill(Tokens.amber)
                .overlay(Capsule().stroke(Tokens.ink, lineWidth: 2))
                .frame(width: 21, height: 15)
            Capsule()
                .fill(Tokens.paper)
                .frame(width: 4, height: 9)
                .offset(x: -4, y: -1)
        }
        .rotationEffect(.degrees(7))
        .offset(x: -38, y: -73)
    }

    private var beaconRays: some View {
        Path { path in
            path.move(to: CGPoint(x: 4, y: 15))
            path.addLine(to: CGPoint(x: 0, y: 11))
            path.move(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 0))
            path.move(to: CGPoint(x: 32, y: 15))
            path.addLine(to: CGPoint(x: 36, y: 11))
        }
        .stroke(Tokens.amber,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .frame(width: 36, height: 16)
        .offset(x: -38, y: -88)
    }

    private func wheel(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Tokens.ink)
            Circle()
                .fill(Tokens.paper)
                .frame(width: size * 0.48, height: size * 0.48)
            Circle()
                .stroke(Tokens.ink, lineWidth: 2)
                .frame(width: size * 0.48, height: size * 0.48)
            Circle()
                .fill(Tokens.ink)
                .frame(width: size * 0.12, height: size * 0.12)

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Tokens.ink)
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: -size * 0.15)
                    .rotationEffect(.degrees(Double(index) * 120))
            }
        }
        .frame(width: size, height: size)
    }

    private var ticket: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Tokens.paper)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Tokens.ink, lineWidth: 2.5)

            VStack(spacing: 4) {
                Text("TICKET")
                    .font(.system(size: 6.5, weight: .black, design: .rounded))
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .frame(width: 22, height: 3)
                }
            }
            .foregroundStyle(Tokens.ink)
        }
    }

    private var ticketMotion: some View {
        Path { path in
            path.move(to: CGPoint(x: 1, y: 25))
            path.addQuadCurve(to: CGPoint(x: 31, y: 2),
                              control: CGPoint(x: 22, y: 27))
            path.move(to: CGPoint(x: 4, y: 32))
            path.addQuadCurve(to: CGPoint(x: 35, y: 12),
                              control: CGPoint(x: 24, y: 34))
        }
        .stroke(Tokens.ink,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .frame(width: 36, height: 34)
        .offset(x: 98, y: -43)
    }

    private var road: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 2, y: 158))
                path.addLine(to: CGPoint(x: 298, y: 158))
            }
            .stroke(Tokens.ink,
                    style: StrokeStyle(lineWidth: 3,
                                       lineCap: .round,
                                       dash: [25, 13]))

            Circle()
                .fill(Tokens.ink)
                .frame(width: 5, height: 5)
                .offset(x: -126, y: 72)
        }
        .frame(width: 300, height: 180)
    }
}

private struct CartBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.01, y: y + h * 0.91))
        path.addLine(to: CGPoint(x: x + w * 0.01, y: y + h * 0.51))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.12, y: y + h * 0.36),
                          control: CGPoint(x: x + w * 0.02, y: y + h * 0.38))
        path.addLine(to: CGPoint(x: x + w * 0.20, y: y + h * 0.12))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.30, y: y + h * 0.03),
                          control: CGPoint(x: x + w * 0.23, y: y + h * 0.03))
        path.addLine(to: CGPoint(x: x + w * 0.86, y: y + h * 0.03))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.99, y: y + h * 0.22),
                          control: CGPoint(x: x + w * 0.98, y: y + h * 0.03))
        path.addLine(to: CGPoint(x: x + w * 0.99, y: y + h * 0.82))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.92, y: y + h * 0.97),
                          control: CGPoint(x: x + w * 0.99, y: y + h * 0.96))
        path.addLine(to: CGPoint(x: x + w * 0.10, y: y + h * 0.97))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.01, y: y + h * 0.91),
                          control: CGPoint(x: x + w * 0.02, y: y + h * 0.97))
        path.closeSubpath()
        return path
    }
}

private struct WindshieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06,
                              y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.34,
                                 y: rect.minY + rect.height * 0.10))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.47,
                                      y: rect.minY),
                          control: CGPoint(x: rect.minX + rect.width * 0.38,
                                           y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct WheelArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.midX,
                                           y: rect.minY - rect.height * 0.25))
        return path
    }
}
