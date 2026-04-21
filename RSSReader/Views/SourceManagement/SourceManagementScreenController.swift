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

    func handleScenarioSelection(
        _ scenarioID: SourceManagementScenarioID,
        dependencies: AppDependencies? = nil
    ) {
        switch scenarioID {
        case .addFeed:
            if let dependencies {
                loadAddFeedContext(dependencies: dependencies)
            }
            screenState.presentScenario(.addFeed)
        case .createFolder:
            scenarioToRestoreAfterCreateFolder = nil
            if let dependencies {
                loadCreateFolderContext(dependencies: dependencies)
            }
            screenState.presentScenario(.createFolder)
        case .moveSource:
            if let dependencies {
                loadMoveSourceContext(dependencies: dependencies)
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
        loadCreateFolderContext(dependencies: dependencies)
        screenState.presentScenario(.createFolder)
    }

    func handleAddFeedPrimaryAction(dependencies: AppDependencies) async {
        if screenState.addFeedCanConfirmPreview() {
            screenState.confirmAddFeedPreview()
            return
        }

        if let createCommand = screenState.beginAddFeedCreation() {
            guard let sourceManagementService = dependencies.sourceManagementService else {
                dependencies.logger.error("Source management service is unavailable for feed creation")
                screenState.applyAddFeedCreationFailure(
                    addFeedCreationUnavailableStatus()
                )
                return
            }

            do {
                let createdFeed = try sourceManagementService.createFeed(createCommand)
                screenState.applyCreatedAddFeed(createdFeed)
            } catch let error as SourceManagementServiceError {
                dependencies.logger.error("Failed to create feed through source management flow: \(error)")
                screenState.applyAddFeedCreationFailure(
                    addFeedCreationFailureStatus(for: error)
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
            return
        }

        guard let requestURL = screenState.beginAddFeedPreviewLoading() else { return }

        guard let sourceManagementService = dependencies.sourceManagementService else {
            dependencies.logger.error("Source management service is unavailable for feed preview")
            screenState.applyAddFeedPreviewFailure(
                addFeedPreviewUnavailableStatus(),
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
                addFeedPreviewFailureStatus(for: error),
                requestURL: requestURL
            )
        }
    }

    func handleMoveSourceFeedSelection(_ feedID: UUID) {
        screenState.selectMoveSourceFeed(feedID)
    }

    func handleMoveSourcePlacementSelection(
        _ placement: SourceManagementFolderPlacement
    ) {
        screenState.selectMoveSourcePlacement(placement)
    }

    func submitMoveSource(dependencies: AppDependencies) {
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

        do {
            let movedFeed = try sourceManagementService.moveFeed(moveCommand)
            screenState.applyMovedSource(movedFeed)
        } catch let error as SourceManagementServiceError {
            dependencies.logger.error("Failed to move source through source management flow: \(error)")
            screenState.applyMoveSourceFailure(moveSourceErrorMessage(error))
        } catch {
            dependencies.logger.error("Failed to move source through source management flow: \(error)")
            screenState.applyMoveSourceFailure(
                "Unable to move the source right now. Try again."
            )
        }
    }

    func submitCreateFolder(dependencies: AppDependencies) {
        guard let validationMessage = screenState.createFolderValidationMessage() else {
            guard let sourceManagementService = dependencies.sourceManagementService else {
                let unavailableMessage = "Source management service is unavailable for folder creation."
                dependencies.logger.error(unavailableMessage)
                screenState.applyCreateFolderServiceUnavailable(
                    message: "Folder creation is unavailable in the current app environment."
                )
                return
            }

            screenState.beginCreateFolderSubmission()

            do {
                let folder = try sourceManagementService.createFolder(
                    SourceManagementCreateFolderCommand(
                        name: screenState.createFolderNameInput()
                    )
                )
                screenState.applyCreatedFolder(folder)
                if scenarioToRestoreAfterCreateFolder == .addFeed {
                    let folders = try sourceManagementService.fetchFolders()
                    screenState.applyAddFeedFolderContext(folders: folders)
                    screenState.selectAddFeedFolderPlacement(.folder(folder.id))
                    screenState.presentScenario(.addFeed)
                    scenarioToRestoreAfterCreateFolder = nil
                }
            } catch let error as SourceManagementServiceError {
                let message = createFolderErrorMessage(error)
                dependencies.logger.error("Failed to create folder through source management flow: \(error)")
                screenState.applyCreateFolderFailure(message)
            } catch {
                dependencies.logger.error("Failed to create folder through source management flow: \(error)")
                screenState.applyCreateFolderFailure(
                    "Unable to create the folder right now. Try again."
                )
            }
            return
        }

        screenState.applyCreateFolderFailure(validationMessage)
    }
}

private extension SourceManagementScreenController {
    func loadAddFeedContext(dependencies: AppDependencies) {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            dependencies.logger.error("Skipped add-feed folder context loading because source management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyAddFeedFolderContext(folders: folders)
        } catch {
            dependencies.logger.error("Failed to load folder context for add-feed flow: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    func loadCreateFolderContext(dependencies: AppDependencies) {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            let unavailableMessage = "Folder creation is unavailable in the current app environment."
            dependencies.logger.error("Skipped create-folder context loading because source management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(message: unavailableMessage)
            return
        }

        do {
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyCreateFolderContext(folders: folders)
        } catch {
            dependencies.logger.error("Failed to load folder context for source management screen: \(error)")
            screenState.applyCreateFolderFailure(
                "Unable to load existing folders right now. Try again."
            )
        }
    }

    func loadMoveSourceContext(dependencies: AppDependencies) {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            dependencies.logger.error("Skipped move-source context loading because source management service is unavailable")
            screenState.applyMoveSourceContext(feeds: [], folders: [])
            screenState.applyMoveSourceFailure(
                "Source moves are unavailable in the current app environment."
            )
            return
        }

        do {
            let feeds = try sourceManagementService.fetchFeeds()
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyMoveSourceContext(feeds: feeds, folders: folders)
        } catch {
            dependencies.logger.error("Failed to load move-source context for source management screen: \(error)")
            screenState.applyMoveSourceContext(feeds: [], folders: [])
            screenState.applyMoveSourceFailure(
                "Unable to load existing sources right now. Try again."
            )
        }
    }

    func createFolderErrorMessage(_ error: SourceManagementServiceError) -> String {
        switch error {
        case .emptyFolderName:
            return "Enter a folder name to continue."
        case .duplicateFolderName:
            return "A folder with this name already exists."
        case .invalidFeedURL,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .feedNotFound,
                .folderNotFound:
            return "Unable to create the folder right now. Try again."
        }
    }

    func moveSourceErrorMessage(_ error: SourceManagementServiceError) -> String {
        switch error {
        case .feedNotFound:
            return "The selected source no longer exists. Reload the move flow and try again."
        case .folderNotFound:
            return "The selected folder no longer exists. Reload the move flow and choose another destination."
        case .invalidFeedURL,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .emptyFolderName,
                .duplicateFolderName:
            return "Unable to move the source right now. Try again."
        }
    }

    func addFeedCreationUnavailableStatus() -> SourceManagementAddFeedStatusPresentation {
        SourceManagementAddFeedStatusPresentation(
            title: "Feed creation is unavailable",
            kind: .failure,
            detail: "The app cannot save a new source in the current environment."
        )
    }

    func addFeedCreationFailureStatus(
        for error: SourceManagementServiceError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .duplicateFeed:
            return SourceManagementAddFeedStatusPresentation(
                title: "This feed is already in the library",
                kind: .warning,
                detail: "Another source with the same normalized URL was saved before this create step finished."
            )
        case .folderNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: "Destination folder is unavailable",
                kind: .failure,
                detail: "The selected folder no longer exists. Choose another destination and try again."
            )
        case .invalidFeedURL,
                .previewUnavailableForNotModifiedResponse,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: "Feed could not be added",
                kind: .failure,
                detail: "Unable to save the new source right now. Try again."
            )
        }
    }

    func addFeedPreviewUnavailableStatus() -> SourceManagementAddFeedStatusPresentation {
        SourceManagementAddFeedStatusPresentation(
            title: "Feed preview is unavailable",
            kind: .failure,
            detail: "Feed preview is unavailable in the current app environment."
        )
    }

    func addFeedPreviewFailureStatus(for error: Error) -> SourceManagementAddFeedStatusPresentation {
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

    func addFeedPreviewFailureStatus(
        for error: SourceManagementServiceError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .invalidFeedURL:
            return SourceManagementAddFeedStatusPresentation(
                title: "Enter a valid feed URL",
                kind: .failure,
                detail: "Use a full http or https URL before loading the preview."
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

    func addFeedPreviewFailureStatus(
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

    func addFeedPreviewFailureStatus(
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

    func networkFailureDetail(for error: FeedTransportError) -> String {
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
