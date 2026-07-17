import Foundation

extension AppActionRouter {
    @MainActor
    func refreshFeed(id feedID: UUID) async -> FeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }

        let result = await feedRefreshService.refresh(feedID: feedID)
        cleanupArticlesUsingCurrentSettings(scope: .feedIDs([result.feedID]))
        await refreshUnreadAppIconBadgeCount()
        return result
    }

    @MainActor
    func refreshAfterAddingFeed(id feedID: UUID, using appState: AppState) async -> FeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable for feed save completion")
            return nil
        }

        let result = await feedRefreshService.refreshAfterAddingFeed(feedID: feedID)
        cleanupArticlesUsingCurrentSettings(scope: .feedIDs([result.feedID]))
        await refreshUnreadAppIconBadgeCount()
        appState.requestSidebarReload()
        showFeed(id: feedID, using: appState)
        dismissFeedManagement(using: appState)
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
        recordFeedsRefreshIfNeeded(from: result)
        cleanupArticlesUsingCurrentSettings(scope: .allFeeds)
        await refreshUnreadAppIconBadgeCount()
        return result
    }

    @MainActor
    func refreshCurrentFeed(using appState: AppState) async -> FeedRefreshResult? {
        switch appState.selectedSidebarSelection {
        case .feed(let feedID):
            let result = await refreshFeed(id: feedID)
            if result != nil {
                appState.requestArticleListReload()
            }
            return result
        case .inbox, .unread, .starred, .folder, .none:
            logger.info("Skipped feed refresh because the current sidebar selection is not a single feed")
            return nil
        }
    }

    @MainActor
    func refreshCurrentSelection(
        using appState: AppState,
        requestsArticleListReload: Bool = true
    ) async -> FeedRefreshBatchResult? {
        guard let selection = appState.selectedSidebarSelection else {
            logger.info("Skipped selection refresh because no sidebar selection is active")
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
            appState.requestSidebarReload()
            if requestsArticleListReload {
                appState.requestArticleListReload()
            }
        }

        return result
    }

    @MainActor
    func refreshVisibleFeeds(using appState: AppState) async -> FeedRefreshBatchResult? {
        let result = await refreshAllFeeds()
        if result != nil {
            appState.requestSidebarReload()
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
            recordFeedsRefreshIfNeeded(from: refreshResult.batchResult)
            cleanupFeedFetchLogs()
            await refreshUnreadAppIconBadgeCount()
        }
        return result
    }

    @MainActor
    private func recordFeedsRefreshIfNeeded(from result: FeedRefreshBatchResult) {
        guard result.summary.fetchedCount + result.summary.notModifiedCount > 0 else {
            return
        }

        do {
            _ = try appSettingsService?.updateSettings(
                AppSettingsPatch(
                    lastFeedsRefreshAt: result.finishedAt,
                    updatedAt: result.finishedAt
                )
            )
        } catch {
            logger.error("Failed to persist feeds refresh timestamp: \(error)")
        }
    }

    @MainActor
    private func refreshFeeds(in folderName: String) async -> FeedRefreshBatchResult? {
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
            cleanupArticlesUsingCurrentSettings(
                scope: .feedIDs(result.results.map(\.feedID))
            )
            await refreshUnreadAppIconBadgeCount()
            return result
        } catch {
            logger.error("Failed to load folder feeds for refresh: \(error)")
            return nil
        }
    }
}
