import CoreGraphics
import XCTest

final class CoordinateUtilitiesTests: XCTestCase {
    func testBoundingBoxHandlesNegativeCoordinates() {
        let frames = [CGRect(x: -1920, y: -300, width: 1920, height: 1080),
                      CGRect(x: 0, y: 0, width: 2560, height: 1440)]
        let box = CoordinateUtilities.boundingBox(of: frames)
        XCTAssertEqual(box, CGRect(x: -1920, y: -300, width: 4480, height: 1740))
    }

    func testRelativeOffsetsRoundTrip() {
        let frames = [CGRect(x: 0, y: -500, width: 1920, height: 1080),   // above
                      CGRect(x: 100, y: 580, width: 2560, height: 1440),  // below, offset
                      CGRect(x: -1512, y: 200, width: 1512, height: 982)] // left portrait-ish
        let offsets = CoordinateUtilities.relativeOffsets(of: frames)
        let rebuilt = CoordinateUtilities.frames(
            fromOffsets: offsets,
            sizes: frames.map { $0.size },
            origin: CoordinateUtilities.boundingBox(of: frames).origin)
        XCTAssertEqual(rebuilt, frames)
    }

    func testTranslatedLayoutPreservesRelativeArrangement() {
        let frames = [CGRect(x: 5000, y: 5000, width: 1920, height: 1080),
                      CGRect(x: 5000, y: 6080, width: 1920, height: 1080)]
        let moved = CoordinateUtilities.translatedToTopLeft(frames)
        XCTAssertEqual(moved[0].origin, .zero)
        XCTAssertEqual(moved[1].origin, CGPoint(x: 0, y: 1080))
    }

    func testTouchingEdgesAreNotOverlaps() {
        let side = [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                    CGRect(x: 1920, y: 0, width: 1920, height: 1080)]
        XCTAssertFalse(CoordinateUtilities.hasOverlaps(side))
    }

    func testRealOverlapsDetected() {
        let overlap = [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                       CGRect(x: 100, y: 100, width: 1920, height: 1080)]
        XCTAssertTrue(CoordinateUtilities.hasOverlaps(overlap))
    }

    func testScaledToFitPreservesArrangement() {
        let frames = [CGRect(x: 0, y: 0, width: 2560, height: 1440),
                      CGRect(x: 2560, y: 200, width: 1512, height: 982)]
        let fitted = CoordinateUtilities.scaledToFit(frames, target: CGSize(width: 200, height: 100))
        let box = CoordinateUtilities.boundingBox(of: fitted)
        XCTAssertLessThanOrEqual(box.width, 200.001)
        XCTAssertLessThanOrEqual(box.height, 100.001)
        // Second display keeps its vertical offset relative to the first.
        XCTAssertGreaterThan(fitted[1].minY, fitted[0].minY)
    }

    func testEmptyInputYieldsZeroBox() {
        XCTAssertEqual(CoordinateUtilities.boundingBox(of: []), .zero)
    }
}
