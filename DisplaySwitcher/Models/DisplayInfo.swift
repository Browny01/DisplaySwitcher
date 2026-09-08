import CoreGraphics
import Foundation

/// Point in macOS global display coordinates. Codable so presets can persist it.
struct DisplayPoint: Codable, Hashable, Sendable {
    var x: Int
    var y: Int

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    init(_ cgPoint: CGPoint) {
        self.x = Int(cgPoint.x.rounded())
        self.y = Int(cgPoint.y.rounded())
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Size in points/pixels. Codable so presets can persist it.
struct DisplaySize: Codable, Hashable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init(_ cgSize: CGSize) {
        self.width = Int(cgSize.width.rounded())
        self.height = Int(cgSize.height.rounded())
    }

    var cgSize: CGSize { CGSize(width: width, height: height) }
}

/// Stable characteristics of a physical display used for fingerprinting.
///
/// `CGDirectDisplayID` values can change between sessions, so matching must
/// rely on the stable metadata captured here instead of the numeric ID.
struct DisplayFingerprint: Codable, Hashable, Sendable {
    /// Vendor ID from `CGDisplayVendorNumber` (EDID-derived where available).
    var vendorID: UInt32
    /// Product/model ID from `CGDisplayModelNumber`.
    var productID: UInt32
    /// Serial number from `CGDisplaySerialNumber` (often 0 for modern displays).
    var serialNumber: UInt32
    /// Physical size in millimetres from `CGDisplayScreenSize`.
    var sizeMillimeters: DisplaySize
    /// Whether this is the built-in panel (e.g. MacBook display).
    var isBuiltIn: Bool
    /// Human-readable name from `NSScreen.localizedName`, lowercased for matching.
    var normalizedName: String

    /// A short human-readable key useful for logs and diagnostics.
    var diagnosticKey: String {
        if isBuiltIn { return "built-in" }
        return String(format: "v%04x-p%04x-s%08x", vendorID, productID, serialNumber)
    }
}

/// A snapshot of one currently connected display.
struct DisplayInfo: Identifiable, Codable, Hashable, Sendable {
    /// The live `CGDirectDisplayID`. Never persisted for matching purposes;
    /// it is only valid for the current session.
    var displayID: UInt32
    var fingerprint: DisplayFingerprint
    /// Friendly name shown in the UI (e.g. "LG UltraGear", "Built-in Display").
    var name: String
    /// Pixel dimensions of the current display mode.
    var pixelSize: DisplaySize
    /// Point dimensions of the current display mode (resolution / scale).
    var pointSize: DisplaySize
    var refreshRateHz: Double
    var rotationDegrees: Double
    var scaleFactor: Double
    var isBuiltIn: Bool
    var isMain: Bool
    var isActive: Bool
    var isOnline: Bool
    var isMirrored: Bool
    /// Current origin in global display coordinates.
    var origin: DisplayPoint
    /// Unit number from `CGDisplayUnitNumber`.
    var unitNumber: UInt32

    var id: UInt32 { displayID }

    /// Frame in global coordinates, derived from origin + point size.
    var frame: CGRect {
        CGRect(x: origin.x, y: origin.y, width: pointSize.width, height: pointSize.height)
    }

    var friendlyResolution: String {
        "\(pixelSize.width) × \(pixelSize.height)"
    }
}
