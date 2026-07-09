import Foundation

public struct GeoPoint: Equatable, Sendable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Curb snapping — DECIDED algorithm (spec §6.2). Pure: takes the coarse
/// candidate set (from SweepBundle.segments(near:)) and one fix.
public enum CurbSnapper {

    public static let fineRadiusMeters: Double = 35
    public static let highConfidenceGapMeters: Double = 15

    public struct Block: Equatable, Sendable {
        public let street: String
        public let blockLabel: String
        public let segmentIds: [String]
        public let distanceMeters: Double
    }

    public enum Confidence: Equatable, Sendable {
        case high
        /// Show block-confirm with the runner-up listed first in the picker.
        case ambiguous
    }

    public struct SnapResult: Equatable, Sendable {
        public let block: Block
        public let runnerUp: Block?
        public let confidence: Confidence
    }

    /// `fineRadius` defaults to the spec's 35 m but must be widened to match
    /// the fix accuracy — a 60 m-accurate indoor fix can land past 35 m from
    /// every curb while the user is standing on the block.
    public static func snap(fix: GeoPoint, candidates: [SweepBundle.Segment],
                            fineRadius: Double = fineRadiusMeters) -> SnapResult? {
        // Fine filter: point-to-polyline distance (§6.2.2).
        var byBlock: [String: (street: String, label: String, ids: [String], d: Double)] = [:]
        for seg in candidates {
            let d = distanceMeters(from: fix, toPolyline: seg.geometry)
            guard d <= fineRadius else { continue }
            var entry = byBlock[seg.blockKey] ?? (seg.street, seg.blockLabel, [], .infinity)
            entry.ids.append(seg.id)
            entry.d = min(entry.d, d)
            byBlock[seg.blockKey] = entry
        }
        guard !byBlock.isEmpty else { return nil }

        let blocks = byBlock.values
            .map { Block(street: $0.street, blockLabel: $0.label,
                         segmentIds: $0.ids.sorted(), distanceMeters: $0.d) }
            .sorted { $0.distanceMeters < $1.distanceMeters }

        let best = blocks[0]
        let runnerUp = blocks.count > 1 ? blocks[1] : nil
        // Never choose the side from GPS (§6.2.3); side is the user's call.
        let confidence: Confidence
        if let ru = runnerUp, ru.distanceMeters - best.distanceMeters < highConfidenceGapMeters {
            confidence = .ambiguous
        } else {
            confidence = .high
        }
        return SnapResult(block: best, runnerUp: runnerUp, confidence: confidence)
    }

    // MARK: - Geometry (equirectangular approximation — fine at city scale)

    public static func distanceMeters(from p: GeoPoint, toPolyline line: [GeoPoint]) -> Double {
        guard !line.isEmpty else { return .infinity }
        if line.count == 1 { return distanceMeters(p, line[0]) }
        var best = Double.infinity
        for i in 0..<(line.count - 1) {
            best = min(best, distanceMeters(from: p, toSegment: (line[i], line[i + 1])))
        }
        return best
    }

    static func distanceMeters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let kx = 111_320.0 * cos((a.lat + b.lat) / 2 * .pi / 180)
        let dx = (a.lon - b.lon) * kx
        let dy = (a.lat - b.lat) * 111_320.0
        return (dx * dx + dy * dy).squareRoot()
    }

    static func distanceMeters(from p: GeoPoint, toSegment seg: (GeoPoint, GeoPoint)) -> Double {
        let kx = 111_320.0 * cos(p.lat * .pi / 180)
        let ax = seg.0.lon * kx, ay = seg.0.lat * 111_320.0
        let bx = seg.1.lon * kx, by = seg.1.lat * 111_320.0
        let px = p.lon * kx, py = p.lat * 111_320.0
        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        var t = lenSq == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / lenSq
        t = max(0, min(1, t))
        let cx = ax + t * dx, cy = ay + t * dy
        return ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
    }
}
