import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen Controller / Add Feed")
@MainActor
struct SourceManagementScreenControllerAddFeedTests {
    @Test
    func sourceManagementScreenControllerLoadsFeedPreviewThroughSourceManagementService() async throws {
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
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(" \(feedURL) ")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview loading")
            return
        }

        #expect(destination.preview?.title == "Controller Preview Feed")
        #expect(destination.preview?.siteURL == "https://example.com/")
        #expect(destination.preview?.kindTitle == SourceManagementLocalization.rssFeedKindTitle)
        #expect(destination.primaryActionTitle == SourceManagementLocalization.addFeedTitle)
        #expect(destination.isPrimaryActionEnabled)
        #expect(destination.isConfirmationActionEnabled)

        let recordedRequests = await harness.httpClient.recordedRequests()
        #expect(recordedRequests.map(\.url.absoluteString) == [feedURL])
    }

    @Test
    func sourceManagementScreenControllerCreatesFeedThroughServiceAfterConfirmedPreview() async throws {
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
        let controller = SourceManagementScreenController()

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

        #expect(createdDestination.primaryActionTitle == SourceManagementLocalization.feedAddedAction)
        #expect(createdDestination.isPrimaryActionEnabled == false)
        #expect(createdDestination.status?.title == SourceManagementLocalization.feedAddedTitle)
        #expect(createdDestination.status?.detail == SourceManagementLocalization.feedAddedDetail(title: "Created Feed", folderTitle: "Tech"))
        #expect(persistedFeed?.url == feedURL)
        #expect(persistedFeed?.title == "Created Feed")
        #expect(persistedFeed?.siteURL == "https://example.com/")
        #expect(persistedFeed?.kind == .rss)
        #expect(persistedFeed?.folder?.id == folder.id)
    }

    @Test
    func sourceManagementScreenControllerCreatesFeedDismissesThenRefreshesAndStaysOnSources() async throws {
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
        let controller = SourceManagementScreenController()
        let articleReloadIDBeforeCreation = appState.articleListReloadID
        let sidebarReloadIDBeforeCreation = appState.sourcesSidebarReloadID

        harness.dependencies.appActions.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(url: feedURL))
        let articles = try harness.articleRepository.fetchArticles(feedID: persistedFeed.id)

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == nil)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCreation)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCreation)
        #expect(appState.consumeSourceIconNetworkLoadRequest(for: persistedFeed.id))
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
    func sourceManagementScreenControllerEditsFeedDismissesThenRefreshesUpdatedSource() async throws {
        let initialURL = "https://example.com/original-feed.xml"
        let updatedURL = "https://example.com/updated-feed.xml"
        let previewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Updated Feed Title",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Updated Feed Article",
                itemLink: "https://example.com/articles/updated-feed",
                itemGUID: "updated-feed-article",
                itemDescription: "Updated feed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let refreshStep = ScriptedHTTPClient.Step.delayedResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Updated Feed Title",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Updated Feed Article",
                itemLink: "https://example.com/articles/updated-feed",
                itemGUID: "updated-feed-article",
                itemDescription: "Updated feed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            ),
            delayNanoseconds: 200_000_000
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: [previewStep, refreshStep])
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
        let controller = SourceManagementScreenController()

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        harness.dependencies.appActions.showFeedEditor(id: feed.id, using: appState)
        controller.handleLaunchContext(.editFeed(feed.id), dependencies: harness.dependencies)

        guard case .addFeed(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation for feed editor launch context")
            return
        }

        #expect(initialDestination.title == SourceManagementLocalization.editFeedTitle)
        #expect(initialDestination.urlInput == initialURL)
        #expect(initialDestination.placementOptions.isEmpty)
        #expect(initialDestination.createFolderActionTitle == nil)

        controller.handleAddFeedURLChange(updatedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == nil)
        #expect(persistedFeed.url == updatedURL)
        #expect(persistedFeed.title == "Updated Feed Title")
        #expect(persistedFeed.folder?.id == originalFolder.id)
        #expect(persistedFeed.lastSuccessfulFetchAt == nil)
        #expect(articles.isEmpty)

        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()

        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let refreshedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(refreshedArticles.count == 1)
        #expect(refreshedArticles.first?.title == "Updated Feed Article")
        #expect(requests.map(\.url.absoluteString) == [updatedURL, updatedURL])
    }

    @Test
    func sourceManagementScreenControllerShowsDuplicateFeedWarningWhenPreviewMatchesExistingSource() async throws {
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
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after duplicate preview loading")
            return
        }

        #expect(destination.preview?.title == "Existing Feed")
        #expect(destination.preview?.existingFeedNotice == SourceManagementLocalization.duplicateSourceNotice)
        #expect(destination.status?.kind == .warning)
        #expect(destination.status?.title == SourceManagementLocalization.duplicateFeedTitle)
        #expect(destination.primaryActionTitle == SourceManagementLocalization.alreadyAddedAction)
        #expect(destination.isPrimaryActionEnabled == false)
    }

    @Test
    func sourceManagementScreenControllerShowsNetworkFailureStatusWhenPreviewRequestFails() async throws {
        let feedURL = "https://example.com/network-failure.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .urlError(.notConnectedToInternet)
                ]
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after network failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == String(localized: "sourceManagement.addFeed.preview.network.title", defaultValue: "Network error while loading preview", comment: "Failure title for network error while loading feed preview."))
        #expect(destination.status?.detail == String(localized: "sourceManagement.addFeed.preview.network.offline", defaultValue: "Check the internet connection and try again.", comment: "Network failure detail for offline state."))
        #expect(destination.primaryActionTitle == SourceManagementLocalization.previewFeedAction)
        #expect(destination.isPrimaryActionEnabled == false)
    }

    @Test
    func sourceManagementScreenControllerShowsUnsupportedFeedStatusWhenPreviewResponseIsNotAFeed() async throws {
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
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after unsupported-feed failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == String(localized: "sourceManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "Source is not a supported feed", comment: "Failure title for unsupported feed."))
        #expect(destination.status?.detail == String.localizedStringWithFormat(String(localized: "sourceManagement.addFeed.preview.unsupportedContentType.detail.format", defaultValue: "The address responded with %@, not a supported RSS or Atom feed.", comment: "Feed preview failure detail for unsupported content type. Placeholder is content type."), "text/html; charset=utf-8"))
        #expect(destination.primaryActionTitle == SourceManagementLocalization.previewFeedAction)
        #expect(destination.isPrimaryActionEnabled == false)
    }
}
