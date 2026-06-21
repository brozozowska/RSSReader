import Foundation

extension FeedManagementScreenController {
    func handleLaunchContext(
        _ launchContext: FeedManagementScreenLaunchContext,
        dependencies: AppDependencies
    ) {
        guard isPreviewMode == false else { return }

        switch launchContext {
        case .entry:
            return
        case .editFeed(let feedID):
            dependencies.appActions.loadFeedManagementAddFeedEditContext(
                feedID: feedID,
                into: &screenState
            )
            screenState.presentScenario(.addFeed)
        case .editFolder(let folderID):
            dependencies.appActions.loadFeedManagementCreateFolderEditContext(
                folderID: folderID,
                into: &screenState
            )
            screenState.presentScenario(.createFolder)
        case .organizeFeed(let feedID):
            dependencies.appActions.loadFeedManagementMoveFeedContext(
                selectedFeedID: feedID,
                into: &screenState
            )
            screenState.presentScenario(.moveFeed)
        }
    }

    func handleScenarioSelection(
        _ scenarioID: FeedManagementScenarioID,
        dependencies: AppDependencies? = nil
    ) {
        switch scenarioID {
        case .addFeed:
            screenState.resetAddFeedForEntry()
            if let dependencies {
                dependencies.appActions.loadFeedManagementAddFeedContext(into: &screenState)
            }
            screenState.presentScenario(.addFeed)
        case .createFolder:
            scenarioToRestoreAfterCreateFolder = nil
            screenState.resetCreateFolderForEntry()
            if let dependencies {
                dependencies.appActions.loadFeedManagementCreateFolderContext(into: &screenState)
            }
            screenState.presentScenario(.createFolder)
        case .moveFeed:
            if let dependencies {
                dependencies.appActions.loadFeedManagementMoveFeedContext(into: &screenState)
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
}
