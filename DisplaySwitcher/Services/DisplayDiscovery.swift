import AppKit
import CoreGraphics
import Foundation

/// Abstraction over display enumeration so matching/validation logic can be
/// unit-tested with mocked displays without touching Core Graphics.
protocol DisplayDiscovering: Sendable {
    func currentDisplays() -> [DisplayInfo]
    func displayModeID(for displayID: CGDirectDisplayID) -> Int32?
}

/// Live implementation backed by Core Graphics + NSScreen.
///
/// Currently used stable metadata: vendor/product/serial numbers,
/// physical size, built-in flag, and display name. macOS exposes no public
/// persistent display UUID, so identity is a fingerprint of these fields —
/// see `DisplayMatcher` for the scoring strategy.
final class CoreGraphicsDisplayDiscovery: DisplayDiscovering, Sendable {
    func currentDisplays() -> [DisplayInfo] {
        var onlineCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &onlineCount) == .success,
              onlineCount > 0 else {
            AppLogger.discovery.error("No online displays reported.")
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(onlineCount))
        var fetched: UInt32 = 0
        guard CGGetOnlineDisplayList(onlineCount, &ids, &fetched) == .success else {
            AppLogger.discovery.error("CGGetOnlineDisplayList fetch failed.")
            return []
        }
        let screensByID = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return nil
                }
                return (CGDirectDisplayID(number.uint32Value), screen)
            }
        )
        let mainID = CGMainDisplayID()
        let infos = ids.prefix(Int(fetched)).compactMap { id -> DisplayInfo? in
            guard CGDisplayIsOnline(id) != 0 else { return nil }
            return self.describe(displayID: id, mainID: mainID, screen: screensByID[id])
        }
        AppLogger.discovery.debug("Detected \(infos.count) online displays.")
        return infos
    }

    func displayModeID(for displayID: CGDirectDisplayID) -> Int32? {
        CGDisplayCopyDisplayMode(displayID)?.ioDisplayModeID
    }

    // MARK: - Private

    private func describe(displayID: CGDirectDisplayID,
                          mainID: CGDirectDisplayID,
                          screen: NSScreen?) -> DisplayInfo {
        let bounds = CGDisplayBounds(displayID)
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let mm = CGDisplayScreenSize(displayID)
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let name = screen?.localizedName
            ?? (isBuiltIn ? "Built-in Display" : "External Display")

        let pixelW = Int(CGDisplayPixelsWide(displayID))
        let pixelH = Int(CGDisplayPixelsHigh(displayID))
        let scale: Double = {
            guard bounds.width > 1 else { return 1 }
            return Double(pixelW) / Double(bounds.width)
        }()

        var refreshHz = 0.0
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            refreshHz = mode.refreshRate
        }

        let fingerprint = DisplayFingerprint(
            vendorID: vendor,
            productID: model,
            serialNumber: serial,
            sizeMillimeters: DisplaySize(width: Int(mm.width.rounded()),
                                        height: Int(mm.height.rounded())),
            isBuiltIn: isBuiltIn,
            normalizedName: name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )

        return DisplayInfo(
            displayID: displayID,
            fingerprint: fingerprint,
            name: name,
            pixelSize: DisplaySize(width: pixelW, height: pixelH),
            pointSize: DisplaySize(bounds.size),
            refreshRateHz: refreshHz,
            rotationDegrees: CGDisplayRotation(displayID),
            scaleFactor: screen.map { Double($0.backingScaleFactor) } ?? scale,
            isBuiltIn: isBuiltIn,
            isMain: displayID == mainID,
            isActive: CGDisplayIsActive(displayID) != 0,
            isOnline: true,
            isMirrored: CGDisplayIsInMirrorSet(displayID) != 0,
            origin: DisplayPoint(bounds.origin),
            unitNumber: CGDisplayUnitNumber(displayID)
        )
    }
}

/// In-memory discovery for tests and previews.
struct MockDisplayDiscovery: DisplayDiscovering, Sendable {
    var displays: [DisplayInfo]
    func currentDisplays() -> [DisplayInfo] { displays }
    func displayModeID(for displayID: CGDirectDisplayID) -> Int32? { nil }
}
