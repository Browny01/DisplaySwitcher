import XCTest

final class DisplayMatcherTests: XCTestCase {
    func testExactMatchScoresOne() {
        let display = TestFixtures.display()
        let preset = TestFixtures.preset(displays: [display])
        let matches = DisplayMatcher.match(preset: preset, against: [display])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].score, 1.0, accuracy: 0.001)
    }

    func testDisplayIDChangeDoesNotAffectMatching() {
        let saved = TestFixtures.display(id: 2)
        let preset = TestFixtures.preset(displays: [saved])
        // Same physical display re-enumerated with a different session ID.
        var reconnected = saved
        reconnected.displayID = 999_001
        let matches = DisplayMatcher.match(preset: preset, against: [reconnected])
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(DisplayMatcher.isCompleteMatch(matches, preset: preset))
    }

    func testMissingDisplayLeavesEntryUnmatched() {
        let d1 = TestFixtures.display(id: 1, serial: 111)
        let d2 = TestFixtures.display(id: 2, serial: 222, name: "Dell U2723QE")
        let preset = TestFixtures.preset(displays: [d1, d2])
        let matches = DisplayMatcher.match(preset: preset, against: [d1])
        XCTAssertEqual(matches.count, 1)
        XCTAssertFalse(DisplayMatcher.isCompleteMatch(matches, preset: preset))
    }

    func testBuiltInNeverMatchesExternal() {
        let external = TestFixtures.display()
        let preset = TestFixtures.preset(displays: [external])
        let matches = DisplayMatcher.match(preset: preset, against: [TestFixtures.builtInDisplay()])
        XCTAssertTrue(matches.isEmpty)
    }

    func testEachPhysicalDisplayUsedAtMostOnce() {
        let d1 = TestFixtures.display(id: 1, serial: 111)
        let d2 = TestFixtures.display(id: 2, serial: 111, name: "Same Serial Twin")
        // Preset saved with two identical-fingerprint entries is ambiguous;
        // matcher must not assign both to one display.
        var twin = d1
        twin.displayID = 2
        let preset = TestFixtures.preset(displays: [d1, d1])
        let matches = DisplayMatcher.match(preset: preset, against: [twin])
        XCTAssertLessThanOrEqual(matches.count, 1)
        _ = d2
    }

    func testSetupSignatureIsOrderIndependent() {
        let a = TestFixtures.display(id: 1, serial: 111)
        let b = TestFixtures.builtInDisplay()
        XCTAssertEqual(DisplayMatcher.setupSignature(of: [a, b]),
                       DisplayMatcher.setupSignature(of: [b, a]))
    }

    func testRenamedDisplayStillMatches() {
        let saved = TestFixtures.display()
        let preset = TestFixtures.preset(displays: [saved])
        var renamed = saved
        renamed.name = "Totally Different Name"
        renamed.fingerprint.normalizedName = "totally different name"
        let matches = DisplayMatcher.match(preset: preset, against: [renamed])
        XCTAssertEqual(matches.count, 1, "Name is only a tiebreaker; hardware IDs must still match.")
    }
}
