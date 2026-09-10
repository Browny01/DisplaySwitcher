import Foundation

/// Loads, persists, and mutates presets. Storage is a versioned JSON file in
/// Application Support so presets survive restarts and are never kept in a
/// temporary location.
@MainActor
final class PresetManager: ObservableObject {
    @Published private(set) var presets: [DisplayPreset] = []

    private let fileURL: URL
    private let fileManager = FileManager.default

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = base.appendingPathComponent(AppConstants.appName, isDirectory: true)
            self.fileURL = dir.appendingPathComponent(AppConstants.presetsFileName)
        }
        load()
    }

    var storeFileURL: URL { fileURL }

    // MARK: - CRUD

    @discardableResult
    func saveCurrentLayout(name: String, entries: [PresetDisplayEntry]) -> DisplayPreset {
        let preset = DisplayPreset(name: name, displays: entries)
        presets.append(preset)
        persist()
        AppLogger.presets.info("Saved preset '\(name)' with \(entries.count) displays.")
        return preset
    }

    func rename(_ preset: DisplayPreset, to newName: String) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].name = newName
        presets[index].updatedAt = Date()
        persist()
    }

    func duplicate(_ preset: DisplayPreset) {
        guard let original = presets.first(where: { $0.id == preset.id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = uniqueName(basedOn: original.name)
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.shortcut = nil
        presets.append(copy)
        persist()
    }

    func delete(_ preset: DisplayPreset) {
        presets.removeAll(where: { $0.id == preset.id })
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Operate on ids so reordering is stable even with duplicate names.
        var ordered = presets
        let moving = source.map { ordered[$0] }
        for index in source.sorted(by: >) { ordered.remove(at: index) }
        var dest = destination
        for removed in source.sorted() where removed < destination { dest -= 1 }
        ordered.insert(contentsOf: moving, at: max(0, min(dest, ordered.count)))
        presets = ordered
        persist()
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for preset: DisplayPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        // Shortcuts must be unique across presets.
        if let shortcut {
            for i in presets.indices where presets[i].id != preset.id
                && presets[i].shortcut == shortcut {
                presets[i].shortcut = nil
            }
        }
        presets[index].shortcut = shortcut
        presets[index].updatedAt = Date()
        persist()
    }

    func setAutoApply(_ enabled: Bool, for preset: DisplayPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].autoApplyOnSetup = enabled
        presets[index].updatedAt = Date()
        persist()
    }

    // MARK: - Import / Export

    /// Write the current preset store to an arbitrary location.
    func export(to url: URL) throws {
        let data = try JSONEncoder().encode(PresetStoreFile(presets: presets))
        try data.write(to: url, options: .atomic)
    }

    /// Load a preset file. `replacing` = true replaces all presets; otherwise
    /// the imported presets are merged, renaming any duplicates. Returns the
    /// number of presets read from the file (0 on parse failure).
    @discardableResult
    func importFile(at url: URL, replacing: Bool) -> Int {
        do {
            let data = try Data(contentsOf: url)
            let store = try JSONDecoder().decode(PresetStoreFile.self, from: data)
            importPresets(migrateIfNeeded(store).presets, replacing: replacing)
            AppLogger.presets.info("Imported \(store.presets.count) presets\(replacing ? " (replaced)" : "").")
            return store.presets.count
        } catch {
            AppLogger.presets.error("Failed to import presets: \(error.localizedDescription)")
            return 0
        }
    }

    private func importPresets(_ imported: [DisplayPreset], replacing: Bool) {
        if replacing {
            presets = imported
        } else {
            var existingNames = Set(presets.map { $0.name })
            for preset in imported {
                var copy = preset
                copy.id = UUID()
                if existingNames.contains(copy.name) {
                    copy.name = uniqueName(basedOn: copy.name)
                }
                existingNames.insert(copy.name)
                presets.append(copy)
            }
        }
        persist()
    }

    func preset(withID id: UUID) -> DisplayPreset? {
        presets.first(where: { $0.id == id })
    }

    // MARK: - Persistence

    func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            presets = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let store = try JSONDecoder().decode(PresetStoreFile.self, from: data)
            presets = migrateIfNeeded(store).presets
        } catch {
            AppLogger.presets.error("Failed to load presets: \(error.localizedDescription)")
            // Preserve the corrupt file for diagnosis instead of deleting it.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: fileURL, to: backup)
            presets = []
        }
    }

    func persist() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            let store = PresetStoreFile(presets: presets)
            let data = try JSONEncoder().encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.presets.error("Failed to persist presets: \(error.localizedDescription)")
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .presetManagerDidChange, object: nil)
        }
    }

    // MARK: - Migration

    /// Forward-compatible loader: unknown future schema versions load
    /// read-only fields best-effort; current version passes through.
    func migrateIfNeeded(_ store: PresetStoreFile) -> PresetStoreFile {
        if store.schemaVersion > AppConstants.presetsSchemaVersion {
            AppLogger.presets.info(
                "Preset file schema v\(store.schemaVersion) is newer than app v\(AppConstants.presetsSchemaVersion); loading best-effort.")
        }
        var migrated = store
        migrated.presets = store.presets.map { preset in
            var copy = preset
            // Older files may lack a schema version on the preset itself.
            if copy.schemaVersion == 0 {
                copy.schemaVersion = AppConstants.presetsSchemaVersion
            }
            return copy
        }
        return migrated
    }

    // MARK: - Private

    private func uniqueName(basedOn name: String) -> String {
        let existing = Set(presets.map { $0.name })
        if !existing.contains("\(name) Copy") { return "\(name) Copy" }
        var i = 2
        while existing.contains("\(name) Copy \(i)") { i += 1 }
        return "\(name) Copy \(i)"
    }
}
