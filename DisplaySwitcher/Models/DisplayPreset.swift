import Foundation

/// One display entry stored inside a preset.
///
/// Positions are stored exactly as captured in global display coordinates.
/// At apply time the whole layout is translated so the relative arrangement
/// is preserved even if macOS reports a different global origin.
struct PresetDisplayEntry: Codable, Hashable, Sendable {
    var fingerprint: DisplayFingerprint
    /// Display name at capture time, for UI messaging only (never used to match).
    var capturedName: String
    var origin: DisplayPoint
    var pixelSize: DisplaySize
    var pointSize: DisplaySize
    var refreshRateHz: Double
    var rotationDegrees: Double
    var scaleFactor: Double
    var wasMain: Bool
    /// IODisplayModeID of the active mode at capture time, if known.
    var displayModeID: Int32?

    init(from display: DisplayInfo, modeID: Int32? = nil) {
        self.fingerprint = display.fingerprint
        self.capturedName = display.name
        self.origin = display.origin
        self.pixelSize = display.pixelSize
        self.pointSize = display.pointSize
        self.refreshRateHz = display.refreshRateHz
        self.rotationDegrees = display.rotationDegrees
        self.scaleFactor = display.scaleFactor
        self.wasMain = display.isMain
        self.displayModeID = modeID
    }
}

/// A saved named arrangement of displays.
struct DisplayPreset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int
    var displays: [PresetDisplayEntry]
    /// Keyboard shortcut bound to this preset, if any.
    var shortcut: KeyboardShortcut?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        displays: [PresetDisplayEntry],
        shortcut: KeyboardShortcut? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.schemaVersion = AppConstants.presetsSchemaVersion
        self.displays = displays
        self.shortcut = shortcut
        self.notes = notes
    }

    var displayCount: Int { displays.count }

    /// Fingerprint of the display that was main when the preset was saved.
    var mainDisplayFingerprint: DisplayFingerprint? {
        displays.first(where: { $0.wasMain })?.fingerprint
    }

    /// Normalised bounding box of the saved layout (for previews/validation).
    var boundingBox: CGRect {
        CoordinateUtilities.boundingBox(of: displays.map { entry in
            CGRect(x: entry.origin.x, y: entry.origin.y,
                   width: entry.pointSize.width, height: entry.pointSize.height)
        })
    }
}

/// Top-level on-disk container so the format can evolve safely.
struct PresetStoreFile: Codable, Sendable {
    var schemaVersion: Int
    var presets: [DisplayPreset]

    init(presets: [DisplayPreset] = [],
         schemaVersion: Int = AppConstants.presetsSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.presets = presets
    }
}
