import Foundation

extension SettingsScreenController {
    func prepareOPMLImportPreview(
        data: Data,
        dependencies: AppDependencies
    ) {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "Import Unavailable",
                    message: dependencies.modelContainerBootstrapFailureDescription
                        ?? "Sources are unavailable in the current app environment.",
                    kind: .failure
                )
            )
            return
        }

        do {
            let document = try OPMLParserService.parse(data)
            let plan = try OPMLImportPreviewPlanner.makePlan(
                document: document,
                sourceManagementService: sourceManagementService
            )
            screenState.presentOPMLImportPreview(
                SettingsOPMLImportPreviewPresentation(plan: plan)
            )
        } catch {
            dependencies.logger.error("Failed to prepare OPML import preview: \(error)")
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "OPML Import Failed",
                    message: opmlImportFailureMessage(for: error),
                    kind: .failure
                )
            )
        }
    }

    func dismissOPMLImportPreview() {
        screenState.dismissOPMLImportPreview()
    }

    func dismissOPMLTransferStatus() {
        screenState.dismissOPMLTransferStatus()
    }

    func commitOPMLImportPreview(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "Import Unavailable",
                    message: dependencies.modelContainerBootstrapFailureDescription
                        ?? "Sources are unavailable in the current app environment.",
                    kind: .failure
                )
            )
            return
        }

        guard let preview = screenState.opmlImportPreview else {
            return
        }

        do {
            let result = try OPMLImportPersistenceService.importPreview(
                preview.plan,
                sourceManagementService: sourceManagementService
            )
            screenState.dismissOPMLImportPreview()
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "OPML Import Complete",
                    message: "\(result.createdFeedCount) sources imported. \(result.skippedEntryCount) skipped.",
                    kind: .success
                )
            )
            if result.createdFeedCount > 0 || result.createdFolderCount > 0 {
                appState?.requestSourcesSidebarReload()
                appState?.requestArticleListReload()
            }
        } catch {
            dependencies.logger.error("Failed to import OPML preview: \(error)")
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "OPML Import Failed",
                    message: "The app could not save the selected OPML sources. Try again.",
                    kind: .failure
                )
            )
        }
    }

    func makeOPMLExportDocument(dependencies: AppDependencies) -> SettingsOPMLFileDocument? {
        guard let feedRepository = dependencies.feedRepository,
              let folderRepository = dependencies.folderRepository else {
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "Export Unavailable",
                    message: dependencies.modelContainerBootstrapFailureDescription
                        ?? "Sources are unavailable in the current app environment.",
                    kind: .failure
                )
            )
            return nil
        }

        do {
            let xml = try OPMLExportService.exportDocument(
                feedRepository: feedRepository,
                folderRepository: folderRepository
            )
            return SettingsOPMLFileDocument(xml: xml)
        } catch {
            dependencies.logger.error("Failed to export OPML document: \(error)")
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "OPML Export Failed",
                    message: "The app could not build an OPML file right now. Try again.",
                    kind: .failure
                )
            )
            return nil
        }
    }

    func applyOPMLExportCompletion(_ result: Result<URL, any Error>, dependencies: AppDependencies) {
        switch result {
        case .success:
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "OPML Export Complete",
                    message: "Your subscriptions were exported successfully.",
                    kind: .success
                )
            )
        case .failure(let error):
            dependencies.logger.error("Failed to write OPML export document: \(error)")
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: "OPML Export Failed",
                    message: "The app could not save the OPML file. Try again.",
                    kind: .failure
                )
            )
        }
    }

    private func opmlImportFailureMessage(for error: Error) -> String {
        switch error {
        case OPMLParserError.emptyDocument:
            return "The selected file is empty."
        case OPMLParserError.malformedXML:
            return "The selected file is not valid XML."
        case OPMLParserError.unsupportedRootElement:
            return "The selected file is not an OPML document."
        case OPMLParserError.missingBody:
            return "The selected OPML document does not contain a subscription list."
        default:
            return "The app could not read the selected OPML file."
        }
    }
}
