import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / App Flow")
@MainActor
struct FeedManagementAppFlowTests {
    @Test
    func addFeedServicePipelinePreviewsCreatesPersistsFolderPlacementAndSchedulesInitialRefreshAtAppBoundary() async throws {
        let feedURL = "https://example.com/app-flow-feed.xml"
        let previewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "App Flow Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Preview Only Article",
                itemLink: "https://example.com/articles/preview",
                itemGUID: "preview-only-article",
                itemDescription: "Preview article should not be persisted before app boundary refresh",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let refreshStep = ScriptedHTTPClient.Step.delayedResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "App Flow Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Persisted Refresh Article",
                itemLink: "https://example.com/articles/refreshed",
                itemGUID: "persisted-refresh-article",
                itemDescription: "Refresh article should be persisted after app boundary refresh",
                pubDate: "Tue, 02 Jan 2024 11:00:00 GMT"
            ),
            delayNanoseconds: 200_000_000
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: [previewStep, refreshStep])
        )
        let service = try #require(harness.dependencies.feedManagementService)
        let appState = AppState()
        let folder = try service.createFolder(FeedManagementCreateFolderCommand(name: "Tech"))

        let preview = try await service.previewFeed(urlString: feedURL)
        let createdFeed = try service.createFeed(
            FeedManagementCreateFeedCommand(
                preview: preview,
                displayTitleOverride: "My App Flow Feed",
                folderPlacement: .folder(folder.id)
            )
        )
        let persistedFeedBeforeRefresh = try #require(try harness.feedRepository.fetchFeed(id: createdFeed.id))
        let articlesBeforeRefresh = try harness.articleRepository.fetchArticles(feedID: createdFeed.id)

        #expect(preview.requestedURL == feedURL)
        #expect(preview.resolvedFeedURL == feedURL)
        #expect(preview.title == "App Flow Feed")
        #expect(preview.existingFeedID == nil)
        #expect(createdFeed.title == "My App Flow Feed")
        #expect(createdFeed.metadataTitle == "App Flow Feed")
        #expect(createdFeed.folderID == folder.id)
        #expect(createdFeed.folderName == "Tech")
        #expect(persistedFeedBeforeRefresh.url == feedURL)
        #expect(persistedFeedBeforeRefresh.title == "App Flow Feed")
        #expect(persistedFeedBeforeRefresh.displayTitleOverride == "My App Flow Feed")
        #expect(persistedFeedBeforeRefresh.folder?.id == folder.id)
        #expect(persistedFeedBeforeRefresh.lastFetchedAt == nil)
        #expect(persistedFeedBeforeRefresh.lastSuccessfulFetchAt == nil)
        #expect(articlesBeforeRefresh.isEmpty)

        _ = await harness.dependencies.appActions.completeFeedManagementFeedSave(
            id: createdFeed.id,
            using: appState,
            selectsSavedFeed: false
        )

        let persistedFeedDuringScheduledRefresh = try #require(try harness.feedRepository.fetchFeed(id: createdFeed.id))
        let articlesDuringScheduledRefresh = try harness.articleRepository.fetchArticles(feedID: createdFeed.id)
        #expect(persistedFeedDuringScheduledRefresh.lastFetchedAt == nil)
        #expect(persistedFeedDuringScheduledRefresh.lastSuccessfulFetchAt == nil)
        #expect(articlesDuringScheduledRefresh.isEmpty)

        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()

        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: createdFeed.id))
        let refreshedArticles = try harness.articleRepository.fetchArticles(feedID: createdFeed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(refreshedArticles.map(\.title) == ["Persisted Refresh Article"])
        #expect(appState.selectedSidebarSelection == nil)
        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(requests.map(\.url.absoluteString) == [feedURL, feedURL])
    }

    @Test
    func initialAndSubsequentRefreshesPublishOnePostRetentionSnapshotForMixedAgeEntries() async throws {
        let feedURL = "https://example.com/initial-refresh-lifecycle.xml"
        let allEntryIDs = Array(1...30)
        let currentEntryIDs = Array(22...30)
        let logger = RecordingLogger()
        let badgeService = RecordingUnreadAppIconBadgeService()
        let client = ScriptedHTTPClient(
            steps: [
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: makeMixedAgeRSSFeedXML(entryIDs: allEntryIDs)
                ),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: makeMixedAgeRSSFeedXML(entryIDs: allEntryIDs)
                ),
                .response(statusCode: 304, headers: [:], body: ""),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: makeMixedAgeRSSFeedXML(entryIDs: currentEntryIDs)
                )
            ]
        )
        let harness = try TestHarness.make(
            httpClient: client,
            unreadAppIconBadgeService: badgeService,
            logger: logger
        )
        let appState = AppState()
        let articleQueryService = try #require(harness.dependencies.articleQueryService)
        let sidebarQueryService = try #require(harness.dependencies.sidebarQueryService)
        let feed = try harness.feedRepository.insert(
            Feed(url: feedURL, title: "Mixed Age Feed", kind: .rss)
        )
        _ = try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleRetentionPolicy: .oneWeek, updatedAt: .distantPast)
        )
        badgeService.onRefreshBadgeCount = {
            let articles = (try? harness.articleRepository.fetchArticles(feedID: feed.id)) ?? []
            let unreadCounts = try? harness.articleStateRepository.fetchUnreadCounts(feedIDs: [feed.id])
            return RefreshSnapshotObservation(
                articleCount: articles.count,
                currentArticleCount: articles.filter { $0.archivedAt == nil }.count,
                unreadCount: unreadCounts?[feed.id],
                sidebarReloadID: appState.sidebarReloadID,
                articleListReloadID: appState.articleListReloadID
            )
        }

        _ = await harness.dependencies.appActions.completeFeedManagementFeedSave(
            id: feed.id,
            using: appState,
            selectsSavedFeed: false
        )
        let sidebarReloadIDBeforeInitialLifecycleCompletion = appState.sidebarReloadID
        let articleReloadIDBeforeInitialLifecycleCompletion = appState.articleListReloadID

        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()

        let initialArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let initialVisibleArticles = try await articleQueryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending
            )
        ).articles
        let initialSidebarSnapshot = try sidebarQueryService.fetchSnapshot()
        let initialBadgeObservation = try #require(badgeService.refreshObservations.first)
        #expect(initialArticles.count == 30)
        #expect(initialArticles.allSatisfy { $0.archivedAt == nil })
        #expect(initialVisibleArticles.count == 30)
        #expect(initialSidebarSnapshot.feeds.first { $0.id == feed.id }?.unreadCount == 30)
        #expect(initialBadgeObservation.articleCount == 30)
        #expect(initialBadgeObservation.currentArticleCount == 30)
        #expect(initialBadgeObservation.unreadCount == 30)
        #expect(initialBadgeObservation.sidebarReloadID == sidebarReloadIDBeforeInitialLifecycleCompletion)
        #expect(initialBadgeObservation.articleListReloadID == articleReloadIDBeforeInitialLifecycleCompletion)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeInitialLifecycleCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeInitialLifecycleCompletion)

        let repeatedFetchedResult = await harness.dependencies.appActions.refreshFeed(id: feed.id)
        let repeatedFetchedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(repeatedFetchedResult?.status == .fetched)
        #expect(repeatedFetchedArticles.count == 30)
        #expect(repeatedFetchedArticles.allSatisfy { $0.archivedAt == nil })

        let notModifiedResult = await harness.dependencies.appActions.refreshFeed(id: feed.id)
        let notModifiedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(notModifiedResult?.status == .notModified)
        #expect(notModifiedArticles.count == 30)
        #expect(notModifiedArticles.allSatisfy { $0.archivedAt == nil })

        let reducedSnapshotResult = await harness.dependencies.appActions.refreshFeed(id: feed.id)
        let reducedSnapshotArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let reducedVisibleArticles = try await articleQueryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending
            )
        ).articles
        let reducedSidebarSnapshot = try sidebarQueryService.fetchSnapshot()
        #expect(reducedSnapshotResult?.status == .fetched)
        #expect(reducedSnapshotResult?.reconciledEntryCount == 21)
        #expect(reducedSnapshotArticles.count == 30)
        #expect(reducedSnapshotArticles.filter { $0.archivedAt == nil }.count == 9)
        #expect(reducedSnapshotArticles.filter { $0.archivedAt != nil }.count == 21)
        #expect(reducedVisibleArticles.count == 30)
        #expect(reducedSidebarSnapshot.feeds.first { $0.id == feed.id }?.unreadCount == 30)
        #expect(badgeService.refreshObservations.map(\.currentArticleCount) == [30, 30, 30, 9])
        #expect(badgeService.refreshObservations.map(\.unreadCount) == [30, 30, 30, 30])

        let lifecycleEntries = logger.entries.filter {
            $0.message.contains("Feed refresh lifecycle completed feed=\(feed.id.uuidString)")
        }
        #expect(lifecycleEntries.count == 4)
        #expect(lifecycleEntries[0].message.contains("status=fetched fetchedEntries=30"))
        #expect(lifecycleEntries[0].message.contains("reconciledEntries=0 deletedByRetention=0"))
        #expect(lifecycleEntries[1].message.contains("status=fetched fetchedEntries=30"))
        #expect(lifecycleEntries[1].message.contains("reconciledEntries=0 deletedByRetention=0"))
        #expect(lifecycleEntries[2].message.contains("status=notModified fetchedEntries=0"))
        #expect(lifecycleEntries[2].message.contains("reconciledEntries=0 deletedByRetention=0"))
        #expect(lifecycleEntries[3].message.contains("status=fetched fetchedEntries=9"))
        #expect(lifecycleEntries[3].message.contains("reconciledEntries=21 deletedByRetention=0"))
    }

    @Test
    func addFeedServicePipelineRejectsDuplicateFeedURLAfterPreviewResolvesExistingFeed() async throws {
        let feedURL = "https://example.com/duplicate-feed.xml"
        let firstPreviewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Duplicate Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "First Article",
                itemLink: "https://example.com/articles/first",
                itemGUID: "first-article",
                itemDescription: "First description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let duplicatePreviewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Duplicate Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Second Article",
                itemLink: "https://example.com/articles/second",
                itemGUID: "second-article",
                itemDescription: "Second description",
                pubDate: "Tue, 02 Jan 2024 11:00:00 GMT"
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: [firstPreviewStep, duplicatePreviewStep])
        )
        let service = try #require(harness.dependencies.feedManagementService)

        let firstPreview = try await service.previewFeed(urlString: feedURL)
        let createdFeed = try service.createFeed(
            FeedManagementCreateFeedCommand(
                preview: firstPreview,
                folderPlacement: .ungrouped
            )
        )
        let duplicatePreview = try await service.previewFeed(urlString: feedURL)

        #expect(duplicatePreview.existingFeedID == createdFeed.id)
        #expect(throws: FeedManagementServiceError.duplicateFeed(feedURL)) {
            _ = try service.createFeed(
                FeedManagementCreateFeedCommand(
                    preview: duplicatePreview,
                    folderPlacement: .ungrouped
                )
            )
        }
        #expect(try harness.feedRepository.fetchAllFeeds().map(\.url) == [feedURL])
    }

    @Test
    func addFeedServicePipelineRejectsDuplicateDisplayTitleWithoutPersistingNewFeed() async throws {
        let existingFeedURL = "https://example.com/existing-title.xml"
        let newFeedURL = "https://example.com/new-title.xml"
        let previewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "New Metadata Title",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "New Article",
                itemLink: "https://example.com/articles/new",
                itemGUID: "new-article",
                itemDescription: "New description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: [previewStep])
        )
        let service = try #require(harness.dependencies.feedManagementService)
        let existingFeed = try #require(try harness.insertFeeds(urls: [existingFeedURL]).first)
        _ = try harness.feedRepository.updateDetails(
            for: existingFeed.id,
            with: FeedDetailsUpdate(displayTitleOverride: "Tech News")
        )

        let preview = try await service.previewFeed(urlString: newFeedURL)

        #expect(throws: FeedManagementServiceError.duplicateFeedDisplayName("tech news")) {
            _ = try service.createFeed(
                FeedManagementCreateFeedCommand(
                    preview: preview,
                    displayTitleOverride: " tech news ",
                    folderPlacement: .ungrouped
                )
            )
        }
        #expect(try harness.feedRepository.fetchFeed(url: newFeedURL) == nil)
        #expect(try harness.feedRepository.fetchAllFeeds().map(\.url) == [existingFeedURL])
    }

    @Test
    func feedManagementPresentationStateUsesSeparateModalFlowAndDoesNotResetReadingShellContext() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.appActions.showFeed(id: feedID, using: appState)
        harness.dependencies.appActions.selectArticle(id: articleID, using: appState)

        harness.dependencies.appActions.showFeedManagement(using: appState)

        #expect(appState.isPresentingFeedManagementScreen)
        #expect(appState.isPresentingSettingsScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))

        harness.dependencies.appActions.dismissFeedManagement(using: appState)

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.isPresentingSettingsScreen == false)
        #expect(appState.feedManagementLaunchContext == .entry)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
    }

    @Test
    func feedManagementPresentationStateTracksSidebarEditLaunchContextWithoutResettingReadingShellContext() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.appActions.showFeed(id: feedID, using: appState)
        harness.dependencies.appActions.selectArticle(id: articleID, using: appState)
        harness.dependencies.appActions.showFeedEditor(id: feedID, using: appState)

        #expect(appState.isPresentingFeedManagementScreen)
        #expect(appState.feedManagementLaunchContext == .editFeed(feedID))
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))

        harness.dependencies.appActions.dismissFeedManagement(using: appState)

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.feedManagementLaunchContext == .entry)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
    }

    @Test
    func feedUnsubscribeRequestCreatesPendingConfirmationWithoutDeletingFeedOrTriggeringSideEffects() throws {
        let badgeService = RecordingUnreadAppIconBadgeService()
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(),
            unreadAppIconBadgeService: badgeService
        )
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/pending-unsubscribe.xml",
                title: "Pending Feed",
                kind: .rss
            )
        )

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        let sidebarReloadIDBeforeRequest = appState.sidebarReloadID
        let articleReloadIDBeforeRequest = appState.articleListReloadID
        let selectedSidebarSelectionBeforeRequest = appState.selectedSidebarSelection

        harness.dependencies.appActions.requestFeedUnsubscribeConfirmation(
            id: feed.id,
            title: feed.displayTitle,
            using: appState
        )

        #expect(appState.pendingFeedUnsubscribeConfirmation?.feedID == feed.id)
        #expect(appState.pendingFeedUnsubscribeConfirmation?.feedTitle == "Pending Feed")
        #expect(try harness.feedRepository.fetchFeed(id: feed.id) != nil)
        #expect(appState.selectedSidebarSelection == selectedSidebarSelectionBeforeRequest)
        #expect(appState.sidebarReloadID == sidebarReloadIDBeforeRequest)
        #expect(appState.articleListReloadID == articleReloadIDBeforeRequest)
        #expect(badgeService.refreshBadgeCountCallCount == 0)

        harness.dependencies.appActions.cancelFeedUnsubscribeConfirmation(using: appState)

        #expect(appState.pendingFeedUnsubscribeConfirmation == nil)
        #expect(try harness.feedRepository.fetchFeed(id: feed.id) != nil)
        #expect(appState.selectedSidebarSelection == selectedSidebarSelectionBeforeRequest)
        #expect(appState.sidebarReloadID == sidebarReloadIDBeforeRequest)
        #expect(appState.articleListReloadID == articleReloadIDBeforeRequest)
        #expect(badgeService.refreshBadgeCountCallCount == 0)
    }

    @Test
    func feedUnsubscribeConfirmationDeletesFeedThroughAppActionBoundary() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/confirmed-unsubscribe.xml",
                title: "Confirmed Feed",
                kind: .rss
            )
        )

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        let sidebarReloadIDBeforeConfirmation = appState.sidebarReloadID
        let articleReloadIDBeforeConfirmation = appState.articleListReloadID

        harness.dependencies.appActions.requestFeedUnsubscribeConfirmation(
            id: feed.id,
            title: feed.displayTitle,
            using: appState
        )
        harness.dependencies.appActions.confirmPendingFeedUnsubscribe(using: appState)

        #expect(appState.pendingFeedUnsubscribeConfirmation == nil)
        #expect(try harness.feedRepository.fetchFeed(id: feed.id) == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeConfirmation)
        #expect(appState.articleListReloadID != articleReloadIDBeforeConfirmation)
    }

    @Test
    func folderDeleteRequestCreatesPendingConfirmationWithoutDeletingFolderOrTriggeringSideEffects() throws {
        let badgeService = RecordingUnreadAppIconBadgeService()
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(),
            unreadAppIconBadgeService: badgeService
        )
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/folder-delete-pending.xml",
                title: "Folder Feed",
                kind: .rss,
                folder: folder
            )
        )

        harness.dependencies.appActions.showFolder(named: "Tech", using: appState)
        let sidebarReloadIDBeforeRequest = appState.sidebarReloadID
        let articleReloadIDBeforeRequest = appState.articleListReloadID
        let selectedSidebarSelectionBeforeRequest = appState.selectedSidebarSelection

        harness.dependencies.appActions.requestFolderDeleteConfirmation(
            named: "Tech",
            using: appState
        )

        let persistedFeedAfterRequest = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(appState.pendingFolderDeleteConfirmation?.folderName == "Tech")
        #expect(try harness.folderRepository.fetchFolder(name: "Tech") != nil)
        #expect(persistedFeedAfterRequest.folder?.name == "Tech")
        #expect(appState.selectedSidebarSelection == selectedSidebarSelectionBeforeRequest)
        #expect(appState.sidebarReloadID == sidebarReloadIDBeforeRequest)
        #expect(appState.articleListReloadID == articleReloadIDBeforeRequest)
        #expect(badgeService.refreshBadgeCountCallCount == 0)

        harness.dependencies.appActions.cancelFolderDeleteConfirmation(using: appState)

        let persistedFeedAfterCancel = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(appState.pendingFolderDeleteConfirmation == nil)
        #expect(try harness.folderRepository.fetchFolder(name: "Tech") != nil)
        #expect(persistedFeedAfterCancel.folder?.name == "Tech")
        #expect(appState.selectedSidebarSelection == selectedSidebarSelectionBeforeRequest)
        #expect(appState.sidebarReloadID == sidebarReloadIDBeforeRequest)
        #expect(appState.articleListReloadID == articleReloadIDBeforeRequest)
        #expect(badgeService.refreshBadgeCountCallCount == 0)
    }

    @Test
    func folderDeleteConfirmationDeletesFolderWithoutDeletingContainedFeeds() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "Design", sortOrder: 0))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/folder-delete-confirmed.xml",
                title: "Design Feed",
                kind: .rss,
                folder: folder
            )
        )

        harness.dependencies.appActions.showFolder(named: "Design", using: appState)
        let sidebarReloadIDBeforeConfirmation = appState.sidebarReloadID
        let articleReloadIDBeforeConfirmation = appState.articleListReloadID

        harness.dependencies.appActions.requestFolderDeleteConfirmation(
            named: "Design",
            using: appState
        )
        harness.dependencies.appActions.confirmPendingFolderDelete(using: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(appState.pendingFolderDeleteConfirmation == nil)
        #expect(try harness.folderRepository.fetchFolder(name: "Design") == nil)
        #expect(persistedFeed.folder == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeConfirmation)
        #expect(appState.articleListReloadID != articleReloadIDBeforeConfirmation)
    }
}

@MainActor
private final class RecordingUnreadAppIconBadgeService: UnreadAppIconBadgeServicing {
    private(set) var refreshBadgeCountCallCount = 0
    private(set) var appliedPreferences: [Bool] = []
    private(set) var refreshObservations: [RefreshSnapshotObservation] = []
    var onRefreshBadgeCount: (() -> RefreshSnapshotObservation)?

    func refreshBadgeCount() async {
        refreshBadgeCountCallCount += 1
        if let observation = onRefreshBadgeCount?() {
            refreshObservations.append(observation)
        }
    }

    func applyBadgePreference(isEnabled: Bool) async {
        appliedPreferences.append(isEnabled)
    }
}

private struct RefreshSnapshotObservation {
    let articleCount: Int
    let currentArticleCount: Int
    let unreadCount: Int?
    let sidebarReloadID: UUID
    let articleListReloadID: UUID
}

private func makeMixedAgeRSSFeedXML(entryIDs: [Int]) -> String {
    let items = entryIDs.map { entryID in
        """
        <item>
          <title>Mixed Age Article \(entryID)</title>
          <link>https://example.com/mixed-age/\(entryID)</link>
          <guid isPermaLink="false">mixed-age-\(entryID)</guid>
          <description>Mixed age fixture article \(entryID)</description>
          <pubDate>Mon, \(String(format: "%02d", entryID)) Jan 2024 10:00:00 GMT</pubDate>
        </item>
        """
    }.joined(separator: "\n")

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Mixed Age Feed</title>
        <link>https://example.com/mixed-age/</link>
        <description>Mixed age lifecycle fixture</description>
        <language>en</language>
        \(items)
      </channel>
    </rss>
    """
}
