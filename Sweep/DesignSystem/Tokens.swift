import SweepCore
import SwiftUI

/// Design tokens (spec §7.1). v1 ships light-only by design — paper is the
/// brand; the root view sets .preferredColorScheme(.light).
public enum Tokens {

    // MARK: - Palette

    public static let paper = Color(hex: 0xF6F3EC)
    public static let card = Color(hex: 0xFDFBF6)
    public static let ink = Color(hex: 0x2C2A25)
    public static let sub = Color(hex: 0x6E6A60)
    public static let line = Color(hex: 0xE4DFD3)
    public static let clay = Color(hex: 0xBF5B3B)
    public static let sage = Color(hex: 0x5F8464)
    public static let amber = Color(hex: 0xC08A2D)
    public static let rust = Color(hex: 0xA8402F)

    // MARK: - Radii

    public static let radiusCard: CGFloat = 22
    public static let radiusControl: CGFloat = 16
    public static let radiusSideCard: CGFloat = 18
    public static let radiusPill: CGFloat = 999

    // MARK: - Type
    // Display = Fraunces (bundled variable font, SIL OFL — license in
    // Settings > About). Body = SF Pro (system). Scales with Dynamic Type.

    public static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Fraunces", size: size, relativeTo: style)
    }

    public static func displayItalic(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Fraunces-Italic", size: size, relativeTo: style).italic()
    }

    /// Verdict headline: 34pt Fraunces 500 (§7.1).
    public static var verdictHeadline: Font {
        display(34, relativeTo: .largeTitle).weight(.medium)
    }

    /// Status words: 13.5pt semibold in status color (§7.1).
    public static var statusWord: Font {
        .system(size: 13.5, weight: .semibold)
    }

    public static func statusColor(_ state: VerdictStateUI) -> Color {
        switch state {
        case .safe: return sage
        case .moveSoon: return amber
        case .sweepingNow: return rust
        case .none: return sub
        }
    }
}

// VerdictStateUI lives in SweepCore (Core/Engine/SweepFormat.swift).

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
