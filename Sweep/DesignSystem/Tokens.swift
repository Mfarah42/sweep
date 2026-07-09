import SweepCore
import SwiftUI
import UIKit

/// Design tokens (spec §7.1, dark mode added by user decision 2026-07-07).
/// Dark mode is "paper after sunset": the same warm almanac identity on deep
/// warm charcoal — never a generic gray theme. Every color is adaptive at the
/// token level, so screens and widgets follow automatically; Settings offers
/// System / Light / Dark.
public enum Tokens {

    // MARK: - Palette (light, dark)

    public static let paper = dynamic(0xF6F3EC, 0x1B1915)
    public static let card = dynamic(0xFDFBF6, 0x26221B)
    public static let ink = dynamic(0x2C2A25, 0xEAE4D6)
    public static let sub = dynamic(0x6E6A60, 0xA69E8E)
    public static let line = dynamic(0xE4DFD3, 0x3B362C)
    // Status colors brighten slightly in the dark for contrast on charcoal.
    public static let clay = dynamic(0xBF5B3B, 0xD1704E)
    public static let sage = dynamic(0x5F8464, 0x83AC8A)
    public static let amber = dynamic(0xC08A2D, 0xD5A34A)
    public static let rust = dynamic(0xA8402F, 0xCE5B47)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
