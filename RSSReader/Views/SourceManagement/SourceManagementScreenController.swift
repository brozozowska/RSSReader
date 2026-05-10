import Foundation
import Observation

@MainActor
@Observable
final class SourceManagementScreenController {
    var screenState: SourceManagementScreenState
    let isPreviewMode: Bool
    private var scenarioToRestoreAfterCreateFolder: SourceManagementScenarioID? = nil

    init(previewScreenState: SourceManagementScreenState? = nil) {
        self.screenState = previewScreenState ?? SourceManagementScreenState()
        self.isPreviewMode = previewScreenState != nil
    }

    func viewState() -> SourceManagementScreenViewState {
        screenState.derivedViewState()
    }

    func handleLaunchContext(
        _ launchContext: SourceManagementScreenLaunchContext,
        dependencies: AppDependencies
    ) {
        guard isPreviewMode == false else { return }

        switch launchContext {
        case .entry:
            return
        case .editFeed(let feedID):
            dependencies.loadSourceManagementAddFeedEditContext(
                feedID: feedID,
                into: &screenState
            )
            screenState.presentScenario(.addFeed)
        case .editFolder(let folderID):
            dependencies.loadSourceManagementCreateFolderEditContext(
                folderID: folderID,
                into: &screenState
            )
            screenState.presentScenario(.createFolder)
        }
    }

    func handleScenarioSelection(
        _ scenarioID: SourceManagementScenarioID,
        dependencies: AppDependencies? = nil
    ) {
        switch scenarioID {
        case .addFeed:
            screenState.resetAddFeedForEntry()
            if let dependencies {
                dependencies.loadSourceManagementAddFeedContext(into: &screenState)
            }
            screenState.presentScenario(.addFeed)
        case .createFolder:
            scenarioToRestoreAfterCreateFolder = nil
            screenState.resetCreateFolderForEntry()
            if let dependencies {
                dependencies.loadSourceManagementCreateFolderContext(into: &screenState)
            }
            screenState.presentScenario(.createFolder)
        case .moveSource:
            if let dependencies {
                dependencies.loadSourceManagementMoveSourceContext(into: &screenState)
            }
            screenState.presentScenario(scenarioID)
        }
    }

    func dismissPresentedScenario() {
        screenState.dismissPresentedScenario()
    }

    func handleCreateFolderNameChange(_ value: String) {
        screenState.updateCreateFolderNameInput(value)
    }

    func handleAddFeedURLChange(_ value: String) {
        screenState.updateAddFeedURLInput(value)
    }

    func handleAddFeedFolderPlacementSelection(
        _ placement: SourceManagementFolderPlacement
    ) {
        screenState.selectAddFeedFolderPlacement(placement)
    }

    func startCreateFolderFromAddFeed(dependencies: AppDependencies) {
        scenarioToRestoreAfterCreateFolder = .addFeed
        dependencies.loadSourceManagementCreateFolderContext(into: &screenState)
        screenState.presentScenario(.createFolder)
    }

    func handleAddFeedPrimaryAction(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) async {
        if screenState.addFeedCanConfirmPreview() {
            screenState.confirmAddFeedPreview()
            return
        }

        if let updateCommand = screenState.beginAddFeedUpdate() {
            await performAddFeedUpdate(
                updateCommand,
                dependencies: dependencies,
                appState: appState
            )
            return
        }

        if let createCommand = screenState.beginAddFeedCreation() {
            await performAddFeedCreation(
                createCommand,
                dependencies: dependencies,
                appState: appState
            )
            return
        }

        guard let requestURL = screenState.beginAddFeedPreviewLoading() else { return }
        await performAddFeedPreview(
            requestURL: requestURL,
            dependencies: dependencies
        )
    }

    func handleMoveSourceFeedSelection(_ feedID: UUID) {
        screenState.selectMoveSourceFeed(feedID)
    }

    func handleMoveSourcePlacementSelection(
        _ placement: SourceManagementFolderPlacement
    ) {
        screenState.selectMoveSourcePlacement(placement)
    }

    func submitMoveSource(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            let unavailableMessage = "Source management service is unavailable for source moves."
            dependencies.logger.error(unavailableMessage)
            screenState.applyMoveSourceFailure(
                "Source moves are unavailable in the current app environment."
            )
            return
        }

        guard let moveCommand = screenState.moveSourceCommand() else {
            screenState.applyMoveSourceFailure(
                "Select a source and a different destination before moving it."
            )
            return
        }

        screenState.beginMoveSourceSubmission()
        performMoveSource(
            moveCommand,
            using: sourceManagementService,
            dependencies: dependencies,
            appState: appState
        )
    }

    func submitCreateFolder(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        if let validationMessage = screenState.createFolderValidationMessage() {
            screenState.applyCreateFolderFailure(validationMessage)
            return
        }

        guard let sourceManagementService = dependencies.sourceManagementService else {
            let unavailableMessage = "Source management service is unavailable for folder creation."
            dependencies.logger.error(unavailableMessage)
            screenState.applyCreateFolderServiceUnavailable(
                title: screenState.isEditingCreateFolder()
                    ? "Folder editing is unavailable"
                    : "Folder creation is unavailable",
                message: screenState.isEditingCreateFolder()
                    ? "Folder editing is unavailable in the current app environment."
                    : "Folder creation is unavailable in the current app environment."
            )
            return
        }

        if let updateCommand = screenState.beginCreateFolderUpdate() {
            performCreateFolderUpdate(
                updateCommand,
                using: sourceManagementService,
                dependencies: dependencies,
                appState: appState
            )
            return
        }

        screenState.beginCreateFolderSubmission()
        performCreateFolderCreation(
            using: sourceManagementService,
            dependencies: dependencies,
            appState: appState
        )
    }
}

private extension SourceManagementScreenController {
    func performAddFeedUpdate(
        _ updateCommand: SourceManagementUpdateFeedCommand,
        dependencies: AppDependencies,
        appState: AppState?
    ) async {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            dependencies.logger.error("Source management service is unavailable for feed updates")
            screenState.applyAddFeedCreationFailure(
                SourceManagementScreenStatusMapper.addFeedSaveUnavailableStatus(isEditing: true)
            )
            return
        }

        do {
            let updatedFeed = try sourceManagementService.updateFeed(updateCommand)
            screenState.applyCreatedAddFeed(updatedFeed)
            _ = await dependencies.completeSourceManagementFeedSave(
                id: updatedFeed.id,
                using: appState
            )
        } catch let error as SourceManagementServiceError {
            dependencies.logger.error("Failed to update feed through source management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                SourceManagementScreenStatusMapper.addFeedSaveFailureStatus(
                    for: error,
                    isEditing: true
                )
            )
        } catch {
            dependencies.logger.error("Failed to update feed through source management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                SourceManagementAddFeedStatusPresentation(
                    title: "Feed changes could not be saved",
                    kind: .failure,
                    detail: "Unable to save the source changes right now. Try again."
                )
            )
        }
    }

    func performAddFeedCreation(
        _ createCommand: SourceManagementCreateFeedCommand,
        dependencies: AppDependencies,
        appState: AppState?
    ) async {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            dependencies.logger.error("Source management service is unavailable for feed creation")
            screenState.applyAddFeedCreationFailure(
                SourceManagementScreenStatusMapper.addFeedSaveUnavailableStatus(isEditing: false)
            )
            return
        }

        do {
            let createdFeed = try sourceManagementService.createFeed(createCommand)
            screenState.applyCreatedAddFeed(createdFeed)
            _ = await dependencies.completeSourceManagementFeedSave(
                id: createdFeed.id,
                using: appState
            )
        } catch let error as SourceManagementServiceError {
            dependencies.logger.error("Failed to create feed through source management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                SourceManagementScreenStatusMapper.addFeedSaveFailureStatus(
                    for: error,
                    isEditing: false
                )
            )
        } catch {
            dependencies.logger.error("Failed to create feed through source management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                SourceManagementAddFeedStatusPresentation(
                    title: "Feed could not be added",
                    kind: .failure,
                    detail: "Unable to save the new source right now. Try again."
                )
            )
        }
    }

    func performAddFeedPreview(
        requestURL: String,
        dependencies: AppDependencies
    ) async {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            dependencies.logger.error("Source management service is unavailable for feed preview")
            screenState.applyAddFeedPreviewFailure(
                SourceManagementScreenStatusMapper.addFeedPreviewUnavailableStatus(),
                requestURL: requestURL
            )
            return
        }

        do {
            let preview = try await sourceManagementService.previewFeed(urlString: requestURL)
            screenState.applyLoadedAddFeedPreview(preview, requestURL: requestURL)
        } catch {
            dependencies.logger.error("Failed to preview feed through source management flow: \(error)")
            screenState.applyAddFeedPreviewFailure(
                SourceManagementScreenStatusMapper.addFeedPreviewFailureStatus(for: error),
                requestURL: requestURL
            )
        }
    }

    func performMoveSource(
        _ moveCommand: SourceManagementMoveFeedCommand,
        using sourceManagementService: SourceManagementService,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        do {
            let previousFeed = screenState.selectedMoveSourceFeed()
            let movedFeed = try sourceManagementService.moveFeed(moveCommand)
            screenState.applyMovedSource(movedFeed)
            dependencies.completeSourceManagementMove(
                feedID: movedFeed.id,
                previousFolderName: previousFeed?.folderName,
                updatedFolderName: movedFeed.folderName,
                using: appState
            )
        } catch let error as SourceManagementServiceError {
            dependencies.logger.error("Failed to move source through source management flow: \(error)")
            screenState.applyMoveSourceFailure(
                SourceManagementScreenStatusMapper.moveSourceErrorMessage(error)
            )
        } catch {
            dependencies.logger.error("Failed to move source through source management flow: \(error)")
            screenState.applyMoveSourceFailure(
                "Unable to move the source right now. Try again."
            )
        }
    }

    func performCreateFolderUpdate(
        _ updateCommand: SourceManagementUpdateFolderCommand,
        using sourceManagementService: SourceManagementService,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        let previousFolderName = screenState.createFolderEditingName()

        do {
            let folder = try sourceManagementService.updateFolder(updateCommand)
            screenState.applyCreatedFolder(folder)
            dependencies.completeSourceManagementFolderEditing(
                previousName: previousFolderName,
                updatedFolderName: folder.name,
                using: appState
            )
        } catch let error as SourceManagementServiceError {
            dependencies.logger.error("Failed to update folder through source management flow: \(error)")
            screenState.applyCreateFolderFailure(
                SourceManagementScreenStatusMapper.createFolderErrorMessage(error)
            )
        } catch {
            dependencies.logger.error("Failed to update folder through source management flow: \(error)")
            screenState.applyCreateFolderFailure(
                "Unable to update the folder right now. Try again."
            )
        }
    }

    func performCreateFolderCreation(
        using sourceManagementService: SourceManagementService,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        do {
            let folder = try sourceManagementService.createFolder(
                SourceManagementCreateFolderCommand(
                    name: screenState.createFolderNameInput()
                )
            )
            screenState.applyCreatedFolder(folder)
            dependencies.completeSourceManagementFolderCreation(
                named: folder.name,
                using: appState
            )
            if scenarioToRestoreAfterCreateFolder == .addFeed {
                dependencies.restoreAddFeedAfterCreatingFolder(
                    folder,
                    into: &screenState
                )
                scenarioToRestoreAfterCreateFolder = nil
            }
        } catch let error as SourceManagementServiceError {
            dependencies.logger.error("Failed to create folder through source management flow: \(error)")
            screenState.applyCreateFolderFailure(
                SourceManagementScreenStatusMapper.createFolderErrorMessage(error)
            )
        } catch {
            dependencies.logger.error("Failed to create folder through source management flow: \(error)")
            screenState.applyCreateFolderFailure(
                "Unable to create the folder right now. Try again."
            )
        }
    }
}

private enum SourceManagementScreenStatusMapper {
    static func createFolderErrorMessage(_ error: SourceManagementServiceError) -> String {
        switch error {
        case .emptyFolderName:
            return "Enter a folder name to continue."
        case .duplicateFolderName:
            return "A folder with this name already exists."
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .feedNotFound,
                .folderNotFound:
            return "Unable to create the folder right now. Try again."
        }
    }

    static func moveSourceErrorMessage(_ error: SourceManagementServiceError) -> String {
        switch error {
        case .feedNotFound:
            return "The selected source no longer exists. Reload the move flow and try again."
        case .folderNotFound:
            return "The selected folder no longer exists. Reload the move flow and choose another destination."
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .emptyFolderName,
                .duplicateFolderName:
            return "Unable to move the source right now. Try again."
        }
    }

    static func addFeedSaveUnavailableStatus(
        isEditing: Bool
    ) -> SourceManagementAddFeedStatusPresentation {
        SourceManagementAddFeedStatusPresentation(
            title: isEditing ? "Feed editing is unavailable" : "Feed creation is unavailable",
            kind: .failure,
            detail: isEditing
                ? "The app cannot save source changes in the current environment."
                : "The app cannot save a new source in the current environment."
        )
    }

    static func addFeedSaveFailureStatus(
        for error: SourceManagementServiceError,
        isEditing: Bool
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .duplicateFeed:
            return SourceManagementAddFeedStatusPresentation(
                title: "This feed is already in the library",
                kind: .warning,
                detail: isEditing
                    ? "Another source already uses this normalized URL. Change the feed URL and try again."
                    : "Another source with the same normalized URL was saved before this create step finished."
            )
        case .folderNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: "Destination folder is unavailable",
                kind: .failure,
                detail: "The selected folder no longer exists. Choose another destination and try again."
            )
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: isEditing ? "Feed changes could not be saved" : "Feed could not be added",
                kind: .failure,
                detail: isEditing
                    ? "Unable to save the source changes right now. Try again."
                    : "Unable to save the new source right now. Try again."
            )
        }
    }

    static func addFeedPreviewUnavailableStatus() -> SourceManagementAddFeedStatusPresentation {
        SourceManagementAddFeedStatusPresentation(
            title: "Feed preview is unavailable",
            kind: .failure,
            detail: "Feed preview is unavailable in the current app environment."
        )
    }

    static func addFeedPreviewFailureStatus(
        for error: Error
    ) -> SourceManagementAddFeedStatusPresentation {
        if let error = error as? SourceManagementServiceError {
            return addFeedPreviewFailureStatus(for: error)
        }

        if let error = error as? FeedFetchError {
            return addFeedPreviewFailureStatus(for: error)
        }

        if let error = error as? FeedParserError {
            return addFeedPreviewFailureStatus(for: error)
        }

        return SourceManagementAddFeedStatusPresentation(
            title: "Preview could not be loaded",
            kind: .failure,
            detail: "Unable to load the feed preview right now. Try again."
        )
    }

    static func addFeedPreviewFailureStatus(
        for error: SourceManagementServiceError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .invalidFeedURL:
            return SourceManagementAddFeedStatusPresentation(
                title: "Enter a valid source address",
                kind: .failure,
                detail: "Use a website address or a direct RSS / Atom feed URL before loading the preview."
            )
        case .feedDiscoveryFailed:
            return SourceManagementAddFeedStatusPresentation(
                title: "Feed was not found",
                kind: .failure,
                detail: "The app could not find a supported RSS or Atom feed for this address."
            )
        case .previewUnavailableForNotModifiedResponse:
            return SourceManagementAddFeedStatusPresentation(
                title: "Preview metadata is unavailable",
                kind: .failure,
                detail: "The source returned a not-modified response, so the app could not inspect the feed contents."
            )
        case .duplicateFeed,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound,
                .folderNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: "Preview could not be loaded",
                kind: .failure,
                detail: "Unable to load the feed preview right now. Try again."
            )
        }
    }

    static func addFeedPreviewFailureStatus(
        for error: FeedFetchError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .transport(let transportError):
            return SourceManagementAddFeedStatusPresentation(
                title: "Network error while loading preview",
                kind: .failure,
                detail: networkFailureDetail(for: transportError)
            )
        case .invalidStatusCode(let statusCode):
            return SourceManagementAddFeedStatusPresentation(
                title: "Preview could not be loaded",
                kind: .failure,
                detail: "The server returned HTTP \(statusCode) instead of usable feed metadata."
            )
        case .unsupportedContentType(let contentType):
            let detail: String
            if let contentType, contentType.isEmpty == false {
                detail = "The URL responded with \(contentType), not a supported RSS or Atom feed."
            } else {
                detail = "The URL responded, but it did not advertise a supported RSS or Atom content type."
            }
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: detail
            )
        }
    }

    static func addFeedPreviewFailureStatus(
        for error: FeedParserError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .emptyDocument:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The URL responded, but the document was empty."
            )
        case .malformedXML:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The URL responded, but the document could not be parsed as RSS or Atom."
            )
        case .unsupportedFeedKind:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The URL responded, but it did not contain a supported RSS or Atom feed."
            )
        case .missingRSSElement(let elementName):
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The RSS document is missing the required \(elementName) element."
            )
        case .missingAtomElement(let elementName):
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The Atom document is missing the required \(elementName) element."
            )
        }
    }

    static func networkFailureDetail(for error: FeedTransportError) -> String {
        switch error {
        case .timedOut:
            return "The request timed out before the feed preview could be loaded."
        case .cannotFindHost, .dnsLookupFailed:
            return "The host name could not be resolved for this feed URL."
        case .cannotConnectToHost, .resourceUnavailable:
            return "The app could not connect to the server for this feed URL."
        case .networkConnectionLost:
            return "The network connection was lost while loading the feed preview."
        case .notConnectedToInternet:
            return "Check the internet connection and try loading the preview again."
        case .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return "The current network settings are blocking the feed preview request."
        case .invalidResponse:
            return "The server returned an invalid response for this feed preview request."
        case .unknown:
            return "The preview request failed for an unknown network reason."
        }
    }
}
