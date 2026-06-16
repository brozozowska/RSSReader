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
}
