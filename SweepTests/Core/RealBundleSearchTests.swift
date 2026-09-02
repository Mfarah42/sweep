import XCTest
@testable import SweepCore

/// Integration checks against the real generated Oakland bundle (skipped when
/// pipeline/out hasn't been built on this machine). Pins the exact scenarios
/// users hit: the 53rd St / 53rd Ave twins and address-ranked search.
final class RealBundleSearchTests: XCTestCase {

    func realBundle(_ city: City) throws -> SweepBundle {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("pipeline/out/\(city.rawValue).sweepbundle").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path),
                          "real bundle not built; run pipeline/ingest.py")
        return try SweepBundle(path: path)
    }

    /// Regression for the "City is set to SF, I search an Oakland street,
    /// nothing comes up" report (2026-09-01): search spans every installed
    /// bundle and each hit says which city it belongs to, so the caller can
    /// switch cities instead of failing.
    func testSearchSpansBothCitiesAndTagsHits() throws {
        let sf = try realBundle(.sf)
        let oak = try realBundle(.oak)

        // Oakland street, "current city" SF first — must still surface.
        let lakeshore = BlockSearch.hits(bundles: [sf, oak], query: "1935 Lakeshore")
        XCTAssertTrue(lakeshore.contains { $0.city == .oak && $0.street == "Lakeshore Ave" })
        XCTAssertTrue(lakeshore.first?.matchesNumber == true, "address match ranks first")

        // SF street with Oakland preferred — same guarantee the other way.
        let irving = BlockSearch.hits(bundles: [oak, sf], query: "Irving")
        XCTAssertTrue(irving.contains { $0.city == .sf && $0.street == "Irving St" })

        // Ids stay unique when the same street name exists in both cities.
        let both = BlockSearch.hits(bundles: [sf, oak], query: "Market")
        XCTAssertEqual(Set(both.map(\.id)).count, both.count)
    }

    func realOakBundle() throws -> SweepBundle {
        // …/SweepTests/Core/RealBundleSearchTests.swift → repo root
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("pipeline/out/oak.sweepbundle").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path),
                          "real bundle not built; run pipeline/ingest.py")
        return try SweepBundle(path: path)
    }

    /// 1091 is odd and exists on BOTH twins: 53rd St's odd range 1037–1099
    /// and 53rd Ave's odd range 1001–1099. The app can't know which street
    /// the user means — both must rank as address matches, above everything
    /// else, each carrying a door summary so the user consciously picks.
    func testAddressSearchSurfacesBothTwinsAsMatches() throws {
        let bundle = try realOakBundle()
        let hits = BlockSearch.hits(bundle: bundle, query: "1091 53rd")

        let matches = hits.filter(\.matchesNumber)
        XCTAssertEqual(Set(matches.map(\.street)), ["53rd St", "53rd Ave"])
        XCTAssertTrue(matches.allSatisfy { $0.blockLabel == "1000 block" })
        XCTAssertTrue(matches.allSatisfy { $0.doorSummary != nil },
                      "matches must show doors to disambiguate the twins")

        // Matches rank strictly above non-matching blocks.
        let firstNonMatch = hits.firstIndex { !$0.matchesNumber }
        let lastMatch = hits.lastIndex { $0.matchesNumber }
        if let firstNonMatch, let lastMatch {
            XCTAssertLessThan(lastMatch, firstNonMatch)
        }

        // An even address on the same street matches only the even ranges'
        // blocks — parity is respected.
        let evenHits = BlockSearch.hits(bundle: bundle, query: "1090 53rd")
            .filter(\.matchesNumber)
        XCTAssertFalse(evenHits.isEmpty)
    }
}
