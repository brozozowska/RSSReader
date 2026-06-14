import Foundation

extension SettingsScreenController {
    func prepareOPMLImportPreview(
        data: Data,
        dependencies: AppDependencies
    ) {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: SettingsLocalization.importUnavailableTitle,
                    message: dependencies.modelContainerBootstrapFailureDescription
                        ?? SettingsLocalization.sourcesUnavailableMessage,
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
                    title: SettingsLocalization.opmlImportFailedTitle,
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
                    title: SettingsLocalization.importUnavailableTitle,
                    message: dependencies.modelContainerBootstrapFailureDescription
                        ?? SettingsLocalization.sourcesUnavailableMessage,
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
                    title: SettingsLocalization.opmlImportCompleteTitle,
                    message: SettingsLocalization.opmlImportCompleteMessage(
                        createdFeedCount: result.createdFeedCount,
                        skippedEntryCount: result.skippedEntryCount
                    ),
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
                    title: SettingsLocalization.opmlImportFailedTitle,
                    message: SettingsLocalization.opmlImportSaveFailureMessage,
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
                    title: SettingsLocalization.exportUnavailableTitle,
                    message: dependencies.modelContainerBootstrapFailureDescription
                        ?? SettingsLocalization.sourcesUnavailableMessage,
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
                    title: SettingsLocalization.opmlExportFailedTitle,
                    message: SettingsLocalization.opmlExportBuildFailureMessage,
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
                    title: SettingsLocalization.opmlExportCompleteTitle,
                    message: SettingsLocalization.opmlExportCompleteMessage,
                    kind: .success
                )
            )
        case .failure(let error):
            dependencies.logger.error("Failed to write OPML export document: \(error)")
            screenState.applyOPMLTransferStatus(
                SettingsOPMLTransferStatusPresentation(
                    title: SettingsLocalization.opmlExportFailedTitle,
                    message: SettingsLocalization.opmlExportSaveFailureMessage,
                    kind: .failure
                )
            )
        }
    }

    private func opmlImportFailureMessage(for error: Error) -> String {
        switch error {
        case OPMLParserError.emptyDocument:
            return SettingsLocalization.selectedFileEmptyMessage
        case OPMLParserError.malformedXML:
            return SettingsLocalization.selectedFileInvalidXMLMessage
        case OPMLParserError.unsupportedRootElement:
            return SettingsLocalization.selectedFileNotOPMLMessage
        case OPMLParserError.missingBody:
            return SettingsLocalization.selectedOPMLMissingBodyMessage
        default:
            return SettingsLocalization.selectedOPMLReadFailureMessage
        }
    }
}
