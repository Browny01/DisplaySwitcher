import XCTest

/// Edge-case matching tests: dual same-model monitors, portrait, ambiguity.
final class DisplayMatcherEdgeCaseTests: XCTestCase {
    func testDualSameModelDifferentSerials() {
        let saved1 = TestFixtures.display(id: 1, serial: 1001, name: "LG")
        let saved2 = TestFixtures.display(id: 2, serial: 1002, name: "LG")
        let preset = TestFixtures.preset(displays: [saved1, saved2])

        var conn1 = saved1; conn1.displayID = 41
        var conn2 = saved2; conn2.displayID = 42
        let matches = DisplayMatcher.match(preset: preset, against: [conn1, conn2])
        XCTAssertTrue(DisplayMatcher.isCompleteMatch(matches, preset: preset))
        XCTAssertEqual(Set(matches.map { $0.display.fingerprint.serialNumber }), Set([1001, 1002]))
    }

    func testTwoIdenticalDisplaysCannotReuseSame() {
        let saved1 = TestFixtures.display(id: 1, serial: 1111, name: "Same")
        let saved2 = TestFixtures.display(id: 2, serial: 1111, name: "Same")
        let preset = TestFixtures.preset(displays: [saved1, saved2])
        // Only one physical display available — should match once at most.
        var conn = saved1; conn.displayID = 99
        let matches = DisplayMatcher.match(preset: preset, against: [conn])
        XCTAssertLessThanOrEqual(matches.count, 1)
    }

    func testPortraitDisplayMatchesByVendorProduct() {
        var saved = TestFixtures.display(id: 1, serial: 5555)
        saved.pixelSize = DisplaySize(width: 1080, height: 1920)
        saved.pointSize = DisplaySize(width: 1080, height: 1920)
        saved.rotationDegrees = 90
        let preset = TestFixtures.preset(displays: [saved])

        var conn = saved; conn.displayID = 77
        let matches = DisplayMatcher.match(preset: preset, against: [conn])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].score, 1.0, accuracy: 0.001)
    }

    func testSetupSignatureHandlesEmpty() {
        XCTAssertEqual(DisplayMatcher.setupSignature(of: []), "")
    }

    func testExactMatchScoreValue() {
        let saved = TestFixtures.display(id: 1, serial: 9999, name: "Dell U2723QE")
        var conn = saved; conn.displayID = 55
        let score = DisplayMatcher.score(preset: PresetDisplayEntry(from: saved), candidate: conn)
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testBuiltInVsExternalScoreIsZero() {
        let saved = TestFixtures.display(id: 1, isBuiltIn: true)
        let candidate = TestFixtures.display(id: 2, isBuiltIn: false)
        let score = DisplayMatcher.score(preset: PresetDisplayEntry(from: saved), candidate: candidate)
        XCTAssertEqual(score, 0.0)
    }

    func testZeroVendorScoreIsLow() {
        var saved = TestFixtures.display(id: 1, serial: 123)
        saved.fingerprint.vendorID = 0
        saved.fingerprint.productID = 0
        var candidate = TestFixtures.display(id: 2, serial: 456)
        candidate.fingerprint.vendorID = 0
        candidate.fingerprint.productID = 0
        let score = DisplayMatcher.score(preset: PresetDisplayEntry(from: saved), candidate: candidate)
        // No vendor/product/serial agreement: should be low.
        XCTAssertLessThan(score, 0.5)
    }
}
