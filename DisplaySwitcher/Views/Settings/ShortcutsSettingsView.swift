import Carbon
import SwiftUI

/// Global shortcuts for next/previous preset, plus per-preset shortcuts
/// managed from the Presets tab.
struct ShortcutsSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var recording: RecordingTarget?

    enum RecordingTarget: Identifiable, Hashable {
        case next, previous
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section("Preset navigation") {
                shortcutRow(label: "Next preset",
                            shortcut: appState.settings.nextPresetShortcut) {
                    recording = .next
                }
                shortcutRow(label: "Previous preset",
                            shortcut: appState.settings.previousPresetShortcut) {
                    recording = .previous
                }
            }
            Section("Per-preset shortcuts") {
                Text("Assign a shortcut to an individual preset from the Presets tab using its “Shortcut…” button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Notes") {
                Text("Shortcuts work globally and need no Accessibility permission. Each shortcut requires at least two modifiers (e.g. ⌃⌥) so system shortcuts are never silently overridden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $recording) { target in
            ShortcutRecorderView(
                title: target == .next ? "Shortcut for Next preset" : "Shortcut for Previous preset",
                current: target == .next ? appState.settings.nextPresetShortcut : appState.settings.previousPresetShortcut,
                onSave: { shortcut in
                    if target == .next {
                        appState.settings.nextPresetShortcut = shortcut
                    } else {
                        appState.settings.previousPresetShortcut = shortcut
                    }
                    appState.registerAllShortcuts()
                    recording = nil
                },
                onClear: {
                    if target == .next {
                        appState.settings.nextPresetShortcut = nil
                    } else {
                        appState.settings.previousPresetShortcut = nil
                    }
                    appState.registerAllShortcuts()
                    recording = nil
                },
                onCancel: { recording = nil })
        }
    }

    private func shortcutRow(label: String, shortcut: KeyboardShortcut?, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let shortcut {
                Text(shortcut.displayLabel)
                    .font(.body.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Text("None").foregroundStyle(.secondary)
            }
            Button("Record…", action: action).controlSize(.small)
        }
    }
}

/// Minimal shortcut recorder: pick a key while holding ≥2 modifiers, or pick
/// from explicit menus (no key-event interception required).
struct ShortcutRecorderView: View {
    var title: String
    var current: KeyboardShortcut?
    var onSave: (KeyboardShortcut?) -> Void
    var onClear: () -> Void
    var onCancel: () -> Void

    @State private var keyCode: UInt32 = 0
    @State private var useCommand = true
    @State private var useOption = true
    @State private var useControl = false
    @State private var useShift = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            Picker("Key", selection: $keyCode) {
                ForEach(KeyboardShortcut.catalogue, id: \.keyCode) { entry in
                    Text(entry.label).tag(entry.keyCode)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Toggle("⌃ Control", isOn: $useControl)
                Toggle("⌥ Option", isOn: $useOption)
                Toggle("⇧ Shift", isOn: $useShift)
                Toggle("⌘ Command", isOn: $useCommand)
            }
            .toggleStyle(.checkbox)

            if let preview = preview {
                Text(preview.displayLabel)
                    .font(.title2.monospaced())
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                if current != nil {
                    Button("Clear", action: onClear)
                }
                Button("Save") {
                    guard let preview else { return }
                    guard preview.usesSafeModifierCombination else {
                        errorMessage = "Hold at least two modifiers to avoid overriding system shortcuts."
                        return
                    }
                    onSave(preview)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            if let current {
                keyCode = current.keyCode
                useCommand = current.carbonModifiers & UInt32(cmdKey) != 0
                useOption = current.carbonModifiers & UInt32(optionKey) != 0
                useControl = current.carbonModifiers & UInt32(controlKey) != 0
                useShift = current.carbonModifiers & UInt32(shiftKey) != 0
            }
        }
    }

    private var preview: KeyboardShortcut? {
        var modifiers: UInt32 = 0
        if useControl { modifiers |= UInt32(controlKey) }
        if useOption { modifiers |= UInt32(optionKey) }
        if useShift { modifiers |= UInt32(shiftKey) }
        if useCommand { modifiers |= UInt32(cmdKey) }
        return KeyboardShortcut(keyCode: keyCode, carbonModifiers: modifiers)
    }
}
