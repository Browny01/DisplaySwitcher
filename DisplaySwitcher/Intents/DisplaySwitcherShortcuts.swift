import AppIntents
import Foundation

/// Shortcuts.app support. `AppShortcutsProvider` publishes the shortcuts so
/// they appear in the Shortcuts app; the intents themselves route through the
/// same headless `AutomationEngine` the CLI uses.
struct DisplaySwitcherAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyPresetIntent(),
            phrases: [
                "Apply \(\.$preset) display preset in \(.applicationName)",
                "Switch to \(\.$preset) in \(.applicationName)",
            ],
            shortTitle: "Apply Preset",
            systemImageName: "display.2"
        )
        AppShortcut(
            intent: SaveCurrentLayoutIntent(),
            phrases: [
                "Save my display layout in \(.applicationName)",
                "Save current display layout in \(.applicationName)",
            ],
            shortTitle: "Save Layout",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: NextPresetIntent(),
            phrases: [
                "Switch to the next display preset in \(.applicationName)",
                "Next display preset in \(.applicationName)",
            ],
            shortTitle: "Next Preset",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: PreviousPresetIntent(),
            phrases: [
                "Switch to the previous display preset in \(.applicationName)",
                "Previous display preset in \(.applicationName)",
            ],
            shortTitle: "Previous Preset",
            systemImageName: "backward.end.fill"
        )
    }
}

/// A named display preset exposed to Shortcuts.app. Identified by its name so
/// Shortcuts can offer a live, searchable list of the user's presets.
struct PresetEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Display preset")
    static let defaultQuery = PresetEntityQuery()

    var id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

/// Provides the list of presets (for the Shortcuts picker) and resolves a
/// chosen preset name from a running shortcut.
struct PresetEntityQuery: EntityQuery {
    func entities(for identifiers: [PresetEntity.ID]) async throws -> [PresetEntity] {
        let names = await MainActor.run { AutomationEngine.presets().map { $0.name } }
        return identifiers.compactMap { id in names.contains(id) ? PresetEntity(id: id) : nil }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        let presets = await MainActor.run { AutomationEngine.presets() }
        return presets.map { PresetEntity(id: $0.name) }
    }
}

struct ApplyPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply display preset"
    static let description = IntentDescription(
        "Applies one of your saved display presets.")

    @Parameter(title: "Preset", requestValueDialog: "Which preset should I apply?")
    var preset: PresetEntity?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let name = preset?.id else {
            throw AutomationEngineError.presetNotFound("")
        }
        try AutomationEngine.apply(named: name)
        return .result(dialog: "Applied \"\(name)\".")
    }
}

struct SaveCurrentLayoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Save current display layout"
    static let description = IntentDescription(
        "Saves your current display arrangement as a new preset.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let form = DateFormatter()
        form.dateFormat = "yyyy-MM-dd HH:mm"
        form.locale = Locale(identifier: "en_US_POSIX")
        let name = "Quick Save \(form.string(from: Date()))"
        _ = try AutomationEngine.save(named: name)
        return .result(dialog: "Saved layout as \"\(name)\".")
    }
}

struct NextPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to next display preset"
    static let description = IntentDescription(
        "Cycles to the next saved display preset.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AutomationEngine.cycle(direction: 1)
        return .result(dialog: "Switched to the next display preset.")
    }
}

struct PreviousPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to previous display preset"
    static let description = IntentDescription(
        "Cycles to the previous saved display preset.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AutomationEngine.cycle(direction: -1)
        return .result(dialog: "Switched to the previous display preset.")
    }
}