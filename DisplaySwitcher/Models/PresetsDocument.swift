import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// `FileDocument` bridge so the Settings view can export presets through the
/// native SwiftUI `fileExporter`.
struct PresetsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(presets: [DisplayPreset]) {
        self.data = (try? JSONEncoder().encode(PresetStoreFile(presets: presets)))
            ?? Data("{}".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data("{}".utf8)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}