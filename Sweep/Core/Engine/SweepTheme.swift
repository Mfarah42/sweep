import Foundation

/// Curb-card themes (Sweep Plus §11): alternate neutral palettes for the
/// paper/card/ink/accent roles. Status colors (sage/amber/rust) are semantic
/// safety colors and never vary by theme. Each role is a (light, dark) pair
/// of sRGB hex values.
public struct SweepTheme: Identifiable, Equatable, Sendable {
    public struct Pair: Equatable, Sendable {
        public let light: UInt32
        public let dark: UInt32

        public init(_ light: UInt32, _ dark: UInt32) {
            self.light = light
            self.dark = dark
        }
    }

    public let id: String
    public let name: String
    public let paper: Pair
    public let card: Pair
    public let ink: Pair
    public let sub: Pair
    public let line: Pair
    public let accent: Pair
    /// Free tier ships the default; the rest are Plus.
    public let isPlus: Bool

    /// The almanac look — the brand default.
    public static let almanac = SweepTheme(
        id: "almanac", name: "Almanac",
        paper: Pair(0xF6F3EC, 0x1B1915),
        card: Pair(0xFDFBF6, 0x26221B),
        ink: Pair(0x2C2A25, 0xEAE4D6),
        sub: Pair(0x6E6A60, 0xA69E8E),
        line: Pair(0xE4DFD3, 0x3B362C),
        accent: Pair(0xBF5B3B, 0xD1704E),
        isPlus: false)

    /// Cool, quiet neutrals with a coral accent.
    public static let harbor = SweepTheme(
        id: "harbor", name: "Harbor",
        paper: Pair(0xFEFBF6, 0x18181C),
        card: Pair(0xF3F0EB, 0x252429),
        ink: Pair(0x19191D, 0xF5F2ED),
        sub: Pair(0x5A5655, 0xB7B2B0),
        line: Pair(0xDEDAD5, 0x3A393E),
        accent: Pair(0xC97A62, 0xD08069),
        isPlus: true)

    /// Warm adobe tones.
    public static let ember = SweepTheme(
        id: "ember", name: "Ember",
        paper: Pair(0xFAF6EF, 0x191512),
        card: Pair(0xF2EDE2, 0x231E19),
        ink: Pair(0x26211B, 0xF2EBDF),
        sub: Pair(0x6F6759, 0x9B9288),
        line: Pair(0xDED6C6, 0x2C2620),
        accent: Pair(0xC06A4D, 0xD6845F),
        isPlus: true)

    public static let all: [SweepTheme] = [.almanac, .harbor, .ember]

    public static func theme(id: String?) -> SweepTheme {
        all.first { $0.id == id } ?? .almanac
    }
}
