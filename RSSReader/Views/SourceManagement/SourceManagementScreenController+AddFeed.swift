import Foundation

private struct SourceManagementPreviewTimeoutError: Error {}

extension SourceManagementScreenController {
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

    func startCreateFolderFromAddFeed(dependencies: AppDependencies) {
        scenarioToRestoreAfterCreateFolder = .addFeed
        dependencies.appActions.loadSourceManagementCreateFolderContext(into: &screenState)
        screenState.presentScenario(.createFolder)
    }

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
            _ = await dependencies.appActions.completeSourceManagementFeedSave(
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
            _ = await dependencies.appActions.completeSourceManagementFeedSave(
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
}
