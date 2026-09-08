import AppKit
import SwiftUI

/// Creates and owns the menu-bar status item using the classic AppKit
/// `NSStatusItem` + `NSMenu` API.
///
/// On macOS 26 the SwiftUI `MenuBarExtra` scene has been observed not to
/// materialise a status item in some configurations (and it cannot be
/// created programmatically). `NSStatusItem` is the battle-tested API used
/// by Rectangle, Ice and similar utilities, and guarantees the icon appears.
@MainActor
final class MenuBarCoordinator {
    private var statusItem: NSStatusItem?
    private var observeDisplaysChange: NSObjectProtocol?
    private var observePresetsChange: NSObjectProtocol?
    private let appState: AppState

    init(appState: AppState, isPreview: Bool = false) {
        self.appState = appState
        if !isPreview {
            setupStatusItem()
            observeChanges()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "display.2", accessibilityDescription: AppConstants.appName)
            button.image = image
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func observeChanges() {
        observeDisplaysChange = NotificationCenter.default.addObserver(
            forName: .displayManagerDidRefresh, object: appState.displayManager, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildOnDisplaysChange() }
        }
        observePresetsChange = NotificationCenter.default.addObserver(
            forName: .presetManagerDidChange, object: appState.presetManager, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildOnPresetsChange() }
        }
    }

    deinit {
        if let observeDisplaysChange { NotificationCenter.default.removeObserver(observeDisplaysChange) }
        if let observePresetsChange { NotificationCenter.default.removeObserver(observePresetsChange) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // Keep the default menu behaviour (left click opens the menu).
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: AppConstants.appName, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        // Current setup
        let setupTitle = NSMenuItem(title: "Current Setup", action: nil, keyEquivalent: "")
        setupTitle.isEnabled = false
        menu.addItem(setupTitle)
        if appState.displayManager.connectedDisplays.isEmpty {
            menu.addItem(withTitle: "No displays detected", action: nil, keyEquivalent: "")
        } else {
            for display in appState.displayManager.connectedDisplays {
                let icon = display.isBuiltIn ? "laptopcomputer" : "display"
                let item = NSMenuItem(title: "\(display.name) — \(display.friendlyResolution)",
                                      action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        // Presets
        let presetsTitle = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presetsTitle.isEnabled = false
        menu.addItem(presetsTitle)
        if appState.presetManager.presets.isEmpty {
            menu.addItem(withTitle: "No presets yet — save your current layout below.",
                         action: nil, keyEquivalent: "")
        } else {
            for preset in appState.presetManager.presets {
                let title = (appState.recognisedPresetID == preset.id ? "✓  " : "") + preset.name
                let item = NSMenuItem(title: title, action: #selector(applyPreset(_:)),
                                      keyEquivalent: "")
                item.representedObject = preset
                item.isEnabled = !appState.displayManager.isApplying
                if let shortcut = preset.shortcut {
                    item.keyEquivalentModifierMask = shortcut.carbonModifierFlags
                    item.keyEquivalent = shortcut.keyEquivalent
                }
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        // Save current layout
        let saveItem = NSMenuItem(title: "Save Current Layout…", action: #selector(saveCurrentLayout(_:)),
                                  keyEquivalent: "")
        menu.addItem(saveItem)
        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        // Quit
        menu.addItem(NSMenuItem(title: "Quit \(AppConstants.appName)", action: #selector(quit(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private func rebuildOnDisplaysChange() {
        statusItem?.menu = buildMenu()
    }

    private func rebuildOnPresetsChange() {
        // Simply rebuild; the running menu cannot be mutated mid-display in
        // macOS 26, so replacing the whole menu is the reliable approach.
        statusItem?.menu = buildMenu()
        // Re-register preset shortcuts after any preset mutation.
        appState.registerAllShortcuts()
    }

    // MARK: - Actions

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? DisplayPreset else { return }
        if appState.settings.confirmBeforeSwitching {
            let alert = NSAlert()
            alert.messageText = "Apply '\(preset.name)'?"
            alert.informativeText = "Your display arrangement will change immediately."
            alert.addButton(withTitle: "Apply")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        appState.applyPreset(preset)
    }

    @objc private func saveCurrentLayout(_ sender: NSMenuItem) {
        presentSaveLayoutPopover()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        SettingsWindowPresenter.present()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Save-layout popover

    private var saveAlertController: NSAlert?

    private func presentSaveLayoutPopover() {
        let alert = NSAlert()
        alert.messageText = "Save Current Layout"
        alert.informativeText = "Name this arrangement so you can switch back to it later."
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.placeholderString = "e.g. Desk"
        alert.accessoryView = textField
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = textField
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                appState.saveCurrentLayout(named: name)
            }
        }
    }
}
