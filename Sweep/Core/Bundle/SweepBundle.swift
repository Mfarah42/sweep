import Foundation
import SQLite3

/// Read-only access to a .sweepbundle SQLite file (spec §4.6).
/// Thread-confined: create one per queue, or use through BundleStore.
public final class SweepBundle {

    public struct Manifest: Sendable {
        public let schemaVersion: String
        public let city: City
        public let sourceUpdatedAt: String
        public let builtAt: String
    }

    public struct Segment: Identifiable, Sendable {
        public let id: String
        public let city: City
        public let street: String
        public let blockLabel: String
        public let sideKey: String
        public let doorParity: String?
        public let doorRange: String?
        public let landmark: String?
        public let landmarkHint: String?
        public let landmarkConfidence: String?
        public let geometry: [GeoPoint]   // decoded from [[lat,lon]] doubles
        public let rules: [ScheduleRule]

        /// Block identity for grouping (§6.2.3).
        public var blockKey: String { "\(street)|\(blockLabel)" }
    }

    public enum BundleError: Error {
        case cannotOpen(String)
        case badManifest
    }

    private var db: OpaquePointer?
    public let manifest: Manifest

    public init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let h = handle else {
            sqlite3_close(handle)
            throw BundleError.cannotOpen(path)
        }
        db = h
        var entries: [String: String] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "SELECT key, value FROM manifest", -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_close(h)
            throw BundleError.badManifest
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries[String(cString: sqlite3_column_text(stmt, 0))] =
                String(cString: sqlite3_column_text(stmt, 1))
        }
        sqlite3_finalize(stmt)
        guard let cityRaw = entries["city"], let city = City(rawValue: cityRaw) else {
            sqlite3_close(h)
            throw BundleError.badManifest
        }
        manifest = Manifest(schemaVersion: entries["schema_version"] ?? "?",
                            city: city,
                            sourceUpdatedAt: entries["source_updated_at"] ?? "",
                            builtAt: entries["built_at"] ?? "")
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Queries

    /// Coarse spatial filter: segments whose bbox (expanded by `marginMeters`)
    /// contains the point (§6.2.1).
    public func segments(near point: GeoPoint, marginMeters: Double = 40) -> [Segment] {
        let dLat = marginMeters / 111_320.0
        let dLon = marginMeters / (111_320.0 * cos(point.lat * .pi / 180))
        let sql = """
            SELECT id, city, street, block_label, side_key, door_parity, door_range,
                   landmark, landmark_hint, landmark_confidence, geometry
            FROM segments
            WHERE max_lat >= ? AND min_lat <= ? AND max_lon >= ? AND min_lon <= ?
            ORDER BY id
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, point.lat - dLat)
        sqlite3_bind_double(stmt, 2, point.lat + dLat)
        sqlite3_bind_double(stmt, 3, point.lon - dLon)
        sqlite3_bind_double(stmt, 4, point.lon + dLon)
        return readSegments(stmt)
    }

    public func segment(id: String) -> Segment? {
        let sql = """
            SELECT id, city, street, block_label, side_key, door_parity, door_range,
                   landmark, landmark_hint, landmark_confidence, geometry
            FROM segments WHERE id = ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return readSegments(stmt).first
    }

    /// All segments on the same block (both sides) as the given segment.
    public func blockSegments(street: String, blockLabel: String) -> [Segment] {
        let sql = """
            SELECT id, city, street, block_label, side_key, door_parity, door_range,
                   landmark, landmark_hint, landmark_confidence, geometry
            FROM segments WHERE street = ? AND block_label = ? ORDER BY side_key
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, street, -1, transient)
        sqlite3_bind_text(stmt, 2, blockLabel, -1, transient)
        return readSegments(stmt)
    }

    /// Raw rows for address-aware search (BlockSearch): one row per segment
    /// with its door metadata, matched on street name.
    public func blockRows(streetMatching query: String, limit: Int = 400)
        -> [(street: String, blockLabel: String, doorRange: String?, doorParity: String?)] {
        let sql = """
            SELECT street, block_label, door_range, door_parity FROM segments
            WHERE street LIKE ? ORDER BY street, block_label, id LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "%\(query)%", -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var out: [(String, String, String?, String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func optText(_ i: Int32) -> String? {
                sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil
                    : String(cString: sqlite3_column_text(stmt, i))
            }
            out.append((String(cString: sqlite3_column_text(stmt, 0)),
                        String(cString: sqlite3_column_text(stmt, 1)),
                        optText(2), optText(3)))
        }
        return out
    }

    /// Block search for the manual flow (§7.2): distinct street + block label.
    public func searchBlocks(matching query: String, limit: Int = 60) -> [(street: String, blockLabel: String)] {
        let sql = """
            SELECT DISTINCT street, block_label FROM segments
            WHERE street LIKE ? ORDER BY street, block_label LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "%\(query)%", -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var out: [(String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((String(cString: sqlite3_column_text(stmt, 0)),
                        String(cString: sqlite3_column_text(stmt, 1))))
        }
        return out
    }

    public func holidays() -> HolidayCalendar {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT date, suspends FROM holidays", -1, &stmt, nil) == SQLITE_OK else {
            return .empty
        }
        defer { sqlite3_finalize(stmt) }
        var map: [String: Bool] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            map[String(cString: sqlite3_column_text(stmt, 0))] = sqlite3_column_int(stmt, 1) == 1
        }
        return HolidayCalendar(suspendsByDate: map)
    }

    // MARK: - Row decoding

    private func readSegments(_ stmt: OpaquePointer?) -> [Segment] {
        var out: [Segment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String { String(cString: sqlite3_column_text(stmt, i)) }
            func optText(_ i: Int32) -> String? {
                sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : text(i)
            }
            let id = text(0)
            guard let city = City(rawValue: text(1)) else { continue }
            var geometry: [GeoPoint] = []
            if let blob = sqlite3_column_blob(stmt, 10) {
                let bytes = Int(sqlite3_column_bytes(stmt, 10))
                let doubles = bytes / 8
                let buf = blob.bindMemory(to: Double.self, capacity: doubles)
                var i = 0
                while i + 1 < doubles {
                    geometry.append(GeoPoint(lat: buf[i], lon: buf[i + 1]))
                    i += 2
                }
            }
            out.append(Segment(id: id, city: city, street: text(2), blockLabel: text(3),
                               sideKey: text(4), doorParity: optText(5), doorRange: optText(6),
                               landmark: optText(7), landmarkHint: optText(8),
                               landmarkConfidence: optText(9), geometry: geometry,
                               rules: rules(forSegment: id)))
        }
        return out
    }

    private func rules(forSegment id: String) -> [ScheduleRule] {
        let sql = """
            SELECT weekday, weeks, from_hour, to_hour, holiday_enforced
            FROM rules WHERE segment_id = ? ORDER BY weekday, from_hour
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var out: [ScheduleRule] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var weeks: [Int]?
            if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                weeks = String(cString: sqlite3_column_text(stmt, 1))
                    .split(separator: ",").compactMap { Int($0) }
            }
            out.append(ScheduleRule(weekday: Int(sqlite3_column_int(stmt, 0)),
                                    weeks: weeks,
                                    fromHour: Int(sqlite3_column_int(stmt, 2)),
                                    toHour: Int(sqlite3_column_int(stmt, 3)),
                                    holidayEnforced: sqlite3_column_int(stmt, 4) == 1))
        }
        return out
    }
}
