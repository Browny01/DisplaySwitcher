import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Creates and owns the menu-bar status item using the classic AppKit
/// `NSStatusItem` + `NSMenu` API.
///
/// On macOS 26 the SwiftUI `MenuBarExtra` scene has been observed not to
/// materialise a status item in some configurations (and it cannot be
/// created programmatically). `NSStatusItem` is the battle-tested API used
/// by Rectangle, Ice and similar utilities, and guarantees the icon appears.
@MainActor
final class MenuBarCoordinator: NSObject {
    private var statusItem: NSStatusItem?
    private var observeDisplaysChange: NSObjectProtocol?
    private var observePresetsChange: NSObjectProtocol?
    private let appState: AppState

    init(appState: AppState, isPreview: Bool = false) {
        self.appState = appState
        super.init()
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
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func observeChanges() {
        observeDisplaysChange = NotificationCenter.default.addObserver(
            forName: .displayManagerDidRefresh, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildOnDisplaysChange() }
        }
        observePresetsChange = NotificationCenter.default.addObserver(
            forName: .presetManagerDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildOnPresetsChange() }
        }
    }

    deinit {
        if let observeDisplaysChange { NotificationCenter.default.removeObserver(observeDisplaysChange) }
        if let observePresetsChange { NotificationCenter.default.removeObserver(observePresetsChange) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    // MARK: - Menu construction

    /// Applies `self` as the target of every item that has an action, so
    /// clicks actually dispatch to this coordinator.
    private func bindTargets(in menu: NSMenu) {
        for item in menu.items {
            if item.action != nil {
                item.target = self
            }
            if let submenu = item.submenu {
                bindTargets(in: submenu)
            }
        }
    }

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

        // Import / Export
        let exportItem = NSMenuItem(title: "Export Presets…", action: #selector(exportPresets(_:)),
                                    keyEquivalent: "")
        menu.addItem(exportItem)
        let importItem = NSMenuItem(title: "Import Presets…", action: #selector(importPresets(_:)),
                                    keyEquivalent: "")
        menu.addItem(importItem)
        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        // Quit
        menu.addItem(NSMenuItem(title: "Quit \(AppConstants.appName)", action: #selector(quit(_:)),
                                keyEquivalent: "q"))
        bindTargets(in: menu)
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

    @objc private func exportPresets(_ sender: NSMenuItem) {
        let panel = NSSavePanel()
        panel.title = "Export Presets"
        panel.nameFieldStringValue = "DisplaySwitcher-presets.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !appState.exportPresets(to: url) {
            presentErrorAlert("Could not export presets. Check that the destination is writable.")
        }
    }

    @objc private func importPresets(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.title = "Import Presets"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Import Presets"
        alert.informativeText = "Import \(panel.nameFieldStringValue)? Merge it with your existing presets, or replace them all?"
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace All")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            let count = appState.importPresets(from: url, replacing: false)
            if count == 0 { presentErrorAlert("The file contained no readable presets.") }
        case .alertSecondButtonReturn:
            let count = appState.importPresets(from: url, replacing: true)
            if count == 0 { presentErrorAlert("The file contained no readable presets.") }
        default:
            break
        }
    }

    private func presentErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
        alert.informativeText = "Name this arrangement so you can switch back to it later (leave blank for a Quick Save)."
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.placeholderString = AutomationEngine.quickSaveName()
        alert.accessoryView = textField
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = textField
        // An LSUIElement (menu-bar-only) app is never automatically active;
        // activate it so the modal dialog actually appears on screen.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            appState.saveCurrentLayout(named: name.isEmpty ? AutomationEngine.quickSaveName() : name)
        }
    }
}
