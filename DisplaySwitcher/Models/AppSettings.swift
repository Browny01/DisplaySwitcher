import Foundation

/// User preferences. Stored in UserDefaults; presets live in Application Support.
struct AppSettings: Codable, Sendable {
    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true
    var confirmBeforeSwitching: Bool = false
    var notificationsEnabled: Bool = true
    var autoRecogniseCurrentPreset: Bool = true
    /// Off by default: never move the user's displays unless they opt in.
    var restoreLastPresetOnReconnect: Bool = false
    var nextPresetShortcut: KeyboardShortcut?
    var previousPresetShortcut: KeyboardShortcut?
    var openMenuShortcut: KeyboardShortcut?
    /// Fingerprint-set signature of the last successfully applied preset.
    var lastAppliedPresetID: UUID?

    static let `default` = AppSettings()
}
