import Foundation

extension FeedManagementScreenController {
    func handleMoveFeedFeedSelection(_ feedID: UUID) {
        screenState.selectMoveFeedFeed(feedID)
    }

    func handleMoveFeedPlacementSelection(
        _ placement: FeedManagementFolderPlacement
    ) {
        screenState.selectMoveFeedPlacement(placement)
    }

    func submitMoveFeed(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        guard let feedManagementService = dependencies.feedManagementService else {
            let unavailableMessage = "Feed management service is unavailable for feed moves."
            dependencies.logger.error(unavailableMessage)
            screenState.applyMoveFeedFailure(
                FeedManagementLocalization.feedMovesUnavailableMessage
            )
            return
        }

        guard let moveCommand = screenState.moveFeedCommand() else {
            screenState.applyMoveFeedFailure(
                FeedManagementLocalization.feedMoveSelectionRequiredMessage
            )
            return
        }

        screenState.beginMoveFeedSubmission()
        performMoveFeed(
            moveCommand,
            using: feedManagementService,
            dependencies: dependencies,
            appState: appState
        )
    }

    func performMoveFeed(
        _ moveCommand: FeedManagementMoveFeedCommand,
        using feedManagementService: FeedManagementService,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        do {
            let previousFeed = screenState.selectedMoveFeedFeed()
            let movedFeed = try feedManagementService.moveFeed(moveCommand)
            screenState.applyMovedFeed(movedFeed)
            dependencies.appActions.completeFeedManagementMove(
                feedID: movedFeed.id,
                previousFolderName: previousFeed?.folderName,
                updatedFolderName: movedFeed.folderName,
                using: appState
            )
        } catch let error as FeedManagementServiceError {
            dependencies.logger.error("Failed to move feed through feed management flow: \(error)")
            screenState.applyMoveFeedFailure(
                FeedManagementScreenStatusMapper.moveFeedErrorMessage(error)
            )
        } catch {
            dependencies.logger.error("Failed to move feed through feed management flow: \(error)")
            screenState.applyMoveFeedFailure(
                FeedManagementLocalization.feedMoveGenericFailure
            )
        }
    }
}
