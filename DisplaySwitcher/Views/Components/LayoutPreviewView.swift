import SwiftUI

/// Proportional monitor-arrangement diagram that works for any number of
/// screens, sizes, offsets, and negative coordinates.
struct LayoutPreviewView: View {
    var frames: [CGRect]
    var mainFrame: CGRect?
    var height: CGFloat = 110

    var body: some View {
        GeometryReader { geometry in
            let fitted = CoordinateUtilities.scaledToFit(
                frames, target: CGSize(width: geometry.size.width, height: geometry.size.height))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                ForEach(Array(fitted.enumerated()), id: \.offset) { _, frame in
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor, lineWidth: isMain(frame, in: fitted) ? 2 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: .controlAccentColor).opacity(0.15)))
                        .frame(width: max(frame.width, 8), height: max(frame.height, 8))
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Monitor arrangement preview")
    }

    private func isMain(_ frame: CGRect, in fitted: [CGRect]) -> Bool {
        // The preview marks the largest display when the main one is unknown.
        guard fitted.count > 1 else { return true }
        if let mainFrame {
            let box = CoordinateUtilities.boundingBox(of: frames)
            let fittedBox = CoordinateUtilities.boundingBox(of: fitted)
            let s = fittedBox.width / max(box.width, 1)
            let expected = CGRect(x: (mainFrame.minX - box.minX) * s,
                                  y: (mainFrame.minY - box.minY) * s,
                                  width: mainFrame.width * s,
                                  height: mainFrame.height * s)
            return abs(frame.minX - expected.minX) < 1 && abs(frame.minY - expected.minY) < 1
        }
        return frame == fitted.max(by: { $0.width * $0.height < $1.width * $1.height })
    }
}

/// Convenience constructors from live or saved data.
extension LayoutPreviewView {
    init(displays: [DisplayInfo], height: CGFloat = 110) {
        self.frames = displays.map { $0.frame }
        self.mainFrame = displays.first(where: { $0.isMain })?.frame
        self.height = height
    }

    init(preset: DisplayPreset, height: CGFloat = 110) {
        self.frames = preset.displays.map {
            CGRect(x: $0.origin.x, y: $0.origin.y,
                   width: $0.pointSize.width, height: $0.pointSize.height)
        }
        if let main = preset.displays.first(where: { $0.wasMain }) {
            self.mainFrame = CGRect(x: main.origin.x, y: main.origin.y,
                                    width: main.pointSize.width, height: main.pointSize.height)
        } else {
            self.mainFrame = nil
        }
        self.height = height
    }
}
