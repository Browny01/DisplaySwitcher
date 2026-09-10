import Foundation

/// Errors surfaced to the CLI and Shortcuts.app.
enum AutomationEngineError: LocalizedError {
    case presetNotFound(String)
    case noDisplays
    case noPresets
    case applyFailed(String?)
    case verificationFailed
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .presetNotFound(let name):
            return "Preset '\(name)' not found."
        case .noDisplays:
            return "No connected displays were detected."
        case .noPresets:
            return "No presets saved yet. Run: DisplaySwitcher save \"My Layout\""
        case .applyFailed(let detail):
            return "Could not apply preset\(detail.map { " (\($0))" } ?? "")."
        case .verificationFailed:
            return "The layout may not have landed exactly as saved."
        case .usage(let message):
            return message
        }
    }
}

/// Synchronous, headless operations shared by the CLI, Command-Shortcuts
/// hookups, and App Intents. Runs on the main actor because the underlying
/// managers are `@MainActor`; the CLI invokes it via
/// `MainActor.assumeIsolated` (both run on the main thread at this point).
@MainActor
enum AutomationEngine {
    // MARK: - Settings

    static func loadSettings() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: AppConstants.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return decoded
        }
        return .default
    }

    private static func persist(settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: AppConstants.settingsKey)
        }
    }

    // MARK: - Presets

    static func presets() -> [DisplayPreset] {
        PresetManager().presets
    }

    /// Save the current arrangement as a named preset.
    @discardableResult
    static func save(named name: String) throws -> DisplayPreset {
        let displayManager = DisplayManager()
        let entries = displayManager.captureCurrentEntries()
        guard !entries.isEmpty else { throw AutomationEngineError.noDisplays }
        let preset = PresetManager().saveCurrentLayout(name: name, entries: entries)
        AppLogger.presets.info("CLI saved preset '\(name)'.")
        return preset
    }

    /// Default name for an unnamed save: "Quick Save" plus the current time,
    /// unique to the minute (suffixed if one already exists).
    static func quickSaveName() -> String {
        let form = DateFormatter()
        form.dateFormat = "yyyy-MM-dd HH:mm"
        form.locale = Locale(identifier: "en_US_POSIX")
        let baseName = "Quick Save \(form.string(from: Date()))"
        let existing = Set(presets().map { $0.name })
        guard existing.contains(baseName) else { return baseName }
        var attempt = 2
        while existing.contains("\(baseName) (\(attempt))") { attempt += 1 }
        return "\(baseName) (\(attempt))"
    }

    /// Apply a named preset synchronously (plan → apply → verify).
    static func apply(named name: String) throws {
        let presetManager = PresetManager()
        guard let preset = presetManager.presets.first(where: { $0.name == name }) else {
            throw AutomationEngineError.presetNotFound(name)
        }
        guard !preset.displays.isEmpty else { throw AutomationEngineError.applyFailed("preset is empty") }

        let service = DisplayConfigurationService()
        var plan = try service.plan(preset: preset)
        plan = LayoutPlan(moves: plan.moves,
                          presetName: plan.presetName,
                          rollbackOrigins: service.snapshotOrigins())
        try service.apply(plan)

        if !verify(plan: plan) {
            throw AutomationEngineError.verificationFailed
        }

        // Remember it as the last applied preset so GUI features such as
        // "restore on reconnect" keep working across entry points.
        var settings = loadSettings()
        settings.lastAppliedPresetID = preset.id
        persist(settings: settings)

        AppLogger.configuration.info("CLI applied layout '\(preset.name)'.")
    }

    /// Cycle to the next/previous preset relative to the recognised one.
    static func cycle(direction: Int) throws {
        let presetManager = PresetManager()
        let presets = presetManager.presets
        guard !presets.isEmpty else { throw AutomationEngineError.noPresets }

        let displayManager = DisplayManager()
        let currentID = displayManager.recognisedPreset(in: presets)?.id
        let currentIndex: Int = {
            if let id = currentID, let index = presets.firstIndex(where: { $0.id == id }) {
                return index
            }
            return direction > 0 ? -1 : 0
        }()
        let next = (currentIndex + direction + presets.count * 2) % presets.count
        try apply(named: presets[next].name)
    }

    // MARK: - Status

    static func statusLines() -> String {
        let displayManager = DisplayManager()
        var lines: [String] = []
        lines.append("Connected displays (\(displayManager.connectedDisplays.count)):")
        for display in displayManager.connectedDisplays {
            var flags: [String] = []
            if display.isMain { flags.append("main") }
            if display.isBuiltIn { flags.append("built-in") }
            lines.append("• \(display.name) — \(Int(display.pointSize.width)) × \(Int(display.pointSize.height))"
                + (display.isMain ? " (main)" : "")
                + (flags.count > 1 ? " [\(flags.joined(separator: ", "))]" : ""))
        }
        let presets = presets()
        lines.append("Presets (\(presets.count)):")
        if presets.isEmpty {
            lines.append("  (none — save the current layout first)")
        }
        for preset in presets {
            let wiring = displayManager.recognisedPreset(in: presets)?.id == preset.id ? "  ← active" : ""
            lines.append("• \(preset.name) (\(preset.displayCount) displays)\(wiring)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Post-apply verification mirroring `DisplayManager.verify`: every
    /// planned target must land within tolerance of its requested origin.
    private static func verify(plan: LayoutPlan) -> Bool {
        let tolerance = 6.0
        let origins = Dictionary(uniqueKeysWithValues:
            CoreGraphicsDisplayDiscovery().currentDisplays().map { ($0.displayID, $0.origin.cgPoint) })
        for move in plan.moves {
            guard let actual = origins[move.displayID] else { return false }
            if abs(actual.x - move.targetOrigin.x) > tolerance
                || abs(actual.y - move.targetOrigin.y) > tolerance {
                return false
            }
        }
        return true
    }
}