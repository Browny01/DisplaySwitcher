import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { appState.settings.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }))
                if let message = appState.loginItemManager.lastErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Text("Requires the app to be code-signed to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Confirm before switching layouts",
                       isOn: boolBinding(\.confirmBeforeSwitching))
                Toggle("Show notifications",
                       isOn: boolBinding(\.notificationsEnabled))
                Toggle("Automatically recognise current preset",
                       isOn: boolBinding(\.autoRecogniseCurrentPreset))
                Toggle("Restore last preset when its displays reconnect",
                       isOn: boolBinding(\.restoreLastPresetOnReconnect))
                Text("Automatic restore is off by default and never changes your layout unless the exact saved displays reconnect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                Text("Presets are stored locally in Application Support — no account, no cloud, no telemetry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reveal Presets File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [appState.presetManager.storeFileURL])
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
    }

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { appState.settings[keyPath: keyPath] = $0 })
    }
}
