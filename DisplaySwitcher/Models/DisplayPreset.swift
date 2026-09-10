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
    /// When true, this preset is recalled automatically whenever a display
    /// setup matching its saved displays connects.
    var autoApplyOnSetup: Bool

    init(
        id: UUID = UUID(),
        name: String,
        displays: [PresetDisplayEntry],
        shortcut: KeyboardShortcut? = nil,
        notes: String? = nil,
        autoApplyOnSetup: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.schemaVersion = AppConstants.presetsSchemaVersion
        self.displays = displays
        self.shortcut = shortcut
        self.notes = notes
        self.autoApplyOnSetup = autoApplyOnSetup
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

    // MARK: - Codable (forward-compatible)

    /// Older preset files predate `autoApplyOnSetup`; decode it as false.
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, schemaVersion, displays, shortcut, notes,
             autoApplyOnSetup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        displays = try c.decode([PresetDisplayEntry].self, forKey: .displays)
        shortcut = try c.decodeIfPresent(KeyboardShortcut.self, forKey: .shortcut)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        autoApplyOnSetup = try c.decodeIfPresent(Bool.self, forKey: .autoApplyOnSetup) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(displays, forKey: .displays)
        try c.encodeIfPresent(shortcut, forKey: .shortcut)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(autoApplyOnSetup, forKey: .autoApplyOnSetup)
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
