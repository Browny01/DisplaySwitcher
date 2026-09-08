import XCTest

final class PresetCodableTests: XCTestCase {
    func testPresetRoundTripsThroughJSON() throws {
        let displays = [TestFixtures.display(),
                        TestFixtures.builtInDisplay()]
        var preset = TestFixtures.preset(name: "Desk", displays: displays)
        preset.shortcut = KeyboardShortcut(keyCode: 0, carbonModifiers: 0x001800) // ctrl+opt
        preset.notes = "Home office"

        let data = try JSONEncoder().encode(PresetStoreFile(presets: [preset]))
        let decoded = try JSONDecoder().decode(PresetStoreFile.self, from: data)

        XCTAssertEqual(decoded.presets.count, 1)
        let roundTripped = decoded.presets[0]
        XCTAssertEqual(roundTripped, preset)
        XCTAssertEqual(roundTripped.displays.count, 2)
        XCTAssertEqual(roundTripped.mainDisplayFingerprint,
                       displays[0].fingerprint)
    }

    func testStoreFileSurvivesUnknownFieldsGracefully() throws {
        // Forward-compat: decoding must not fail on the documented schema.
        let json = """
        {"schemaVersion":1,"presets":[{"id":"\(UUID().uuidString)","name":"Work","createdAt":718000000.0,"updatedAt":718000000.0,"schemaVersion":1,"displays":[]}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PresetStoreFile.self, from: json)
        XCTAssertEqual(decoded.presets.first?.name, "Work")
    }

    @MainActor
    func testCorruptFileIsBackedUpNotDeleted() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("presets.json")
        try "not json{{".write(to: url, atomically: true, encoding: .utf8)

        let manager = PresetManager(fileURL: url)
        XCTAssertTrue(manager.presets.isEmpty)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(remaining.contains(where: { $0.contains("corrupt") }),
                      "Corrupt file should be preserved with a backup name, got: \(remaining)")
    }

    @MainActor
    func testMigrationFillsMissingSchemaVersion() {
        let manager = PresetManager(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json"))
        var preset = TestFixtures.preset(displays: [TestFixtures.display()])
        preset.schemaVersion = 0
        let migrated = manager.migrateIfNeeded(PresetStoreFile(presets: [preset]))
        XCTAssertEqual(migrated.presets.first?.schemaVersion, AppConstants.presetsSchemaVersion)
    }

    @MainActor
    func testPresetCRUDPersistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        let manager = PresetManager(fileURL: url)
        let preset = manager.saveCurrentLayout(
            name: "Desk",
            entries: [TestFixtures.display()].map { PresetDisplayEntry(from: $0) })
        manager.rename(preset, to: "Desk v2")

        let reloaded = PresetManager(fileURL: url)
        XCTAssertEqual(reloaded.presets.count, 1)
        XCTAssertEqual(reloaded.presets.first?.name, "Desk v2")

        reloaded.duplicate(reloaded.presets[0])
        XCTAssertEqual(reloaded.presets.count, 2)
        reloaded.delete(reloaded.presets[0])
        XCTAssertEqual(reloaded.presets.count, 1)
    }

    @MainActor
    func testShortcutUniquenessAcrossPresets() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        let manager = PresetManager(fileURL: url)
        let a = manager.saveCurrentLayout(name: "A",
            entries: [TestFixtures.display()].map { PresetDisplayEntry(from: $0) })
        let b = manager.saveCurrentLayout(name: "B",
            entries: [TestFixtures.display()].map { PresetDisplayEntry(from: $0) })
        let shortcut = KeyboardShortcut(keyCode: 0, carbonModifiers: 0x001800)
        manager.setShortcut(shortcut, for: a)
        manager.setShortcut(shortcut, for: b)
        XCTAssertNil(manager.preset(withID: a.id)?.shortcut)
        XCTAssertEqual(manager.preset(withID: b.id)?.shortcut, shortcut)
    }
}
