import Foundation

/// One logical curb side of a block. A block label can span multiple source
/// features (Oakland splits long blocks), so a side may hold several segments;
/// the side question and the side cards operate on these groups, never on raw
/// segments — comparing raw segments can pair two same-side segments and skip
/// the question when it actually matters.
public struct BlockSide: Identifiable {
    public let sideKey: String
    public let segments: [SweepBundle.Segment]

    public var id: String { sideKey }

    /// Union of the side's effective rules (deduped by the engine's
    /// canonicalization when compared).
    public func mergedRules(overrides: [String: ScheduleRuleOverride]) -> [ScheduleRule] {
        segments.flatMap { OverrideDecorator.effectiveRules(segment: $0, overrides: overrides) }
    }

    public var landmark: String? { segments.compactMap(\.landmark).first }
    public var landmarkHint: String? { segments.compactMap(\.landmarkHint).first }
    public var landmarkConfidence: String? { segments.compactMap(\.landmarkConfidence).first }

    public var doorParity: String? {
        let parities = Set(segments.compactMap(\.doorParity))
        return parities.count == 1 ? parities.first : (parities.isEmpty ? nil : "mixed")
    }

    /// Merged door range across the side's segments, e.g. "3728–3898".
    public var doorRange: String? {
        let bounds = segments.compactMap { seg -> (Int, Int)? in
            guard let range = seg.doorRange else { return nil }
            let parts = range.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard let lo = parts.min(), let hi = parts.max() else { return nil }
            return (lo, hi)
        }
        guard let lo = bounds.map(\.0).min(), let hi = bounds.map(\.1).max() else { return nil }
        return "\(lo)–\(hi)"
    }

    /// The segment to store in the parking session for this side: the one
    /// whose next sweep comes first (most conservative when the side's
    /// segments disagree); ties break by id for determinism.
    public func parkTarget(at now: Date, calendar: Calendar, holidays: HolidayCalendar,
                           overrides: [String: ScheduleRuleOverride]) -> SweepBundle.Segment {
        segments.min { a, b in
            let na = nextStart(a, now: now, calendar: calendar, holidays: holidays, overrides: overrides)
            let nb = nextStart(b, now: now, calendar: calendar, holidays: holidays, overrides: overrides)
            return na == nb ? a.id < b.id : na < nb
        }!
    }

    private func nextStart(_ segment: SweepBundle.Segment, now: Date, calendar: Calendar,
                           holidays: HolidayCalendar,
                           overrides: [String: ScheduleRuleOverride]) -> Date {
        let rules = OverrideDecorator.effectiveRules(segment: segment, overrides: overrides)
        let verdict = VerdictEngine.verdict(rules: rules, city: segment.city, at: now,
                                            calendar: calendar, holidays: holidays)
        return verdict.next?.start ?? .distantFuture
    }
}

public enum BlockSides {

    /// Group a block's segments into its logical sides, sorted by side key.
    public static func group(_ segments: [SweepBundle.Segment]) -> [BlockSide] {
        Dictionary(grouping: segments, by: \.sideKey)
            .map { BlockSide(sideKey: $0.key, segments: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.sideKey < $1.sideKey }
    }

    /// The side question is skipped only when every side sweeps identically.
    public static func sidesAreEquivalent(_ sides: [BlockSide],
                                          overrides: [String: ScheduleRuleOverride]) -> Bool {
        guard let first = sides.first else { return true }
        let reference = first.mergedRules(overrides: overrides)
        return sides.dropFirst().allSatisfy {
            VerdictEngine.rulesAreEquivalent(reference, $0.mergedRules(overrides: overrides))
        }
    }
}
