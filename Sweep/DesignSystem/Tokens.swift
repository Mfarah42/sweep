import SweepCore
import SwiftUI
import UIKit

/// Design tokens (spec §7.1, dark mode added by user decision 2026-07-07).
/// Dark mode is "paper after sunset": the same warm almanac identity on deep
/// warm charcoal — never a generic gray theme. Every color is adaptive at the
/// token level, so screens and widgets follow automatically; Settings offers
/// System / Light / Dark.
public enum Tokens {

    // MARK: - Theme (curb-card themes are a Plus feature)

    /// Set from the persisted choice at app/widget startup and on change;
    /// views re-resolve because color properties are computed. The root view
    /// re-identifies on theme change to force a repaint.
    public static var theme: SweepTheme = .almanac

    /// Call once per process (app launch, widget render) before drawing.
    public static func loadTheme(from store: PersistenceStore) {
        theme = SweepTheme.theme(id: store.themeId)
    }

    // MARK: - Palette (light, dark)

    public static var paper: Color { dynamic(theme.paper) }
    public static var card: Color { dynamic(theme.card) }
    public static var ink: Color { dynamic(theme.ink) }
    public static var sub: Color { dynamic(theme.sub) }
    public static var line: Color { dynamic(theme.line) }
    public static var clay: Color { dynamic(theme.accent) }
    // Status colors are semantic and theme-independent — safe/warn/danger
    // must read the same in every wardrobe. Slightly brighter in the dark.
    public static let sage = dynamic(SweepTheme.Pair(0x5F8464, 0x83AC8A))
    public static let amber = dynamic(SweepTheme.Pair(0xC08A2D, 0xD5A34A))
    public static let rust = dynamic(SweepTheme.Pair(0xA8402F, 0xCE5B47))

    private static func dynamic(_ pair: SweepTheme.Pair) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
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
