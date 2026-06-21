import Foundation

extension FeedManagementScreenController {
    func handleCreateFolderNameChange(_ value: String) {
        screenState.updateCreateFolderNameInput(value)
    }

    func submitCreateFolder(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        if let validationMessage = screenState.createFolderValidationMessage() {
            screenState.applyCreateFolderFailure(validationMessage)
            return
        }

        guard let feedManagementService = dependencies.feedManagementService else {
            let unavailableMessage = "Feed management service is unavailable for folder creation."
            dependencies.logger.error(unavailableMessage)
            screenState.applyCreateFolderServiceUnavailable(
                title: screenState.isEditingCreateFolder()
                    ? FeedManagementLocalization.folderEditingUnavailableTitle
                    : FeedManagementLocalization.folderCreationUnavailableTitle,
                message: screenState.isEditingCreateFolder()
                    ? FeedManagementLocalization.folderEditingUnavailableMessage
                    : FeedManagementLocalization.folderCreationUnavailableValidation
            )
            return
        }

        if let updateCommand = screenState.beginCreateFolderUpdate() {
            performCreateFolderUpdate(
                updateCommand,
                using: feedManagementService,
                dependencies: dependencies,
                appState: appState
            )
            return
        }

        screenState.beginCreateFolderSubmission()
        performCreateFolderCreation(
            using: feedManagementService,
            dependencies: dependencies,
            appState: appState
        )
    }

    func performCreateFolderUpdate(
        _ updateCommand: FeedManagementUpdateFolderCommand,
        using feedManagementService: FeedManagementService,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        let previousFolderName = screenState.createFolderEditingName()

        do {
            let folder = try feedManagementService.updateFolder(updateCommand)
            screenState.applyCreatedFolder(folder)
            dependencies.appActions.completeFeedManagementFolderEditing(
                previousName: previousFolderName,
                updatedFolderName: folder.name,
                using: appState
            )
        } catch let error as FeedManagementServiceError {
            dependencies.logger.error("Failed to update folder through feed management flow: \(error)")
            screenState.applyCreateFolderFailure(
                FeedManagementScreenStatusMapper.createFolderErrorMessage(error)
            )
        } catch {
            dependencies.logger.error("Failed to update folder through feed management flow: \(error)")
            screenState.applyCreateFolderFailure(
                String(localized: "feedManagement.createFolder.error.updateGeneric", defaultValue: "Unable to update the folder right now. Try again.", comment: "Generic update folder error message.")
            )
        }
    }

    func performCreateFolderCreation(
        using feedManagementService: FeedManagementService,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        do {
            let folder = try feedManagementService.createFolder(
                FeedManagementCreateFolderCommand(
                    name: screenState.createFolderNameInput()
                )
            )
            screenState.applyCreatedFolder(folder)
            dependencies.appActions.completeFeedManagementFolderCreation(
                named: folder.name,
                using: appState
            )
            if scenarioToRestoreAfterCreateFolder == .addFeed {
                dependencies.appActions.restoreAddFeedAfterCreatingFolder(
                    folder,
                    into: &screenState
                )
                scenarioToRestoreAfterCreateFolder = nil
            }
        } catch let error as FeedManagementServiceError {
            dependencies.logger.error("Failed to create folder through feed management flow: \(error)")
            screenState.applyCreateFolderFailure(
                FeedManagementScreenStatusMapper.createFolderErrorMessage(error)
            )
        } catch {
            dependencies.logger.error("Failed to create folder through feed management flow: \(error)")
            screenState.applyCreateFolderFailure(
                String(localized: "feedManagement.createFolder.error.generic", defaultValue: "Unable to create the folder right now. Try again.", comment: "Generic create folder error message.")
            )
        }
    }
}
