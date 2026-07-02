import Foundation

/// A "sign says otherwise" correction (§7.5): one posted window that replaces
/// the bundle's rules for a segment, on this phone only. Overnight signs are
/// allowed in the form and split here (same rule as pipeline §4.5).
public struct ScheduleRuleOverride: Codable, Equatable, Sendable {
    public let weekday: Int       // 0=Sunday … 6=Saturday
    public let fromHour: Int      // 0…23
    public let toHour: Int        // 1…24; may be <= fromHour before splitting
    public let createdAt: Date

    public init(weekday: Int, fromHour: Int, toHour: Int, createdAt: Date) {
        self.weekday = weekday
        self.fromHour = fromHour
        self.toHour = toHour
        self.createdAt = createdAt
    }

    /// Engine-ready rules; splits overnight windows so the engine never sees
    /// wraparound. holidayEnforced follows the city default.
    public func rules(for city: City) -> [ScheduleRule] {
        let enforced = city == .sf
        if toHour > fromHour {
            return [ScheduleRule(weekday: weekday, weeks: nil, fromHour: fromHour,
                                 toHour: toHour, holidayEnforced: enforced)]
        }
        var out = [ScheduleRule(weekday: weekday, weeks: nil, fromHour: fromHour,
                                toHour: 24, holidayEnforced: enforced)]
        if toHour > 0 {
            out.append(ScheduleRule(weekday: (weekday + 1) % 7, weeks: nil, fromHour: 0,
                                    toHour: toHour, holidayEnforced: enforced))
        }
        return out
    }
}

/// Decorator over bundle reads (§7.5): a local correction replaces the
/// segment's rules everywhere — verdicts, reminders, widgets.
public enum OverrideDecorator {
    public static func effectiveRules(segment: SweepBundle.Segment,
                                      overrides: [String: ScheduleRuleOverride]) -> [ScheduleRule] {
        if let override = overrides[segment.id] {
            return override.rules(for: segment.city)
        }
        return segment.rules
    }

    public static func hasCorrection(segmentId: String,
                                     overrides: [String: ScheduleRuleOverride]) -> Bool {
        overrides[segmentId] != nil
    }
}
