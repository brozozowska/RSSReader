import Foundation
import Observation

private struct SourceManagementPreviewTimeoutError: Error {}

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
        case .organizeFeed(let feedID):
            dependencies.loadSourceManagementMoveSourceContext(
                selectedFeedID: feedID,
                into: &screenState
            )
            screenState.presentScenario(.moveSource)
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
        if scenarioToRestoreAfterCreateFolder == .addFeed,
           screenState.presentedDestination?.id == .createFolder {
            scenarioToRestoreAfterCreateFolder = nil
            screenState.resetCreateFolderForEntry()
            screenState.presentScenario(.addFeed)
            return
        }

        screenState.dismissPresentedScenario()
    }

    func handleCreateFolderNameChange(_ value: String) {
        screenState.updateCreateFolderNameInput(value)
    }

    func handleAddFeedURLChange(_ value: String) {
        screenState.updateAddFeedURLInput(value)
    }

    func handleAddFeedDisplayNameChange(_ value: String) {
        screenState.updateAddFeedDisplayNameInput(value)
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
        if screenState.shouldPreviewAddFeedBeforeSaving() {
            guard let previewCommand = screenState.beginAddFeedPreviewLoading() else { return }
            await performAddFeedPreview(
                command: previewCommand,
                dependencies: dependencies
            )
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

        guard let previewCommand = screenState.beginAddFeedPreviewLoading() else { return }
        await performAddFeedPreview(
            command: previewCommand,
            dependencies: dependencies
        )
    }

    func handleAddFeedPreviewAction(dependencies: AppDependencies) async {
        guard let previewCommand = screenState.beginAddFeedPreviewLoading() else { return }
        await performAddFeedPreview(
            command: previewCommand,
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
                "Source moves are unavailable right now."
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
                    ? "Folder editing is unavailable right now."
                    : "Folder creation is unavailable right now."
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
                using: appState,
                selectsSavedFeed: false
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
                using: appState,
                selectsSavedFeed: false
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
        command: SourceManagementAddFeedPreviewCommand,
        dependencies: AppDependencies
    ) async {
        guard let sourceManagementService = dependencies.sourceManagementService else {
            dependencies.logger.error("Source management service is unavailable for feed preview")
            screenState.applyAddFeedPreviewFailure(
                SourceManagementScreenStatusMapper.addFeedPreviewUnavailableStatus(),
                command: command
            )
            return
        }

        do {
            let preview = try await withAddFeedPreviewTimeout(seconds: 10) {
                try await sourceManagementService.previewFeed(urlString: command.urlString)
            }
            screenState.applyLoadedAddFeedPreview(preview, command: command)
        } catch is SourceManagementPreviewTimeoutError {
            dependencies.logger.error("Timed out while previewing feed through source management flow")
            screenState.applyAddFeedPreviewFailure(
                SourceManagementScreenStatusMapper.addFeedPreviewFailureStatus(
                    for: .feedDiscoveryFailed(command.urlString)
                ),
                command: command
            )
        } catch {
            dependencies.logger.error("Failed to preview feed through source management flow: \(error)")
            screenState.applyAddFeedPreviewFailure(
                SourceManagementScreenStatusMapper.addFeedPreviewFailureStatus(for: error),
                command: command
            )
        }
    }

    func withAddFeedPreviewTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw SourceManagementPreviewTimeoutError()
            }

            guard let result = try await group.next() else {
                throw SourceManagementPreviewTimeoutError()
            }
            group.cancelAll()
            return result
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
                .duplicateFeedDisplayName,
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
                .duplicateFeedDisplayName,
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
        case .duplicateFeedDisplayName:
            return SourceManagementAddFeedStatusPresentation(
                title: "This display name is already in use",
                kind: .warning,
                detail: "Choose a different source name before saving."
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
            title: "Source preview is unavailable",
            kind: .failure,
            detail: "The app cannot check this source right now."
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
            detail: "Unable to check this source right now. Try again."
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
                detail: "Use a website address or a direct RSS / Atom feed link."
            )
        case .feedDiscoveryFailed:
            return SourceManagementAddFeedStatusPresentation(
                title: "Feed was not found",
                kind: .failure,
                detail: "The app could not find a supported RSS or Atom feed for this address."
            )
        case .previewUnavailableForNotModifiedResponse:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source could not be checked",
                kind: .failure,
                detail: "The source did not send enough information to review it right now."
            )
        case .duplicateFeed,
                .duplicateFeedDisplayName,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound,
                .folderNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: "Preview could not be loaded",
                kind: .failure,
                detail: "Unable to check this source right now. Try again."
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
                detail: "The server returned HTTP \(statusCode), so the app could not read this source."
            )
        case .unsupportedContentType(let contentType):
            let detail: String
            if let contentType, contentType.isEmpty == false {
                detail = "The address responded with \(contentType), not a supported RSS or Atom feed."
            } else {
                detail = "The address responded, but it does not look like a supported RSS or Atom feed."
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
                detail: "The address responded, but there was no feed content to read."
            )
        case .malformedXML:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The address responded, but the app could not read it as RSS or Atom."
            )
        case .unsupportedFeedKind:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The address responded, but it did not contain a supported RSS or Atom feed."
            )
        case .missingRSSElement:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The RSS feed is missing information the app needs before adding it."
            )
        case .missingAtomElement:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The Atom feed is missing information the app needs before adding it."
            )
        }
    }

    static func networkFailureDetail(for error: FeedTransportError) -> String {
        switch error {
        case .timedOut:
            return "The request timed out before the feed preview could be loaded."
        case .cannotFindHost, .dnsLookupFailed:
            return "The host name could not be found for this source."
        case .cannotConnectToHost, .resourceUnavailable:
            return "The app could not connect to this source."
        case .networkConnectionLost:
            return "The network connection was lost while checking this source."
        case .notConnectedToInternet:
            return "Check the internet connection and try again."
        case .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return "The current network settings are blocking this request."
        case .invalidResponse:
            return "The server returned a response the app could not read."
        case .unknown:
            return "The source could not be checked for an unknown network reason."
        }
    }
}
