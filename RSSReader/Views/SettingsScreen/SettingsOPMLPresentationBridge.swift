import Foundation
import Observation

@MainActor
@Observable
final class SettingsOPMLPresentationBridge {
    var isImporterPresented = false
    var isExporterPresented = false
    private(set) var exportDocument: SettingsOPMLFileDocument?
    private(set) var isPreparingImport = false
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importID: UUID?

    func presentExporter(document: SettingsOPMLFileDocument?) {
        guard let document else { return }
        exportDocument = document
        isExporterPresented = true
    }

    func clearExportDocument() {
        exportDocument = nil
    }

    func handleImportResult(
        _ result: Result<URL, any Error>,
        preparePreview: @escaping @MainActor (URL) async -> Void,
        reportFailure: @MainActor (any Error) -> Void
    ) {
        cancelImport()
        switch result {
        case .success(let url):
            let id = UUID()
            importID = id
            isPreparingImport = true
            importTask = Task { @MainActor [weak self] in
                defer { self?.finishImport(id: id) }
                guard Task.isCancelled == false else { return }
                await preparePreview(url)
            }
        case .failure(let error):
            reportFailure(error)
        }
    }

    func endPresentation() {
        cancelImport()
        isImporterPresented = false
        isExporterPresented = false
        clearExportDocument()
    }

    private func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importID = nil
        isPreparingImport = false
    }

    private func finishImport(id: UUID) {
        guard importID == id else { return }
        importTask = nil
        importID = nil
        isPreparingImport = false
    }
}
