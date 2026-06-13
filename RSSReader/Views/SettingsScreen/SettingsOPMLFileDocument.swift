import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsOPMLFileDocument: FileDocument {
    static let contentType = UTType(filenameExtension: "opml") ?? .xml
    static var readableContentTypes: [UTType] { [contentType, .xml] }
    static var writableContentTypes: [UTType] { [contentType, .xml] }

    let xml: String

    init(xml: String) {
        self.xml = xml
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let xml = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.xml = xml
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(xml.utf8))
    }
}
