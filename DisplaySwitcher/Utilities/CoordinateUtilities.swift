import CoreGraphics
import Foundation

/// Pure helpers for global-coordinate layout math. Fully unit-testable.
enum CoordinateUtilities {
    /// Bounding box enclosing all frames. Empty input yields `.zero`.
    static func boundingBox(of frames: [CGRect]) -> CGRect {
        guard let first = frames.first else { return .zero }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Translate every frame so the top-left of the bounding box sits at
    /// `target`. Preserves relative arrangement exactly, including negative
    /// coordinates, offsets, and mixed sizes.
    static func translatedToTopLeft(_ frames: [CGRect], target: CGPoint = .zero) -> [CGRect] {
        let box = boundingBox(of: frames)
        let dx = target.x - box.minX
        let dy = target.y - box.minY
        return frames.map { $0.offsetBy(dx: dx, dy: dy) }
    }

    /// Relative offsets of each frame from the bounding-box origin.
    /// Round-trips with `frames(fromOffsets:sizes:origin:)`.
    static func relativeOffsets(of frames: [CGRect]) -> [CGPoint] {
        let box = boundingBox(of: frames)
        return frames.map { CGPoint(x: $0.minX - box.minX, y: $0.minY - box.minY) }
    }

    /// Rebuild absolute frames from relative offsets plus an origin.
    static func frames(fromOffsets offsets: [CGPoint], sizes: [CGSize], origin: CGPoint) -> [CGRect] {
        zip(offsets, sizes).map { offset, size in
            CGRect(x: origin.x + offset.x, y: origin.y + offset.y,
                   width: size.width, height: size.height)
        }
    }

    /// True when no two frames overlap with positive area.
    /// Touching edges are legal in macOS arrangements; zero-size frames
    /// (e.g. a display whose size is not yet known) are ignored defensively.
    static func hasOverlaps(_ frames: [CGRect]) -> Bool {
        let valid = frames.filter { $0.width > 0.5 && $0.height > 0.5 }
        for i in valid.indices {
            for j in valid.indices where j > i {
                let intersection = valid[i].intersection(valid[j])
                if intersection.width > 0.5 && intersection.height > 0.5 {
                    return true
                }
            }
        }
        return false
    }

    /// Scale a layout to fit inside `target` while preserving aspect/positions.
    static func scaledToFit(_ frames: [CGRect], target: CGSize) -> [CGRect] {
        let box = boundingBox(of: frames)
        guard box.width > 0, box.height > 0,
              target.width > 0, target.height > 0 else { return frames }
        let s = min(target.width / box.width, target.height / box.height)
        return frames.map { frame in
            CGRect(x: (frame.minX - box.minX) * s,
                   y: (frame.minY - box.minY) * s,
                   width: frame.width * s,
                   height: frame.height * s)
        }
    }
}
