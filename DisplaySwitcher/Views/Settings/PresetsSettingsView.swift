import SwiftUI

/// Preset cards/rows: name, arrangement diagram, display count, shortcut,
// Rename, Apply, Duplicate, Delete + drag-to-reorder + save-current.
struct PresetsSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var newPresetName = ""
    @State private var renamingPreset: DisplayPreset?
    @State private var renameText = ""
    @State private var recordingShortcutFor: DisplayPreset?
    @State private var pendingConfirmPreset: DisplayPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Save current layout row.
            HStack {
                TextField("New preset name, e.g. Desk", text: $newPresetName)
                Button("Save Current Layout") {
                    let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    appState.saveCurrentLayout(named: name)
                    newPresetName = ""
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = appState.displayManager.lastError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if appState.presetManager.presets.isEmpty {
                ContentUnavailableView(
                    "No presets yet",
                    systemImage: "rectangle.on.rectangle",
                    description: Text("Arrange your displays in System Settings, then save the layout here."))
            } else {
                List {
                    ForEach(appState.presetManager.presets) { preset in
                        presetRow(preset)
                    }
                    .onMove { source, destination in
                        appState.presetManager.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            appState.presetManager.delete(appState.presetManager.presets[index])
                        }
                        appState.registerAllShortcuts()
                    }
                }
                .listStyle(.inset)
            }

            Text("Tip: drag rows to reorder. Your most-used preset can go first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $renamingPreset) { preset in
            VStack(spacing: 12) {
                Text("Rename preset").font(.headline)
                TextField("Preset name", text: $renameText)
                    .frame(width: 240)
                HStack {
                    Button("Cancel") { renamingPreset = nil }
                    Button("Rename") {
                        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { appState.presetManager.rename(preset, to: name) }
                        renamingPreset = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .onAppear { renameText = preset.name }
        }
        .sheet(item: $recordingShortcutFor) { preset in
            ShortcutRecorderView(
                title: "Shortcut for '\(preset.name)'",
                current: preset.shortcut,
                onSave: { shortcut in
                    appState.presetManager.setShortcut(shortcut, for: preset)
                    appState.registerAllShortcuts()
                    recordingShortcutFor = nil
                },
                onClear: {
                    appState.presetManager.setShortcut(nil, for: preset)
                    appState.registerAllShortcuts()
                    recordingShortcutFor = nil
                },
                onCancel: { recordingShortcutFor = nil })
        }
        .alert(item: $pendingConfirmPreset) { preset in
            Alert(
                title: Text("Apply '\(preset.name)'?"),
                message: Text("Your display arrangement will change immediately."),
                primaryButton: .default(Text("Apply")) { appState.applyPreset(preset) },
                secondaryButton: .cancel { pendingConfirmPreset = nil })
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: DisplayPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if appState.recognisedPresetID == preset.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Currently active")
                }
                Text(preset.name).font(.headline)
                Spacer()
                Text("\(preset.displayCount) displays")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let shortcut = preset.shortcut {
                    Text(shortcut.displayLabel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            LayoutPreviewView(preset: preset, height: 80)
            HStack {
                Button("Apply") {
                    if appState.settings.confirmBeforeSwitching {
                        pendingConfirmPreset = preset
                    } else {
                        appState.applyPreset(preset)
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appState.displayManager.isApplying)
                Button("Rename") { renamingPreset = preset }
                    .controlSize(.small)
                Button("Duplicate") { appState.presetManager.duplicate(preset) }
                    .controlSize(.small)
                Button("Shortcut…") { recordingShortcutFor = preset }
                    .controlSize(.small)
                Spacer()
                Button(role: .destructive) {
                    appState.presetManager.delete(preset)
                    appState.registerAllShortcuts()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
