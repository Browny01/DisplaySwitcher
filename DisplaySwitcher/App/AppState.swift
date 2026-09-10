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
    private var presetChangeObserver: NSObjectProtocol?
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

        // Presets can also be changed on disk by the CLI or Shortcuts.app; the
        // in-app manager only knows about in-memory edits, so reload whenever
        // the file is persisted so the menu bar and settings stay in sync.
        self.presetChangeObserver = NotificationCenter.default.addObserver(
            forName: .presetManagerDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadPresets() }
        }

        // Create the menu-bar status item eagerly so the icon appears at
        // launch, before any window is opened.
        self.menuBarCoordinator = MenuBarCoordinator(appState: self)
    }

    // MARK: - Preset reload

    func reloadPresets() {
        presetManager.load()
        updateRecognisedPreset()
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

    /// Save with the nearest Quick Save name (dated, unique to the minute).
    func quickSaveCurrentLayout() {
        saveCurrentLayout(named: AutomationEngine.quickSaveName())
    }

    // MARK: - Import / Export

    @discardableResult
    func exportPresets(to url: URL) -> Bool {
        do {
            try presetManager.export(to: url)
            AppLogger.ui.info("Exported \(self.presetManager.presets.count) presets to \(url.lastPathComponent).")
            return true
        } catch {
            AppLogger.ui.error("Preset export failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func importPresets(from url: URL, replacing: Bool) -> Int {
        let count = presetManager.importFile(at: url, replacing: replacing)
        if count > 0 {
            updateRecognisedPreset()
        }
        return count
    }

    func applyPreset(_ preset: DisplayPreset) {
        Task {
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

        // Automatic per-setup switching: recall any preset that is marked
        // "auto-apply" and whose saved displays now match the connected set.
        applyAutomaticSetupPresetIfNeeded()
    }

    /// Applies the first auto-apply preset whose saved displays fully match
    /// the currently connected set — but only if that preset is not already
    /// the recognised active one (avoids re-applying the same layout).
    private func applyAutomaticSetupPresetIfNeeded() {
        let candidates = presetManager.presets.filter { $0.autoApplyOnSetup }
        guard !candidates.isEmpty, !displayManager.isApplying else { return }
        let connected = displayManager.connectedDisplays
        for preset in candidates {
            guard recognisedPresetID != preset.id else { continue }
            let matches = DisplayMatcher.match(preset: preset, against: connected)
            if DisplayMatcher.isCompleteMatch(matches, preset: preset) {
                AppLogger.ui.info("Detected setup for '\(preset.name)'; auto-applying.")
                applyPreset(preset)
                return
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
        if let shortcut = settings.quickSaveShortcut {
            shortcutManager.setShortcut(shortcut, named: "quickSave") { [weak self] in
                Task { @MainActor [weak self] in self?.quickSaveCurrentLayout() }
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

    // MARK: - MenuBar

    /// Owning reference that keeps the NSStatusItem alive for the app's
    /// lifetime. Created lazily on first access from the UI layer.
    var menuBarCoordinator: MenuBarCoordinator?

    func ensureMenuBarCoordinator() {
        if menuBarCoordinator == nil {
            menuBarCoordinator = MenuBarCoordinator(appState: self)
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: AppConstants.settingsKey)
        }
        updateRecognisedPreset()
    }
}
