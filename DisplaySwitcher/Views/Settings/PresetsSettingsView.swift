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
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = PresetsDocument(presets: [])
    @State private var pendingImportURL: URL?
    @State private var importNotice: String?

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
                Button("Export…") {
                    exportDocument = PresetsDocument(presets: appState.presetManager.presets)
                    showExporter = true
                }
                Button("Import…") {
                    showImporter = true
                }
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

            Text("Tip: drag rows to reorder. Auto-apply recalls a preset automatically when its display setup connects.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): pendingImportURL = url
            case .failure: importNotice = "Could not open that file."
            }
        }
        .fileExporter(isPresented: $showExporter,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "DisplaySwitcher-presets") { _ in }
        .confirmationDialog("Import Presets",
                            isPresented: Binding(
                                get: { pendingImportURL != nil },
                                set: { if !$0 { pendingImportURL = nil } }),
                            titleVisibility: .visible) {
            Button("Merge with existing presets") {
                if let url = pendingImportURL {
                    importFrom(url, replacing: false)
                }
                pendingImportURL = nil
            }
            Button("Replace all presets", role: .destructive) {
                if let url = pendingImportURL {
                    importFrom(url, replacing: true)
                }
                pendingImportURL = nil
            }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        }
        .alert("Import", isPresented: Binding(
            get: { importNotice != nil },
            set: { if !$0 { importNotice = nil } })) {
            Button("OK") { importNotice = nil }
        } message: {
            Text(importNotice ?? "")
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
                Toggle("Auto-apply", isOn: Binding(
                    get: { preset.autoApplyOnSetup },
                    set: { appState.presetManager.setAutoApply($0, for: preset) }))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Automatically apply this preset when its display setup connects")
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

    private func importFrom(_ url: URL, replacing: Bool) {
        let count = appState.importPresets(from: url, replacing: replacing)
        if count > 0 {
            appState.registerAllShortcuts()
            importNotice = replacing
                ? "Replaced presets with \(count) imported."
                : "Imported \(count) new presets."
        } else {
            importNotice = "The file contained no readable presets."
        }
    }
}
