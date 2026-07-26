import Foundation

private struct FeedManagementPreviewTimeoutError: Error {}

extension FeedManagementScreenController {
    func handleAddFeedURLChange(_ value: String) {
        screenState.updateAddFeedURLInput(value)
    }

    func handleAddFeedDisplayNameChange(_ value: String) {
        screenState.updateAddFeedDisplayNameInput(value)
    }

    func handleAddFeedFolderPlacementSelection(
        _ placement: FeedManagementFolderPlacement
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
        dependencies.appActions.loadFeedManagementCreateFolderContext(into: &screenState)
        screenState.presentScenario(.createFolder)
    }

    func performAddFeedUpdate(
        _ updateCommand: FeedManagementUpdateFeedCommand,
        dependencies: AppDependencies,
        appState: AppState?
    ) async {
        guard let feedManagementService = dependencies.feedManagementService else {
            dependencies.logger.error("Feed management service is unavailable for feed updates")
            screenState.applyAddFeedCreationFailure(
                FeedManagementScreenStatusMapper.addFeedSaveUnavailableStatus(isEditing: true)
            )
            return
        }

        do {
            let updatedFeed = try feedManagementService.updateFeed(updateCommand)
            screenState.applyCreatedAddFeed(updatedFeed)
            _ = await dependencies.appActions.completeFeedManagementFeedSave(
                id: updatedFeed.id,
                using: appState,
                selectsSavedFeed: false
            )
        } catch let error as FeedManagementServiceError {
            dependencies.logger.error("Failed to update feed through feed management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                FeedManagementScreenStatusMapper.addFeedSaveFailureStatus(
                    for: error,
                    isEditing: true
                )
            )
        } catch {
            dependencies.logger.error("Failed to update feed through feed management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                FeedManagementAddFeedStatusPresentation(
                    title: String(localized: "feedManagement.addFeed.save.editFailed.title", defaultValue: "Feed changes could not be saved", comment: "Generic failure title after feed edit save fails."),
                    kind: .failure,
                    detail: String(localized: "feedManagement.addFeed.save.editFailed.detail", defaultValue: "Unable to save the feed changes right now. Try again.", comment: "Generic failure detail after feed edit save fails.")
                )
            )
        }
    }

    func performAddFeedCreation(
        _ createCommand: FeedManagementCreateFeedCommand,
        dependencies: AppDependencies,
        appState: AppState?
    ) async {
        guard let feedManagementService = dependencies.feedManagementService else {
            dependencies.logger.error("Feed management service is unavailable for feed creation")
            screenState.applyAddFeedCreationFailure(
                FeedManagementScreenStatusMapper.addFeedSaveUnavailableStatus(isEditing: false)
            )
            return
        }

        do {
            let createdFeed = try feedManagementService.createFeed(createCommand)
            screenState.applyCreatedAddFeed(createdFeed)
            _ = await dependencies.appActions.completeFeedManagementFeedSave(
                id: createdFeed.id,
                using: appState,
                selectsSavedFeed: false
            )
        } catch let error as FeedManagementServiceError {
            dependencies.logger.error("Failed to create feed through feed management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                FeedManagementScreenStatusMapper.addFeedSaveFailureStatus(
                    for: error,
                    isEditing: false
                )
            )
        } catch {
            dependencies.logger.error("Failed to create feed through feed management flow: \(error)")
            screenState.applyAddFeedCreationFailure(
                FeedManagementAddFeedStatusPresentation(
                    title: String(localized: "feedManagement.addFeed.save.addFailed.title", defaultValue: "Feed could not be added", comment: "Generic failure title after feed create save fails."),
                    kind: .failure,
                    detail: String(localized: "feedManagement.addFeed.save.addFailed.detail", defaultValue: "Unable to save the new feed right now. Try again.", comment: "Generic failure detail after feed create save fails.")
                )
            )
        }
    }

    func performAddFeedPreview(
        command: FeedManagementAddFeedPreviewCommand,
        dependencies: AppDependencies,
        timeout: Duration = .seconds(10)
    ) async {
        guard let feedManagementService = dependencies.feedManagementService else {
            dependencies.logger.error("Feed management service is unavailable for feed preview")
            screenState.applyAddFeedPreviewFailure(
                FeedManagementScreenStatusMapper.addFeedPreviewUnavailableStatus(),
                command: command
            )
            return
        }

        do {
            let preview = try await withAddFeedPreviewTimeout(timeout: timeout) {
                try await feedManagementService.previewFeed(urlString: command.urlString)
            }
            screenState.applyLoadedAddFeedPreview(preview, command: command)
        } catch is CancellationError {
            screenState.cancelAddFeedPreviewLoading(command: command)
        } catch is FeedManagementPreviewTimeoutError {
            dependencies.logger.error("Timed out while previewing feed through feed management flow")
            screenState.applyAddFeedPreviewFailure(
                FeedManagementScreenStatusMapper.addFeedPreviewFailureStatus(
                    for: .feedDiscoveryFailed(command.urlString)
                ),
                command: command
            )
        } catch {
            dependencies.logger.error("Failed to preview feed through feed management flow: \(error)")
            screenState.applyAddFeedPreviewFailure(
                FeedManagementScreenStatusMapper.addFeedPreviewFailureStatus(for: error),
                command: command
            )
        }
    }

    func withAddFeedPreviewTimeout<T>(
        timeout: Duration,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw FeedManagementPreviewTimeoutError()
            }

            guard let result = try await group.next() else {
                throw FeedManagementPreviewTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}
