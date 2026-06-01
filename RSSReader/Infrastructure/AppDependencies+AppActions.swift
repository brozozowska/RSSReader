import Foundation

extension AppDependencies {
    @MainActor
    func showInbox(using appState: AppState) {
        appState.selectReadingSource(.inbox)
    }

    @MainActor
    func showUnread(using appState: AppState) {
        appState.selectReadingSource(.unread)
    }

    @MainActor
    func showStarred(using appState: AppState) {
        appState.selectReadingSource(.starred)
    }

    @MainActor
    func showFeed(id feedID: UUID, using appState: AppState) {
        appState.selectReadingSource(.feed(feedID))
    }

    @MainActor
    func showFolder(named folderName: String, using appState: AppState) {
        appState.selectReadingSource(.folder(folderName))
    }

    @MainActor
    func selectArticle(id articleID: UUID?, using appState: AppState) {
        guard let articleID else {
            appState.selectedArticleID = nil
            return
        }

        guard shouldPresentSelectedArticleInSafariByDefault() else {
            appState.selectedArticleID = articleID
            return
        }

        guard let articleQueryService else {
            logger.error("Article query service is unavailable for default reader mode policy")
            appState.selectedArticleID = articleID
            return
        }

        do {
            guard let article = try articleQueryService.fetchReaderArticle(id: articleID) else {
                logger.error("Skipped default Safari presentation because article \(articleID) was not found")
                appState.selectedArticleID = articleID
                return
            }

            guard openArticleInSafari(article, using: appState) else {
                appState.selectedArticleID = articleID
                return
            }
        } catch {
            logger.error("Failed to apply default reader mode policy for article \(articleID): \(error)")
            appState.selectedArticleID = articleID
        }
    }

    @MainActor
    func applySourcesFilter(_ filter: SourcesFilter, using appState: AppState) {
        appState.selectSourcesFilter(filter)
    }

    @MainActor
    @discardableResult
    func openArticleInSafari(_ article: ReaderArticleDTO, using appState: AppState) -> Bool {
        guard let url = URL(string: article.canonicalURL ?? article.articleURL) else {
            logger.error("Skipped opening article in Safari because URL is invalid for article \(article.id)")
            return false
        }

        guard appState.presentSafari(articleID: article.id, url: url) else {
            logger.error("Skipped opening article in Safari because URL is unsupported for article \(article.id)")
            return false
        }

        return true
    }

    @MainActor
    func openArticleBodyLink(_ url: URL, articleID: UUID, using appState: AppState) {
        guard appState.presentSafari(articleID: articleID, url: url) else {
            logger.error("Skipped opening article body link in Safari because URL is unsupported for article \(articleID)")
            return
        }
    }

    @MainActor
    func closePresentedArticleSafari(using appState: AppState) {
        appState.dismissPresentedSafari()
    }

    @MainActor
    func showSettings(using appState: AppState) {
        appState.presentSettingsScreen()
    }

    @MainActor
    func dismissSettings(using appState: AppState) {
        appState.dismissSettingsScreen()
    }

    @MainActor
    func showSourceManagement(using appState: AppState) {
        appState.presentSourceManagementScreen()
    }

    @MainActor
    func showFeedEditor(id feedID: UUID, using appState: AppState) {
        appState.presentSourceManagementScreen(launchContext: .editFeed(feedID))
    }

    @MainActor
    func showFeedOrganizer(id feedID: UUID, using appState: AppState) {
        appState.presentSourceManagementScreen(launchContext: .organizeFeed(feedID))
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
            appState.presentSourceManagementScreen(launchContext: .editFolder(folder.id))
        } catch {
            logger.error("Failed to resolve folder editor presentation for \(folderName): \(error)")
        }
    }

    @MainActor
    func loadSourceManagementAddFeedContext(
        into screenState: inout SourceManagementScreenState
    ) {
        guard let sourceManagementService else {
            logger.error("Skipped add-feed folder context loading because source management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyAddFeedFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for add-feed flow: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    @MainActor
    func loadSourceManagementAddFeedEditContext(
        feedID: UUID,
        into screenState: inout SourceManagementScreenState
    ) {
        screenState.resetAddFeedForEntry()

        guard let sourceManagementService else {
            logger.error("Skipped feed editor context loading because source management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            guard let feed = try sourceManagementService.fetchFeed(id: feedID) else {
                logger.error("Skipped feed editor context loading because feed \(feedID) was not found")
                screenState.applyAddFeedFolderContext(folders: [])
                return
            }

            let folders = try sourceManagementService.fetchFolders()
            screenState.applyAddFeedEditContext(feed: feed, folders: folders)
        } catch {
            logger.error("Failed to load feed editor context for source management screen: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    @MainActor
    func loadSourceManagementCreateFolderContext(
        into screenState: inout SourceManagementScreenState
    ) {
        guard let sourceManagementService else {
            let unavailableMessage = "Folder creation is unavailable in the current app environment."
            logger.error("Skipped create-folder context loading because source management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: "Folder creation is unavailable",
                message: unavailableMessage
            )
            return
        }

        do {
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyCreateFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for source management screen: \(error)")
            screenState.applyCreateFolderFailure(
                "Unable to load existing folders right now. Try again."
            )
        }
    }

    @MainActor
    func loadSourceManagementCreateFolderEditContext(
        folderID: UUID,
        into screenState: inout SourceManagementScreenState
    ) {
        screenState.resetCreateFolderForEntry()

        guard let sourceManagementService else {
            let unavailableMessage = "Folder editing is unavailable in the current app environment."
            logger.error("Skipped folder editor context loading because source management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: "Folder editing is unavailable",
                message: unavailableMessage
            )
            return
        }

        do {
            guard let folder = try sourceManagementService.fetchFolder(id: folderID) else {
                logger.error("Skipped folder editor context loading because folder \(folderID) was not found")
                return
            }

            let folders = try sourceManagementService.fetchFolders()
            screenState.applyCreateFolderEditContext(folder: folder, folders: folders)
        } catch {
            logger.error("Failed to load folder editor context for source management screen: \(error)")
            screenState.applyCreateFolderFailure(
                "Unable to load the folder details right now. Try again."
            )
        }
    }

    @MainActor
    func loadSourceManagementMoveSourceContext(
        selectedFeedID: UUID? = nil,
        into screenState: inout SourceManagementScreenState
    ) {
        guard let sourceManagementService else {
            logger.error("Skipped move-source context loading because source management service is unavailable")
            screenState.applyMoveSourceContext(feeds: [], folders: [])
            screenState.applyMoveSourceFailure(
                "Source moves are unavailable in the current app environment."
            )
            return
        }

        do {
            let feeds = try sourceManagementService.fetchFeeds()
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyMoveSourceContext(
                feeds: feeds,
                folders: folders,
                selectedFeedID: selectedFeedID
            )
        } catch {
            logger.error("Failed to load move-source context for source management screen: \(error)")
            screenState.applyMoveSourceContext(feeds: [], folders: [])
            screenState.applyMoveSourceFailure(
                "Unable to load existing sources right now. Try again."
            )
        }
    }

    @MainActor
    func restoreAddFeedAfterCreatingFolder(
        _ folder: SourceManagementFolderSummary,
        into screenState: inout SourceManagementScreenState
    ) {
        loadSourceManagementAddFeedContext(into: &screenState)
        screenState.selectAddFeedFolderPlacement(.folder(folder.id))
        screenState.presentScenario(.addFeed)
    }

    @MainActor
    func finishFolderEditing(
        previousName: String,
        updatedFolderName: String,
        using appState: AppState
    ) {
        appState.requestSourcesSidebarReload()
        if appState.selectedSidebarSelection == .folder(previousName) {
            showFolder(named: updatedFolderName, using: appState)
        }
        dismissSourceManagement(using: appState)
    }

    @MainActor
    func finishCreatingFolder(named folderName: String, using appState: AppState) {
        logger.info("Finished source management folder creation for \(folderName)")
        appState.requestSourcesSidebarReload()
    }

    @MainActor
    func finishMovingSource(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState
    ) {
        appState.requestSourcesSidebarReload()

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

        dismissSourceManagement(using: appState)
    }

    @MainActor
    func finishSavingFeed(
        id feedID: UUID,
        using appState: AppState,
        selectsSavedFeed: Bool = true
    ) async -> FeedRefreshResult? {
        appState.requestSourceIconNetworkLoad(for: feedID)
        appState.requestSourcesSidebarReload()
        if selectsSavedFeed {
            showFeed(id: feedID, using: appState)
        } else {
            appState.selectReadingSource(nil)
        }
        dismissSourceManagement(using: appState)
        scheduleInitialRefreshAfterSavingFeed(id: feedID, using: appState)
        return nil
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
            appState.requestSourcesSidebarReload()
            appState.requestArticleListReload()
        }
        feedSaveRefreshTaskStore?.append(task)
    }

    func waitForScheduledFeedSaveRefreshes() async {
        await feedSaveRefreshTaskStore?.waitForAll()
    }

    @MainActor
    func completeSourceManagementFolderEditing(
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
    func completeSourceManagementFolderCreation(
        named folderName: String,
        using appState: AppState?
    ) {
        guard let appState else { return }
        finishCreatingFolder(named: folderName, using: appState)
    }

    @MainActor
    func completeSourceManagementMove(
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
    func completeSourceManagementFeedSave(
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
        appState.requestSourcesSidebarReload()
        if appState.selectedSidebarSelection == .feed(feedID) {
            showInbox(using: appState)
        } else {
            appState.requestArticleListReload()
        }
    }

    @MainActor
    func finishDeletingFolder(named folderName: String, using appState: AppState) {
        appState.requestSourcesSidebarReload()
        if appState.selectedSidebarSelection == .folder(folderName) {
            showInbox(using: appState)
        } else {
            appState.requestArticleListReload()
        }
    }

    @MainActor
    func unsubscribeFeed(id feedID: UUID, using appState: AppState) {
        guard let sourceManagementService else {
            logger.error("Source management service is unavailable for feed deletion")
            return
        }

        do {
            try sourceManagementService.deleteFeed(id: feedID)
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
        guard let sourceManagementService else {
            logger.error("Source management service is unavailable for folder deletion")
            return
        }

        do {
            guard let folder = try folderRepository.fetchFolder(name: folderName) else {
                logger.error("Skipped folder deletion because folder \(folderName) was not found")
                return
            }
            try sourceManagementService.deleteFolder(id: folder.id)
            finishDeletingFolder(named: folderName, using: appState)
        } catch {
            logger.error("Failed to delete folder \(folderName): \(error)")
        }
    }

    @MainActor
    func dismissSourceManagement(using appState: AppState) {
        appState.dismissSourceManagementScreen()
    }

    @MainActor
    func refreshFeed(id feedID: UUID) async -> FeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }

        let result = await feedRefreshService.refresh(feedID: feedID)
        cleanupArchivedArticlesUsingCurrentSettings()
        await refreshUnreadAppIconBadgeCount()
        return result
    }

    @MainActor
    func refreshAfterAddingFeed(id feedID: UUID, using appState: AppState) async -> FeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable for source save completion")
            return nil
        }

        let result = await feedRefreshService.refreshAfterAddingFeed(feedID: feedID)
        cleanupArchivedArticlesUsingCurrentSettings()
        await refreshUnreadAppIconBadgeCount()
        appState.requestSourcesSidebarReload()
        showFeed(id: feedID, using: appState)
        dismissSourceManagement(using: appState)
        return result
    }

    @MainActor
    func refreshSelectedFeed(using appState: AppState) async -> FeedRefreshResult? {
        guard let selectedFeedID = appState.selectedFeedID else {
            logger.info("Skipped manual refresh because no feed is selected")
            return nil
        }

        return await refreshFeed(id: selectedFeedID)
    }

    @MainActor
    func refreshAllFeeds() async -> FeedRefreshBatchResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }

        let result = await feedRefreshService.refreshAllActiveFeeds()
        recordSourcesRefreshIfNeeded(from: result)
        cleanupArchivedArticlesUsingCurrentSettings()
        await refreshUnreadAppIconBadgeCount()
        return result
    }

    @MainActor
    func refreshCurrentSource(using appState: AppState) async -> FeedRefreshResult? {
        switch appState.selectedSidebarSelection {
        case .feed(let feedID):
            let result = await refreshFeed(id: feedID)
            if result != nil {
                appState.requestArticleListReload()
            }
            return result
        case .inbox, .unread, .starred, .folder, .none:
            logger.info("Skipped source refresh because the current source is not a single feed")
            return nil
        }
    }

    @MainActor
    func refreshCurrentSelection(
        using appState: AppState,
        requestsArticleListReload: Bool = true
    ) async -> FeedRefreshBatchResult? {
        guard let selection = appState.selectedSidebarSelection else {
            logger.info("Skipped selection refresh because no source is selected")
            return nil
        }

        let result: FeedRefreshBatchResult?
        switch selection {
        case .feed(let feedID):
            if let refreshResult = await refreshFeed(id: feedID) {
                result = FeedRefreshBatchResult(
                    startedAt: refreshResult.startedAt,
                    finishedAt: refreshResult.finishedAt,
                    results: [refreshResult]
                )
            } else {
                result = nil
            }
        case .folder(let folderName):
            result = await refreshFeeds(in: folderName)
        case .inbox, .unread, .starred:
            result = await refreshAllFeeds()
        }

        if result != nil {
            appState.requestSourcesSidebarReload()
            if requestsArticleListReload {
                appState.requestArticleListReload()
            }
        }

        return result
    }

    @MainActor
    func refreshVisibleSources(using appState: AppState) async -> FeedRefreshBatchResult? {
        let result = await refreshAllFeeds()
        if result != nil {
            appState.requestSourceIconReload()
            appState.requestArticleListReload()
        }
        return result
    }

    @MainActor
    func refreshFeedsForBackground() async -> BackgroundRefreshServiceExecutionResult {
        guard let backgroundRefreshService else {
            logger.debug(
                "Background refresh dependencies trace outcome=serviceUnavailable operation=executeBackgroundAppRefresh"
            )
            return .failedToStart(.feedRefreshServiceUnavailable)
        }

        let result = await backgroundRefreshService.performScheduledRefresh()
        if case .executed(let refreshResult) = result {
            recordSourcesRefreshIfNeeded(from: refreshResult.batchResult)
            cleanupPersistenceBoundedGrowth()
            await refreshUnreadAppIconBadgeCount()
        }
        return result
    }

    @MainActor
    private func recordSourcesRefreshIfNeeded(from result: FeedRefreshBatchResult) {
        guard result.summary.fetchedCount + result.summary.notModifiedCount > 0 else {
            return
        }

        do {
            _ = try appSettingsService?.updateSettings(
                AppSettingsPatch(
                    lastSourcesRefreshAt: result.finishedAt,
                    updatedAt: result.finishedAt
                )
            )
        } catch {
            logger.error("Failed to persist sources refresh timestamp: \(error)")
        }
    }

    @MainActor
    @discardableResult
    func cleanupArchivedArticles(
        policy: ArticleRetentionPolicy,
        now: Date = .now
    ) -> ArticleRetentionCleanupResult? {
        guard let articleRetentionCleanupService else {
            logger.debug("Article retention cleanup service is unavailable")
            return nil
        }

        do {
            let result = try articleRetentionCleanupService.cleanupArchivedArticles(policy: policy, now: now)
            cleanupPersistenceBoundedGrowth(now: now)
            return result
        } catch {
            logger.error("Failed to clean up archived articles: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func cleanupArchivedArticlesUsingCurrentSettings(now: Date = .now) -> ArticleRetentionCleanupResult? {
        guard let appSettingsService else {
            logger.debug("App settings service is unavailable for article retention cleanup")
            return nil
        }

        do {
            let settings = try appSettingsService.fetchSettings()
            return cleanupArchivedArticles(policy: settings.articleRetentionPolicy, now: now)
        } catch {
            logger.error("Failed to load article retention settings for cleanup: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func purgeArchivedArticles() -> ArticleArchivePurgeResult? {
        guard let articleRetentionCleanupService else {
            logger.debug("Article retention cleanup service is unavailable for article archive purge")
            return nil
        }

        do {
            let result = try articleRetentionCleanupService.purgeArchivedArticles()
            cleanupPersistenceBoundedGrowth()
            return result
        } catch {
            logger.error("Failed to purge archived articles: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func cleanupPersistenceBoundedGrowth(now: Date = .now) -> PersistenceBoundedGrowthCleanupResult? {
        guard let persistenceBoundedGrowthCleanupService else {
            logger.debug("Persistence bounded growth cleanup service is unavailable")
            return nil
        }

        do {
            return try persistenceBoundedGrowthCleanupService.cleanupBoundedGrowth(now: now)
        } catch {
            logger.error("Failed to clean up bounded persistence growth: \(error)")
            return nil
        }
    }

    @MainActor
    func refreshUnreadAppIconBadgeCount() async {
        guard let unreadAppIconBadgeService else {
            logger.debug("Unread app icon badge service is unavailable")
            return
        }

        await unreadAppIconBadgeService.refreshBadgeCount()
    }

    @MainActor
    func applyUnreadAppIconBadgePreference(isEnabled: Bool) {
        guard let unreadAppIconBadgeService else {
            logger.debug("Unread app icon badge service is unavailable")
            return
        }

        Task { @MainActor in
            await unreadAppIconBadgeService.applyBadgePreference(isEnabled: isEnabled)
        }
    }
}

private extension AppDependencies {
    @MainActor
    func shouldPresentSelectedArticleInSafariByDefault() -> Bool {
        guard let appSettingsService else {
            return false
        }

        do {
            return try appSettingsService.fetchSettings().defaultReaderMode == .browser
        } catch {
            logger.error("Failed to load app settings for default reader mode policy: \(error)")
            return false
        }
    }
    @MainActor
    func refreshFeeds(in folderName: String) async -> FeedRefreshBatchResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }
        guard let feedRepository else {
            logger.error("Feed repository is unavailable")
            return nil
        }

        do {
            let folderFeedIDs = try feedRepository.fetchActiveFeeds()
                .filter { $0.folder?.name == folderName }
                .map(\.id)
            let result = await feedRefreshService.refreshFeeds(folderFeedIDs)
            cleanupArchivedArticlesUsingCurrentSettings()
            await refreshUnreadAppIconBadgeCount()
            return result
        } catch {
            logger.error("Failed to load folder feeds for refresh: \(error)")
            return nil
        }
    }

    @MainActor
    func scheduleUnreadAppIconBadgeRefresh() {
        Task { @MainActor in
            await refreshUnreadAppIconBadgeCount()
        }
    }
}
