import Foundation

extension SourceManagementScreenController {
    func handleLaunchContext(
        _ launchContext: SourceManagementScreenLaunchContext,
        dependencies: AppDependencies
    ) {
        guard isPreviewMode == false else { return }

        switch launchContext {
        case .entry:
            return
        case .editFeed(let feedID):
            dependencies.appActions.loadSourceManagementAddFeedEditContext(
                feedID: feedID,
                into: &screenState
            )
            screenState.presentScenario(.addFeed)
        case .editFolder(let folderID):
            dependencies.appActions.loadSourceManagementCreateFolderEditContext(
                folderID: folderID,
                into: &screenState
            )
            screenState.presentScenario(.createFolder)
        case .organizeFeed(let feedID):
            dependencies.appActions.loadSourceManagementMoveSourceContext(
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
                dependencies.appActions.loadSourceManagementAddFeedContext(into: &screenState)
            }
            screenState.presentScenario(.addFeed)
        case .createFolder:
            scenarioToRestoreAfterCreateFolder = nil
            screenState.resetCreateFolderForEntry()
            if let dependencies {
                dependencies.appActions.loadSourceManagementCreateFolderContext(into: &screenState)
            }
            screenState.presentScenario(.createFolder)
        case .moveSource:
            if let dependencies {
                dependencies.appActions.loadSourceManagementMoveSourceContext(into: &screenState)
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
