import Foundation

extension AppActionRouter {
    @MainActor
    func showFeedManagement(using appState: AppState) {
        appState.presentFeedManagementScreen()
    }

    @MainActor
    func showFeedEditor(id feedID: UUID, using appState: AppState) {
        appState.presentFeedManagementScreen(launchContext: .editFeed(feedID))
    }

    @MainActor
    func showFeedOrganizer(id feedID: UUID, using appState: AppState) {
        appState.presentFeedManagementScreen(launchContext: .organizeFeed(feedID))
    }

    @MainActor
    func showFolderEditor(named folderName: String, using appState: AppState) {
        guard let folderRepository else {
            logger.error("Folder repository is unavailable for folder editing")
            return
        }

        do {
            guard let folder = try folderRepository.fetchFolder(name: folderName) else {
                logger.error("Skipped folder editor presentation because folder \(folderName) was not found")
                return
            }
            appState.presentFeedManagementScreen(launchContext: .editFolder(folder.id))
        } catch {
            logger.error("Failed to resolve folder editor presentation for \(folderName): \(error)")
        }
    }

    @MainActor
    func loadFeedManagementAddFeedContext(
        into screenState: inout FeedManagementScreenState
    ) {
        guard let feedManagementService else {
            logger.error("Skipped add-feed folder context loading because feed management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            let folders = try feedManagementService.fetchFolders()
            screenState.applyAddFeedFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for add-feed flow: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    @MainActor
    func loadFeedManagementAddFeedEditContext(
        feedID: UUID,
        into screenState: inout FeedManagementScreenState
    ) {
        screenState.resetAddFeedForEntry()

        guard let feedManagementService else {
            logger.error("Skipped feed editor context loading because feed management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            guard let feed = try feedManagementService.fetchFeed(id: feedID) else {
                logger.error("Skipped feed editor context loading because feed \(feedID) was not found")
                screenState.applyAddFeedFolderContext(folders: [])
                return
            }

            let folders = try feedManagementService.fetchFolders()
            screenState.applyAddFeedEditContext(feed: feed, folders: folders)
        } catch {
            logger.error("Failed to load feed editor context for feed management screen: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    @MainActor
    func loadFeedManagementCreateFolderContext(
        into screenState: inout FeedManagementScreenState
    ) {
        guard let feedManagementService else {
            logger.error("Skipped create-folder context loading because feed management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: FeedManagementLocalization.folderCreationUnavailableTitle,
                message: FeedManagementLocalization.folderCreationUnavailableMessage
            )
            return
        }

        do {
            let folders = try feedManagementService.fetchFolders()
            screenState.applyCreateFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for feed management screen: \(error)")
            screenState.applyCreateFolderFailure(
                FeedManagementLocalization.existingFoldersLoadFailureMessage
            )
        }
    }

    @MainActor
    func loadFeedManagementCreateFolderEditContext(
        folderID: UUID,
        into screenState: inout FeedManagementScreenState
    ) {
        screenState.resetCreateFolderForEntry()

        guard let feedManagementService else {
            logger.error("Skipped folder editor context loading because feed management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: FeedManagementLocalization.folderEditingUnavailableTitle,
                message: FeedManagementLocalization.folderEditingUnavailableMessage
            )
            return
        }

        do {
            guard let folder = try feedManagementService.fetchFolder(id: folderID) else {
                logger.error("Skipped folder editor context loading because folder \(folderID) was not found")
                return
            }

            let folders = try feedManagementService.fetchFolders()
            screenState.applyCreateFolderEditContext(folder: folder, folders: folders)
        } catch {
            logger.error("Failed to load folder editor context for feed management screen: \(error)")
            screenState.applyCreateFolderFailure(
                FeedManagementLocalization.folderDetailsLoadFailureMessage
            )
        }
    }

    @MainActor
    func loadFeedManagementMoveFeedContext(
        selectedFeedID: UUID? = nil,
        into screenState: inout FeedManagementScreenState
    ) {
        guard let feedManagementService else {
            logger.error("Skipped move-source context loading because feed management service is unavailable")
            screenState.applyMoveFeedContext(feeds: [], folders: [])
            screenState.applyMoveFeedFailure(
                FeedManagementLocalization.feedMovesEnvironmentUnavailableMessage
            )
            return
        }

        do {
            let feeds = try feedManagementService.fetchFeeds()
            let folders = try feedManagementService.fetchFolders()
            screenState.applyMoveFeedContext(
                feeds: feeds,
                folders: folders,
                selectedFeedID: selectedFeedID
            )
        } catch {
            logger.error("Failed to load move-source context for feed management screen: \(error)")
            screenState.applyMoveFeedContext(feeds: [], folders: [])
            screenState.applyMoveFeedFailure(
                FeedManagementLocalization.existingFeedsLoadFailureMessage
            )
        }
    }

    @MainActor
    func restoreAddFeedAfterCreatingFolder(
        _ folder: FeedManagementFolderSummary,
        into screenState: inout FeedManagementScreenState
    ) {
        loadFeedManagementAddFeedContext(into: &screenState)
        screenState.selectAddFeedFolderPlacement(.folder(folder.id))
        screenState.presentScenario(.addFeed)
    }

    @MainActor
    func finishFolderEditing(
        previousName: String,
        updatedFolderName: String,
        using appState: AppState
    ) {
        appState.requestSidebarReload()
        if appState.selectedSidebarSelection == .folder(previousName) {
            showFolder(named: updatedFolderName, using: appState)
        }
        dismissFeedManagement(using: appState)
    }

    @MainActor
    func finishCreatingFolder(named folderName: String, using appState: AppState) {
        logger.info("Finished feed management folder creation for \(folderName)")
        appState.requestSidebarReload()
    }

    @MainActor
    func finishMovingSource(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState
    ) {
        appState.requestSidebarReload()

        switch appState.selectedSidebarSelection {
        case .feed(let selectedFeedID):
            if selectedFeedID == feedID {
                appState.requestArticleListReload()
            }
        case .folder(let folderName):
            if folderName == previousFolderName || folderName == updatedFolderName {
                appState.requestArticleListReload()
            }
        case .inbox, .unread, .starred, .none:
            break
        }

        dismissFeedManagement(using: appState)
    }

    @MainActor
    func finishSavingFeed(
        id feedID: UUID,
        using appState: AppState,
        selectsSavedFeed: Bool = true
    ) async -> FeedRefreshResult? {
        appState.requestSourceIconNetworkLoad(for: feedID)
        appState.requestSidebarReload()
        if selectsSavedFeed {
            showFeed(id: feedID, using: appState)
        } else {
            appState.selectSidebarSelection(nil)
        }
        dismissFeedManagement(using: appState)
        scheduleInitialRefreshAfterSavingFeed(id: feedID, using: appState)
        return nil
    }

    func waitForScheduledFeedSaveRefreshes() async {
        await feedSaveRefreshTaskStore?.waitForAll()
    }

    @MainActor
    func completeFeedManagementFolderEditing(
        previousName: String?,
        updatedFolderName: String,
        using appState: AppState?
    ) {
        guard let appState, let previousName else { return }
        finishFolderEditing(
            previousName: previousName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func completeFeedManagementFolderCreation(
        named folderName: String,
        using appState: AppState?
    ) {
        guard let appState else { return }
        finishCreatingFolder(named: folderName, using: appState)
    }

    @MainActor
    func completeFeedManagementMove(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState?
    ) {
        guard let appState else { return }
        finishMovingSource(
            feedID: feedID,
            previousFolderName: previousFolderName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func completeFeedManagementFeedSave(
        id feedID: UUID,
        using appState: AppState?,
        selectsSavedFeed: Bool
    ) async -> FeedRefreshResult? {
        guard let appState else { return nil }
        return await finishSavingFeed(
            id: feedID,
            using: appState,
            selectsSavedFeed: selectsSavedFeed
        )
    }

    @MainActor
    func finishUnsubscribingFeed(id feedID: UUID, using appState: AppState) {
        appState.requestSidebarReload()
        if appState.selectedSidebarSelection == .feed(feedID) {
            showInbox(using: appState)
        } else {
            appState.requestArticleListReload()
        }
    }

    @MainActor
    func finishDeletingFolder(named folderName: String, using appState: AppState) {
        appState.requestSidebarReload()
        if appState.selectedSidebarSelection == .folder(folderName) {
            showInbox(using: appState)
        } else {
            appState.requestArticleListReload()
        }
    }

    @MainActor
    func unsubscribeFeed(id feedID: UUID, using appState: AppState) {
        guard let feedManagementService else {
            logger.error("Source management service is unavailable for feed deletion")
            return
        }

        do {
            try feedManagementService.deleteFeed(id: feedID)
            finishUnsubscribingFeed(id: feedID, using: appState)
            scheduleUnreadAppIconBadgeRefresh()
        } catch {
            logger.error("Failed to unsubscribe feed \(feedID): \(error)")
        }
    }

    @MainActor
    func deleteFolder(named folderName: String, using appState: AppState) {
        guard let folderRepository else {
            logger.error("Folder repository is unavailable for folder deletion")
            return
        }
        guard let feedManagementService else {
            logger.error("Source management service is unavailable for folder deletion")
            return
        }

        do {
            guard let folder = try folderRepository.fetchFolder(name: folderName) else {
                logger.error("Skipped folder deletion because folder \(folderName) was not found")
                return
            }
            try feedManagementService.deleteFolder(id: folder.id)
            finishDeletingFolder(named: folderName, using: appState)
        } catch {
            logger.error("Failed to delete folder \(folderName): \(error)")
        }
    }

    @MainActor
    func dismissFeedManagement(using appState: AppState) {
        appState.dismissFeedManagementScreen()
    }

    @MainActor
    private func scheduleInitialRefreshAfterSavingFeed(
        id feedID: UUID,
        using appState: AppState
    ) {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable for source save completion")
            return
        }

        let task = Task { @MainActor in
            _ = await feedRefreshService.refreshAfterAddingFeed(feedID: feedID)
            await refreshUnreadAppIconBadgeCount()
            appState.requestSidebarReload()
            appState.requestArticleListReload()
        }
        feedSaveRefreshTaskStore?.append(task)
    }
}
