import SwiftUI

/// The menu-bar dropdown: current setup, presets, actions.
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var saveName = ""
    @State private var showingSavePopover = false

    var body: some View {
        Text(AppConstants.appName).font(.headline)

        Section("Current Setup") {
            if appState.displayManager.connectedDisplays.isEmpty {
                Text("No displays detected")
            } else {
                ForEach(appState.displayManager.connectedDisplays) { display in
                    Label {
                        Text("\(display.name) — \(display.friendlyResolution)")
                    } icon: {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    }
                }
            }
        }

        Section("Presets") {
            if appState.presetManager.presets.isEmpty {
                Text("No presets yet — save your current layout below.")
            } else {
                ForEach(appState.presetManager.presets) { preset in
                    Button {
                        if appState.settings.confirmBeforeSwitching {
                            SaveConfirmation.confirm(
                                presetName: preset.name,
                                onConfirm: { appState.applyPreset(preset) })
                        } else {
                            appState.applyPreset(preset)
                        }
                    } label: {
                        HStack {
                            if appState.recognisedPresetID == preset.id {
                                Image(systemName: "checkmark")
                            }
                            Text(preset.name)
                            if let shortcut = preset.shortcut {
                                Spacer()
                                Text(shortcut.displayLabel).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(appState.displayManager.isApplying)
                }
            }
        }

        Button("Save Current Layout") { showingSavePopover = true }
            .popover(isPresented: $showingSavePopover) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name this layout").font(.headline)
                    TextField("e.g. Desk", text: $saveName)
                        .frame(width: 200)
                    HStack {
                        Spacer()
                        Button("Cancel") { showingSavePopover = false }
                        Button("Save") {
                            let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            appState.saveCurrentLayout(named: name)
                            saveName = ""
                            showingSavePopover = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
            }

        Divider()

        Button("Settings…") { openWindow(id: "settings") }
            .keyboardShortcut(",", modifiers: .command)

        Button("Quit \(AppConstants.appName)") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

/// Tiny helper to surface a confirm-before-switching alert from the menu.
@MainActor
enum SaveConfirmation {
    static func confirm(presetName: String, onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Apply '\(presetName)'?"
        alert.informativeText = "Your display arrangement will change immediately."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }
}
