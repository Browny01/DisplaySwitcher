import Foundation

/// Shared fixtures for display/matching tests. No real hardware involved.
enum TestFixtures {
    static func fingerprint(vendor: UInt32 = 0x0610,
                            product: UInt32 = 0x9162,
                            serial: UInt32 = 12345,
                            builtIn: Bool = false,
                            name: String = "lg ultragear") -> DisplayFingerprint {
        DisplayFingerprint(vendorID: vendor,
                           productID: product,
                           serialNumber: serial,
                           sizeMillimeters: DisplaySize(width: 600, height: 340),
                           isBuiltIn: builtIn,
                           normalizedName: name)
    }

    static func display(id: UInt32 = 1,
                        serial: UInt32 = 12345,
                        name: String = "LG UltraGear",
                        origin: DisplayPoint = DisplayPoint(x: 0, y: 0),
                        pointSize: DisplaySize = DisplaySize(width: 2560, height: 1440),
                        isMain: Bool = true,
                        isBuiltIn: Bool = false) -> DisplayInfo {
        DisplayInfo(
            displayID: id,
            fingerprint: fingerprint(product: UInt32(0x9162 + id),
                                     serial: serial + id,
                                     builtIn: isBuiltIn,
                                     name: name.lowercased()),
            name: name,
            pixelSize: pointSize,
            pointSize: pointSize,
            refreshRateHz: 144,
            rotationDegrees: 0,
            scaleFactor: 1,
            isBuiltIn: isBuiltIn,
            isMain: isMain,
            isActive: true,
            isOnline: true,
            isMirrored: false,
            origin: origin,
            unitNumber: id)
    }

    static func builtInDisplay(id: UInt32 = 7) -> DisplayInfo {
        display(id: id, serial: 0, name: "Built-in Display",
                origin: DisplayPoint(x: 2560, y: 0),
                pointSize: DisplaySize(width: 1512, height: 982),
                isMain: false, isBuiltIn: true)
    }

    static func entry(from display: DisplayInfo, wasMain: Bool? = nil) -> PresetDisplayEntry {
        var entry = PresetDisplayEntry(from: display)
        if let wasMain { entry.wasMain = wasMain }
        return entry
    }

    static func preset(name: String = "Desk", displays: [DisplayInfo]) -> DisplayPreset {
        DisplayPreset(name: name, displays: displays.map { PresetDisplayEntry(from: $0) })
    }
}
