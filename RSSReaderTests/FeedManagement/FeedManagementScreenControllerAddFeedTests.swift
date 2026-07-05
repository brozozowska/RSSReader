import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Screen Controller / Add Feed")
@MainActor
struct FeedManagementScreenControllerAddFeedTests {
    @Test
    func feedManagementScreenControllerLoadsFeedPreviewThroughFeedManagementService() async throws {
        let feedURL = "https://example.com/preview-controller.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Controller Preview Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Preview Article",
                            itemLink: "https://example.com/articles/preview",
                            itemGUID: "controller-preview-article",
                            itemDescription: "Preview description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let controller = FeedManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(" \(feedURL) ")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview loading")
            return
        }

        #expect(destination.preview?.title == "Controller Preview Feed")
        #expect(destination.preview?.siteURL == "https://example.com/")
        #expect(destination.preview?.kindTitle == FeedManagementLocalization.rssFeedKindTitle)
        #expect(destination.primaryActionTitle == FeedManagementLocalization.addFeedTitle)
        #expect(destination.isPrimaryActionEnabled)
        #expect(destination.isConfirmationActionEnabled)

        let recordedRequests = await harness.httpClient.recordedRequests()
        #expect(recordedRequests.map(\.url.absoluteString) == [feedURL])
    }

    @Test
    func feedManagementScreenControllerCreatesFeedThroughServiceAfterConfirmedPreview() async throws {
        let feedURL = "https://example.com/create-from-preview.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Created Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Created Article",
                            itemLink: "https://example.com/articles/created",
                            itemGUID: "created-article",
                            itemDescription: "Created description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let folder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let controller = FeedManagementScreenController()

        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(" \(feedURL) ")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)
        controller.handleAddFeedFolderPlacementSelection(.folder(folder.id))
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let createdDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after feed creation")
            return
        }

        let persistedFeed = try harness.feedRepository.fetchFeed(url: feedURL)

        #expect(createdDestination.primaryActionTitle == FeedManagementLocalization.feedAddedAction)
        #expect(createdDestination.isPrimaryActionEnabled == false)
        #expect(createdDestination.status?.title == FeedManagementLocalization.feedAddedTitle)
        #expect(createdDestination.status?.detail == FeedManagementLocalization.feedAddedDetail(title: "Created Feed", folderTitle: "Tech"))
        #expect(persistedFeed?.url == feedURL)
        #expect(persistedFeed?.title == "Created Feed")
        #expect(persistedFeed?.siteURL == "https://example.com/")
        #expect(persistedFeed?.kind == .rss)
        #expect(persistedFeed?.folder?.id == folder.id)
    }

    @Test
    func feedManagementScreenControllerCreatesFeedDismissesThenRefreshesAndStaysOnSidebar() async throws {
        let feedURL = "https://example.com/create-and-refresh.xml"
        let previewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Created And Refreshed Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "First Refreshed Article",
                itemLink: "https://example.com/articles/first-refreshed",
                itemGUID: "first-refreshed-article",
                itemDescription: "Refreshed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let refreshStep = ScriptedHTTPClient.Step.delayedResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Created And Refreshed Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "First Refreshed Article",
                itemLink: "https://example.com/articles/first-refreshed",
                itemGUID: "first-refreshed-article",
                itemDescription: "Refreshed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            ),
            delayNanoseconds: 200_000_000
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [previewStep, refreshStep]
            )
        )
        let appState = AppState()
        let controller = FeedManagementScreenController()
        let articleReloadIDBeforeCreation = appState.articleListReloadID
        let sidebarReloadIDBeforeCreation = appState.sidebarReloadID

        harness.dependencies.appActions.showFeedManagement(using: appState)
        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(url: feedURL))
        let articles = try harness.articleRepository.fetchArticles(feedID: persistedFeed.id)

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == nil)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCreation)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeCreation)
        #expect(appState.consumeFeedIconNetworkLoadRequest(for: persistedFeed.id))
        #expect(persistedFeed.lastFetchedAt == nil)
        #expect(persistedFeed.lastSuccessfulFetchAt == nil)
        #expect(articles.isEmpty)

        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()

        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: persistedFeed.id))
        let refreshedArticles = try harness.articleRepository.fetchArticles(feedID: persistedFeed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(refreshedArticles.count == 1)
        #expect(refreshedArticles.first?.title == "First Refreshed Article")
        #expect(requests.map(\.url.absoluteString) == [feedURL, feedURL])
    }

    @Test
    func feedManagementScreenControllerRenamesFeedAndIgnoresEditedURLInput() async throws {
        let initialURL = "https://example.com/original-feed.xml"
        let updatedURL = "https://example.com/updated-feed.xml"
        let refreshStep = ScriptedHTTPClient.Step.delayedResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Original Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Original Feed Article",
                itemLink: "https://example.com/articles/original-feed",
                itemGUID: "original-feed-article",
                itemDescription: "Original feed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            ),
            delayNanoseconds: 200_000_000
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: [refreshStep])
        )
        let originalFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: initialURL,
                title: "Original Feed",
                kind: .rss,
                folder: originalFolder
            )
        )
        let appState = AppState()
        let controller = FeedManagementScreenController()

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        harness.dependencies.appActions.showFeedEditor(id: feed.id, using: appState)
        controller.handleLaunchContext(.editFeed(feed.id), dependencies: harness.dependencies)

        guard case .addFeed(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation for feed editor launch context")
            return
        }

        #expect(initialDestination.title == FeedManagementLocalization.editFeedTitle)
        #expect(initialDestination.urlInput == initialURL)
        #expect(initialDestination.placementOptions.isEmpty)
        #expect(initialDestination.createFolderActionTitle == nil)
        #expect(initialDestination.allowsPreviewAction == false)

        controller.handleAddFeedURLChange(updatedURL)
        controller.handleAddFeedDisplayNameChange("Renamed Feed")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == nil)
        #expect(persistedFeed.url == initialURL)
        #expect(persistedFeed.title == "Original Feed")
        #expect(persistedFeed.displayTitleOverride == "Renamed Feed")
        #expect(persistedFeed.folder?.id == originalFolder.id)
        #expect(persistedFeed.lastSuccessfulFetchAt == nil)
        #expect(articles.isEmpty)

        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()

        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let refreshedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(refreshedArticles.count == 1)
        #expect(refreshedArticles.first?.title == "Original Feed Article")
        #expect(requests.map(\.url.absoluteString) == [initialURL])
    }

    @Test
    func feedManagementScreenControllerShowsDuplicateFeedWarningWhenPreviewMatchesExistingFeed() async throws {
        let feedURL = "https://example.com/existing-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Existing Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Existing Article",
                            itemLink: "https://example.com/articles/existing",
                            itemGUID: "existing-article",
                            itemDescription: "Existing description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        _ = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Existing Feed",
                kind: .rss
            )
        )
        let controller = FeedManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after duplicate preview loading")
            return
        }

        #expect(destination.preview?.title == "Existing Feed")
        #expect(destination.preview?.existingFeedNotice == FeedManagementLocalization.duplicateFeedNotice)
        #expect(destination.status?.kind == .warning)
        #expect(destination.status?.title == FeedManagementLocalization.duplicateFeedTitle)
        #expect(destination.primaryActionTitle == FeedManagementLocalization.alreadyAddedAction)
        #expect(destination.isPrimaryActionEnabled == false)
    }

    @Test
    func feedManagementScreenControllerShowsNetworkFailureStatusWhenPreviewRequestFails() async throws {
        let feedURL = "https://example.com/network-failure.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .urlError(.notConnectedToInternet)
                ]
            )
        )
        let controller = FeedManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after network failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == String(localized: "feedManagement.addFeed.preview.network.title", defaultValue: "Network error while loading preview", comment: "Failure title for network error while loading feed preview."))
        #expect(destination.status?.detail == String(localized: "feedManagement.addFeed.preview.network.offline", defaultValue: "Check the internet connection and try again.", comment: "Network failure detail for offline state."))
        #expect(destination.primaryActionTitle == FeedManagementLocalization.previewFeedAction)
        #expect(destination.isPrimaryActionEnabled == false)
    }

    @Test
    func feedManagementScreenControllerShowsUnsupportedFeedStatusWhenPreviewResponseIsNotAFeed() async throws {
        let feedURL = "https://example.com/not-a-feed"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "text/html; charset=utf-8"],
                        body: "<html><body>Not a feed</body></html>"
                    )
                ]
            )
        )
        let controller = FeedManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after unsupported-feed failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == String(localized: "feedManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "This is not a supported feed", comment: "Failure title for unsupported feed."))
        #expect(destination.status?.detail == String.localizedStringWithFormat(String(localized: "feedManagement.addFeed.preview.unsupportedContentType.detail.format", defaultValue: "The address responded with %@, not a supported RSS or Atom feed.", comment: "Feed preview failure detail for unsupported content type. Placeholder is content type."), "text/html; charset=utf-8"))
        #expect(destination.primaryActionTitle == FeedManagementLocalization.previewFeedAction)
        #expect(destination.isPrimaryActionEnabled == false)
    }
}
