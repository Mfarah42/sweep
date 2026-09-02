import Foundation

/// Address-aware block search for the manual flow. "1091 53rd" parses the
/// house number, ranks blocks whose door ranges contain it first (respecting
/// parity — 1091 only matches odd-side ranges), and every hit carries a door
/// summary so twins like 53rd St / 53rd Ave are tellable apart before tapping.
/// SF door ranges are absent from the source, so SF degrades to name search.
public enum BlockSearch {

    public struct Hit: Identifiable, Equatable {
        public let street: String
        public let blockLabel: String
        /// Merged door span across the block's segments, e.g. "1036–1127".
        public let doorSummary: String?
        /// True when the parsed house number falls in this block's doors.
        public let matchesNumber: Bool
        /// Which city's bundle produced this hit. Search runs across every
        /// installed city so a wrong Settings toggle can never hide a street.
        public let city: City

        public var id: String { "\(city.rawValue)|\(street)|\(blockLabel)" }
    }

    /// Search every installed city at once. Address matches still rank first;
    /// ties keep the caller's bundle order (put the user's current city first).
    public static func hits(bundles: [SweepBundle], query: String, limit: Int = 60) -> [Hit] {
        var all: [Hit] = []
        for bundle in bundles {
            all += hits(bundle: bundle, query: query, limit: limit)
        }
        all.sort { a, b in
            if a.matchesNumber != b.matchesNumber { return a.matchesNumber }
            return false   // stable: keeps per-bundle order and bundle order
        }
        return Array(all.prefix(limit))
    }

    /// "1091 53rd st" → (1091, "53rd st"); "Maybelle" → (nil, "Maybelle").
    public static func parse(_ query: String) -> (number: Int?, streetQuery: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        if parts.count == 2, let n = Int(parts[0]), n > 0 {
            return (n, String(parts[1]))
        }
        return (nil, trimmed)
    }

    public static func hits(bundle: SweepBundle, query: String, limit: Int = 60) -> [Hit] {
        let (number, streetQuery) = parse(query)
        guard streetQuery.count >= 2 else { return [] }

        var byBlock: [String: (street: String, label: String,
                               bounds: [(Int, Int)], matches: Bool)] = [:]
        for row in bundle.blockRows(streetMatching: streetQuery) {
            var entry = byBlock[row.street + "|" + row.blockLabel]
                ?? (row.street, row.blockLabel, [], false)
            if let span = parseRange(row.doorRange) {
                entry.bounds.append(span)
                if let number, span.0 <= number, number <= span.1,
                   parityMatches(number, parity: row.doorParity) {
                    entry.matches = true
                }
            }
            byBlock[row.street + "|" + row.blockLabel] = entry
        }

        var hits = byBlock.values.map { entry in
            Hit(street: entry.street,
                blockLabel: entry.label,
                doorSummary: entry.bounds.isEmpty ? nil
                    : "\(entry.bounds.map(\.0).min()!)–\(entry.bounds.map(\.1).max()!)",
                matchesNumber: entry.matches,
                city: bundle.manifest.city)
        }
        // Address matches first, then streets alphabetically, blocks in order.
        hits.sort {
            if $0.matchesNumber != $1.matchesNumber { return $0.matchesNumber }
            if $0.street != $1.street { return $0.street < $1.street }
            return $0.blockLabel.localizedStandardCompare($1.blockLabel) == .orderedAscending
        }
        return Array(hits.prefix(limit))
    }

    static func parseRange(_ doorRange: String?) -> (Int, Int)? {
        guard let doorRange else { return nil }
        let nums = doorRange.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let lo = nums.min(), let hi = nums.max() else { return nil }
        return (lo, hi)
    }

    static func parityMatches(_ number: Int, parity: String?) -> Bool {
        switch parity {
        case "even": return number.isMultiple(of: 2)
        case "odd": return !number.isMultiple(of: 2)
        default: return true   // mixed/unknown — don't exclude
        }
    }
}
