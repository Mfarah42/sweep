import XCTest
@testable import SweepCore

/// Address-aware search: born from the 53rd St / 53rd Ave mixup — Oakland has
/// numbered Streets AND Avenues, both with overlapping house numbers.
final class BlockSearchTests: XCTestCase {

    func testParseAddressQuery() {
        var p = BlockSearch.parse("1091 53rd st")
        XCTAssertEqual(p.number, 1091)
        XCTAssertEqual(p.streetQuery, "53rd st")

        p = BlockSearch.parse("Maybelle")
        XCTAssertNil(p.number)
        XCTAssertEqual(p.streetQuery, "Maybelle")

        // A bare number has no street part — treated as a street query.
        p = BlockSearch.parse("1091")
        XCTAssertNil(p.number)
        XCTAssertEqual(p.streetQuery, "1091")

        // Ordinal street names: "9th" is not Int-parseable, stays a street.
        p = BlockSearch.parse("9th Ave")
        XCTAssertNil(p.number)
        XCTAssertEqual(p.streetQuery, "9th Ave")
    }

    func testOrdinalStreetNamesAreNotHouseNumbers() {
        let p = BlockSearch.parse("53rd st")
        XCTAssertNil(p.number, "'53rd' must not parse as house number 53")
        XCTAssertEqual(p.streetQuery, "53rd st")
    }

    func testRangeAndParity() {
        XCTAssertEqual(BlockSearch.parseRange("1037–1099")?.0, 1037)
        XCTAssertEqual(BlockSearch.parseRange("1037–1099")?.1, 1099)
        XCTAssertNil(BlockSearch.parseRange(nil))
        XCTAssertTrue(BlockSearch.parityMatches(1091, parity: "odd"))
        XCTAssertFalse(BlockSearch.parityMatches(1091, parity: "even"))
        XCTAssertTrue(BlockSearch.parityMatches(1091, parity: nil))
    }

    /// End-to-end against the Oakland fixture bundle: the hit list carries
    /// door summaries and containing blocks rank first.
    func testHitsAgainstFixtureBundle() throws {
        let url = Bundle.module.url(forResource: "oak", withExtension: "sweepbundle",
                                    subdirectory: "Fixtures")
        let bundle = try SweepBundle(path: try XCTUnwrap(url).path)

        // Pick any block with a door range from the fixture and search for an
        // address inside it.
        let rows = bundle.blockRows(streetMatching: "")
        let target = try XCTUnwrap(rows.first { $0.doorRange != nil })
        let span = try XCTUnwrap(BlockSearch.parseRange(target.doorRange))
        var number = (span.0 + span.1) / 2
        if !BlockSearch.parityMatches(number, parity: target.doorParity) {
            number += 1
        }
        number = min(max(number, span.0), span.1)

        let hits = BlockSearch.hits(bundle: bundle, query: "\(number) \(target.street)")
        let first = try XCTUnwrap(hits.first)
        XCTAssertTrue(first.matchesNumber, "containing block must rank first")
        XCTAssertEqual(first.street, target.street)
        XCTAssertNotNil(first.doorSummary)
    }
}
