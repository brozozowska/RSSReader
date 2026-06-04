import Foundation

extension SourceManagementScreenController {
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
            dependencies.appActions.completeSourceManagementMove(
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
}
