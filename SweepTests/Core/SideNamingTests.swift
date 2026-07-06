import XCTest
@testable import SweepCore

/// Side naming rules, born from user feedback at 3850 Maybelle Ave:
/// "Airport side" only means "the side facing the airport direction," which
/// nobody can feel standing on the block. Door parity is the one instantly
/// verifiable cue, so it leads whenever the data has it.
final class SideNamingTests: XCTestCase {

    func testParityLeadsForAutoNamedSides() {
        // Geo-derived name (no hint) → parity title, no backup.
        XCTAssertEqual(SweepFormat.sideTitle(parity: "odd", landmark: "Airport side",
                                             confidence: "auto"),
                       "Odd side")
        XCTAssertNil(SweepFormat.sideBackup(parity: "odd", landmark: "Airport side",
                                            landmarkHint: nil, confidence: "auto"))

        // Arterial name → parity title, visible-street hint kept as backup.
        XCTAssertEqual(SweepFormat.sideTitle(parity: "even", landmark: "MacArthur side",
                                             confidence: "auto"),
                       "Even side")
        XCTAssertEqual(SweepFormat.sideBackup(parity: "even", landmark: "MacArthur side",
                                              landmarkHint: "toward MacArthur Blvd",
                                              confidence: "auto"),
                       "toward MacArthur Blvd")
    }

    func testEditorialNamesKeepTheLead() {
        XCTAssertEqual(SweepFormat.sideTitle(parity: "even", landmark: "Lake side",
                                             confidence: "editorial"),
                       "Lake side")
        XCTAssertEqual(SweepFormat.sideBackup(parity: "even", landmark: "Lake side",
                                              landmarkHint: "theater marquee up the street",
                                              confidence: "editorial"),
                       "theater marquee up the street")
    }

    func testParitylessSidesFallBackToLandmark() {
        // SF has no door ranges — landmark stays the title there.
        XCTAssertEqual(SweepFormat.sideTitle(parity: nil, landmark: "Ocean side",
                                             confidence: "auto"),
                       "Ocean side")
        XCTAssertEqual(SweepFormat.sideTitle(parity: "mixed", landmark: "Geary side",
                                             confidence: "auto"),
                       "Geary side")
    }

    func testDisplaySideNameForRunningCopy() {
        func segment(parity: String?, landmark: String?, confidence: String?) -> SweepBundle.Segment {
            SweepBundle.Segment(id: "x", city: .oak, street: "Maybelle Ave",
                                blockLabel: "3700 block", sideKey: "a",
                                doorParity: parity, doorRange: nil,
                                landmark: landmark, landmarkHint: nil,
                                landmarkConfidence: confidence,
                                geometry: [], rules: [])
        }
        // "Maybelle Ave · even side · sweep in …"
        XCTAssertEqual(segment(parity: "even", landmark: "Airport side",
                               confidence: "auto").displaySideName, "Even side")
        XCTAssertEqual(segment(parity: nil, landmark: "Ocean side",
                               confidence: "auto").displaySideName, "Ocean side")
        XCTAssertEqual(segment(parity: "even", landmark: "Lake side",
                               confidence: "editorial").displaySideName, "Lake side")
    }
}
