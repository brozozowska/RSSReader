import Foundation
import Testing
@testable import RSSReader

@Suite("Shell / Entry Points")
@MainActor
struct ShellActionEntryPointTests {
    @Test
    func shellActionEntryPointsOpenAndCloseArticleSafariRouteViaDependencies() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/shell-web.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "shell-web-article",
            url: "https://example.com/articles/1",
            title: "Shell Web Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/1/canonical"
        try harness.saveModelContext()
        let readerArticle = try harness.dependencies.articleQueryService?.fetchReaderArticle(id: articleModel.id)
        let article = try #require(readerArticle)

        harness.dependencies.selectArticle(id: article.id, using: appState)
        harness.dependencies.openArticleInSafari(article, using: appState)

        #expect(appState.selectedDetailRoute == .safari(ArticleSafariRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!)))
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!))

        harness.dependencies.closePresentedArticleSafari(using: appState)

        #expect(appState.selectedDetailRoute == .article(article.id))
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func shellActionEntryPointsSkipUnsupportedArticleSafariURLs() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/shell-unsupported-safari.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "shell-unsupported-safari-article",
            url: "https://example.com/articles/unsupported-safari",
            title: "Shell Unsupported Safari Article"
        )
        articleModel.canonicalURL = "mailto:hello@example.com"
        try harness.saveModelContext()
        let readerArticle = try harness.dependencies.articleQueryService?.fetchReaderArticle(id: articleModel.id)
        let article = try #require(readerArticle)

        let didOpenSafari = harness.dependencies.openArticleInSafari(article, using: appState)

        #expect(didOpenSafari == false)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func shellActionEntryPointsSkipUnsupportedBodyLinkSafariURLs() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let articleID = UUID()

        harness.dependencies.openArticleBodyLink(
            URL(string: "mailto:hello@example.com")!,
            articleID: articleID,
            using: appState
        )

        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func shellActionEntryPointsSelectArticleOpensSafariWhenDefaultReaderModeIsBrowser() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/default-reader-mode.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "default-browser-article",
            url: "https://example.com/articles/browser-mode",
            title: "Default Browser Mode Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/browser-mode/canonical"
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(defaultReaderMode: .browser)
        )
        try harness.saveModelContext()

        harness.dependencies.selectArticle(id: articleModel.id, using: appState)

        #expect(appState.selectedArticleID == articleModel.id)
        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(
                    articleID: articleModel.id,
                    url: URL(string: "https://example.com/articles/browser-mode/canonical")!
                )
            )
        )
        #expect(
            appState.presentedSafariRoute == ArticleSafariRoute(
                articleID: articleModel.id,
                url: URL(string: "https://example.com/articles/browser-mode/canonical")!
            )
        )
    }

    @Test
    func shellActionEntryPointsSelectArticleFallsBackToReaderWhenDefaultSafariURLIsUnsupported() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/default-reader-unsupported-safari.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "default-unsupported-safari-article",
            url: "https://example.com/articles/default-unsupported-safari",
            title: "Default Unsupported Safari Article"
        )
        articleModel.canonicalURL = "mailto:hello@example.com"
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(defaultReaderMode: .browser)
        )
        try harness.saveModelContext()

        harness.dependencies.selectArticle(id: articleModel.id, using: appState)

        #expect(appState.selectedArticleID == articleModel.id)
        #expect(appState.selectedDetailRoute == .article(articleModel.id))
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSourceTriggersReloadAfterFeedRefresh() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/shell-refresh-current.xml": .response(
                    statusCode: 304,
                    headers: ["ETag": "\"etag-shell-current\""],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/shell-refresh-current.xml"]).first)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let reloadIDAfterSourceSelection = appState.articleListReloadID

        let result = await harness.dependencies.refreshCurrentSource(using: appState)

        #expect(result?.status == .notModified)
        #expect(appState.articleListReloadID != reloadIDAfterSourceSelection)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshAfterAddingFeedRefreshesNewSourceSelectsItAndClosesModalFlow() async throws {
        let feedURL = "https://example.com/shell-refresh-added.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Shell Refreshed Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Shell Refreshed Article",
                            itemLink: "https://example.com/articles/shell-refreshed",
                            itemGUID: "shell-refreshed-article",
                            itemDescription: "Shell refreshed description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let appState = AppState()
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Shell Feed",
                kind: .rss
            )
        )

        harness.dependencies.showSourceManagement(using: appState)

        let result = await harness.dependencies.refreshAfterAddingFeed(id: feed.id, using: appState)
        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result?.status == .fetched)
        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Shell Refreshed Article")
    }

    @Test
    func shellActionEntryPointsUnsubscribeFeedRemovesSourceAndResetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/unsubscribe.xml",
                title: "Unsubscribe Me",
                kind: .rss
            )
        )
        let sidebarReloadIDBeforeDelete = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.unsubscribeFeed(id: feed.id, using: appState)

        #expect(try harness.feedRepository.fetchFeed(id: feed.id) == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeDelete)
        #expect(appState.articleListReloadID != articleReloadIDBeforeDelete)
    }

    @Test
    func shellActionEntryPointsDeleteFolderUngroupsFeedsAndResetsFolderSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/folder-delete.xml",
                title: "Folder Feed",
                kind: .rss,
                folder: folder
            )
        )
        let sidebarReloadIDBeforeDelete = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.showFolder(named: "Tech", using: appState)
        harness.dependencies.deleteFolder(named: "Tech", using: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))

        #expect(try harness.folderRepository.fetchFolder(name: "Tech") == nil)
        #expect(persistedFeed.folder == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeDelete)
        #expect(appState.articleListReloadID != articleReloadIDBeforeDelete)
    }

    @Test
    func shellActionEntryPointsRefreshVisibleSourcesTriggersReloadAfterBatchRefresh() async throws {
        let urls = [
            "https://example.com/shell-refresh-all-1.xml",
            "https://example.com/shell-refresh-all-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        let result = await harness.dependencies.refreshVisibleSources(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesOnlyFolderFeeds() async throws {
        let urls = [
            "https://example.com/folder-refresh-1.xml",
            "https://example.com/folder-refresh-2.xml",
            "https://example.com/folder-refresh-3.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-2\""],
                body: ""
            ),
            urls[2]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-3\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: urls)
        let techFolder = Folder(name: "Tech")
        feeds[0].folder = techFolder
        feeds[1].folder = techFolder
        try harness.saveModelContext()
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID

        harness.dependencies.showFolder(named: "Tech", using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionCanLeaveArticleListReloadToCaller() async throws {
        let url = "https://example.com/suppress-article-reload.xml"
        let responses = [
            url: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-suppress-reload\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: [url]).first)

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID

        let result = await harness.dependencies.refreshCurrentSelection(
            using: appState,
            requestsArticleListReload: false
        )

        #expect(result?.summary.totalFeedCount == 1)
        #expect(result?.summary.notModifiedCount == 1)
        #expect(appState.articleListReloadID == articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesAllFeedsForInbox() async throws {
        let urls = [
            "https://example.com/inbox-refresh-1.xml",
            "https://example.com/inbox-refresh-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)

        harness.dependencies.showInbox(using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
    }
}
