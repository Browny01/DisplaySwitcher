import CoreGraphics
import XCTest

/// Layout planning/validation without touching real display hardware.
final class LayoutValidationTests: XCTestCase {
    private func service(with displays: [DisplayInfo]) -> DisplayConfigurationService {
        DisplayConfigurationService(discovery: MockDisplayDiscovery(displays: displays))
    }

    func testEmptyPresetThrows() {
        let service = service(with: [TestFixtures.display()])
        let preset = DisplayPreset(name: "Empty", displays: [])
        XCTAssertThrowsError(try service.plan(preset: preset)) { error in
            XCTAssertEqual(error as? DisplayConfigurationError, .emptyPreset)
        }
    }

    func testNoDisplaysThrows() {
        let service = service(with: [])
        let preset = TestFixtures.preset(displays: [TestFixtures.display()])
        XCTAssertThrowsError(try service.plan(preset: preset)) { error in
            XCTAssertEqual(error as? DisplayConfigurationError, .noDisplaysDetected)
        }
    }

    func testMissingDisplayReportsName() {
        let connected = [TestFixtures.display()]
        let absent = TestFixtures.display(id: 2, serial: 999, name: "Unplugged Monitor")
        let preset = TestFixtures.preset(displays: connected + [absent])
        let service = service(with: connected)
        XCTAssertThrowsError(try service.plan(preset: preset)) { error in
            if case .incompleteMatch(let missing) = error as? DisplayConfigurationError {
                XCTAssertTrue(missing.contains("Unplugged Monitor"))
            } else {
                XCTFail("Expected incompleteMatch, got \(error)")
            }
        }
    }

    func testValidPlanPreservesRelativeOffsets() throws {
        // Saved: main at (0,0) 2560 wide, second to the right at x=2560.
        let main = TestFixtures.display(id: 1, origin: DisplayPoint(x: 0, y: 0),
                                        pointSize: DisplaySize(width: 2560, height: 1440),
                                        isMain: true)
        let right = TestFixtures.display(id: 2, serial: 777, name: "Right",
                                         origin: DisplayPoint(x: 2560, y: -200),
                                         pointSize: DisplaySize(width: 1920, height: 1080),
                                         isMain: false)
        let preset = TestFixtures.preset(displays: [main, right])

        // macOS currently has them stacked differently; main stays put.
        var movedMain = main
        movedMain.displayID = 41
        var movedRight = right
        movedRight.displayID = 42
        movedRight.origin = DisplayPoint(x: 0, y: 1440)
        let service = service(with: [movedMain, movedRight])

        let plan = try service.plan(preset: preset)
        XCTAssertEqual(plan.moves.count, 2)
        let mainMove = plan.moves.first(where: { $0.displayID == 41 })!
        let rightMove = plan.moves.first(where: { $0.displayID == 42 })!
        XCTAssertEqual(mainMove.targetOrigin, movedMain.origin.cgPoint)
        XCTAssertEqual(rightMove.targetOrigin.x, mainMove.targetOrigin.x + 2560)
        XCTAssertEqual(rightMove.targetOrigin.y, mainMove.targetOrigin.y - 200)
    }

    func testPlanCoversThreeMonitorsAndPortrait() throws {
        let top = TestFixtures.display(id: 1, origin: DisplayPoint(x: 0, y: -1080),
                                       pointSize: DisplaySize(width: 1920, height: 1080),
                                       isMain: false)
        let main = TestFixtures.display(id: 2, serial: 555, name: "Main",
                                        origin: DisplayPoint(x: 0, y: 0),
                                        pointSize: DisplaySize(width: 2560, height: 1440),
                                        isMain: true)
        let portrait = TestFixtures.display(id: 3, serial: 888, name: "Portrait",
                                            origin: DisplayPoint(x: 2560, y: -340),
                                            pointSize: DisplaySize(width: 1080, height: 1920),
                                            isMain: false)
        let preset = TestFixtures.preset(displays: [top, main, portrait])
        let service = service(with: [top, main, portrait])
        let plan = try service.plan(preset: preset)
        XCTAssertEqual(plan.moves.count, 3)
        XCTAssertFalse(plan.rollbackOrigins.isEmpty)
    }
}
