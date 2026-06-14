import Foundation

extension SourceManagementScreenController {
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

        guard let sourceManagementService = dependencies.sourceManagementService else {
            let unavailableMessage = "Source management service is unavailable for folder creation."
            dependencies.logger.error(unavailableMessage)
            screenState.applyCreateFolderServiceUnavailable(
                title: screenState.isEditingCreateFolder()
                    ? String(localized: "sourceManagement.createFolder.unavailable.edit.title", defaultValue: "Folder editing is unavailable", comment: "Failure title when folder editing service is unavailable.")
                    : String(localized: "sourceManagement.createFolder.unavailable.create.title", defaultValue: "Folder creation is unavailable", comment: "Failure title when folder creation service is unavailable."),
                message: screenState.isEditingCreateFolder()
                    ? String(localized: "sourceManagement.createFolder.unavailable.edit.detail", defaultValue: "Folder editing is unavailable right now.", comment: "Failure detail when folder editing service is unavailable.")
                    : SourceManagementLocalization.folderCreationUnavailableValidation
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
            dependencies.appActions.completeSourceManagementFolderEditing(
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
                String(localized: "sourceManagement.createFolder.error.updateGeneric", defaultValue: "Unable to update the folder right now. Try again.", comment: "Generic update folder error message.")
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
            dependencies.appActions.completeSourceManagementFolderCreation(
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
        } catch let error as SourceManagementServiceError {
            dependencies.logger.error("Failed to create folder through source management flow: \(error)")
            screenState.applyCreateFolderFailure(
                SourceManagementScreenStatusMapper.createFolderErrorMessage(error)
            )
        } catch {
            dependencies.logger.error("Failed to create folder through source management flow: \(error)")
            screenState.applyCreateFolderFailure(
                String(localized: "sourceManagement.createFolder.error.generic", defaultValue: "Unable to create the folder right now. Try again.", comment: "Generic create folder error message.")
            )
        }
    }
}
