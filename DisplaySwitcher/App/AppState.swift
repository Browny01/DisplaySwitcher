import AppKit
import Combine
import Foundation

/// Application settings persistence (UserDefaults) plus wiring between the
/// display layer, presets, shortcuts, and login item.
@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var recognisedPresetID: UUID?

    let displayManager: DisplayManager
    let presetManager: PresetManager
    let shortcutManager: ShortcutManager
    let loginItemManager: LoginItemManager
    let notificationService = NotificationService()

    private var cancellables = Set<AnyCancellable>()
    private var lastSignature: String?

    init(displayManager: DisplayManager? = nil,
         presetManager: PresetManager? = nil,
         shortcutManager: ShortcutManager? = nil,
         loginItemManager: LoginItemManager? = nil) {
        // Restore settings first so managers can be configured from them.
        if let data = UserDefaults.standard.data(forKey: AppConstants.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
        self.displayManager = displayManager ?? DisplayManager()
        self.presetManager = presetManager ?? PresetManager()
        self.shortcutManager = shortcutManager ?? ShortcutManager()
        self.loginItemManager = loginItemManager ?? LoginItemManager()

        self.lastSignature = DisplayMatcher.setupSignature(of: self.displayManager.connectedDisplays)
        updateRecognisedPreset()
        registerAllShortcuts()

        DisplayChangeObserver.shared.onDisplaysChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDisplaysChanged()
            }
        }
        DisplayChangeObserver.shared.start()
        notificationService.requestAuthorizationIfNeeded()
    }

    // MARK: - Preset actions

    func saveCurrentLayout(named name: String) {
        let entries = displayManager.captureCurrentEntries()
        guard !entries.isEmpty else { return }
        let preset = presetManager.saveCurrentLayout(name: name, entries: entries)
        updateRecognisedPreset()
        registerAllShortcuts()
        if settings.notificationsEnabled {
            notificationService.show(title: AppConstants.appName,
                                     body: "Saved '\(preset.name)' with \(entries.count) displays")
        }
    }

    func applyPreset(_ preset: DisplayPreset) {
        Task {
            if settings.confirmBeforeSwitching {
                // Confirmation is handled by the calling view via
                // `pendingConfirmationPreset`; this path applies directly.
            }
            let ok = await displayManager.applyPreset(preset, settings: settings)
            if ok {
                settings.lastAppliedPresetID = preset.id
                updateRecognisedPreset()
            }
        }
    }

    func updateRecognisedPreset() {
        guard settings.autoRecogniseCurrentPreset else {
            recognisedPresetID = nil
            return
        }
        recognisedPresetID = displayManager.recognisedPreset(in: presetManager.presets)?.id
    }

    // MARK: - Display change handling

    func handleDisplaysChanged() {
        displayManager.refresh()
        updateRecognisedPreset()
        let signature = DisplayMatcher.setupSignature(of: displayManager.connectedDisplays)
        defer { lastSignature = signature }
        guard signature != lastSignature else { return }

        // Optional opt-in automation: re-apply the last used preset when its
        // displays reconnect. Off by default; never moves displays otherwise.
        if settings.restoreLastPresetOnReconnect,
           let lastID = settings.lastAppliedPresetID,
           let preset = presetManager.preset(withID: lastID) {
            let matches = DisplayMatcher.match(preset: preset,
                                               against: displayManager.connectedDisplays)
            if DisplayMatcher.isCompleteMatch(matches, preset: preset) {
                AppLogger.ui.info("Known setup reconnected; restoring '\(preset.name)'.")
                applyPreset(preset)
            }
        }
    }

    // MARK: - Shortcuts

    func registerAllShortcuts() {
        shortcutManager.unregisterAll()

        if let shortcut = settings.nextPresetShortcut {
            shortcutManager.setShortcut(shortcut, named: "nextPreset") { [weak self] in
                Task { @MainActor [weak self] in self?.cyclePreset(direction: 1) }
            }
        }
        if let shortcut = settings.previousPresetShortcut {
            shortcutManager.setShortcut(shortcut, named: "previousPreset") { [weak self] in
                Task { @MainActor [weak self] in self?.cyclePreset(direction: -1) }
            }
        }
        for preset in presetManager.presets where preset.shortcut != nil {
            shortcutManager.setShortcut(preset.shortcut, named: "preset-\(preset.id.uuidString)") { [weak self] in
                Task { @MainActor [weak self] in
                    if let full = self?.presetManager.preset(withID: preset.id) {
                        self?.applyPreset(full)
                    }
                }
            }
        }
    }

    func cyclePreset(direction: Int) {
        let presets = presetManager.presets
        guard !presets.isEmpty else { return }
        let currentIndex: Int = {
            if let id = recognisedPresetID,
               let idx = presets.firstIndex(where: { $0.id == id }) { return idx }
            return direction > 0 ? -1 : 0
        }()
        let next = (currentIndex + direction + presets.count * 2) % presets.count
        applyPreset(presets[next])
    }

    // MARK: - Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemManager.setLaunchAtLogin(enabled)
        settings.launchAtLogin = loginItemManager.isRegistered
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: AppConstants.settingsKey)
        }
        updateRecognisedPreset()
    }
}
