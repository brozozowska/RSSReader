import Foundation
import Observation

@MainActor
@Observable
final class SourceManagementScreenController {
    var screenState: SourceManagementScreenState
    let isPreviewMode: Bool

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
            screenState.presentScenario(.addFeed)
        case .createFolder:
            if let dependencies {
                loadCreateFolderContext(dependencies: dependencies)
            }
            screenState.presentScenario(.createFolder)
        case .moveSource:
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

    func prepareAddFeedPreview() {
        guard screenState.addFeedValidationMessage() == nil else { return }
        screenState.prepareAddFeedPreview()
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
}
