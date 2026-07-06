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

        harness.dependencies.appActions.selectArticle(id: article.id, using: appState)
        harness.dependencies.appActions.openArticleInSafari(article, using: appState)

        #expect(appState.selectedDetailRoute == .safari(ArticleSafariRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!)))
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!))

        harness.dependencies.appActions.closePresentedArticleSafari(using: appState)

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

        let didOpenSafari = harness.dependencies.appActions.openArticleInSafari(article, using: appState)

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

        harness.dependencies.appActions.openArticleBodyLink(
            URL(string: "mailto:hello@example.com")!,
            articleID: articleID,
            using: appState
        )

        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func shellActionEntryPointsSelectArticleOpensSafariWhenArticleOpeningModeIsSafariView() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/article-opening-mode.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "safari-view-article",
            url: "https://example.com/articles/safari-view-mode",
            title: "Safari View Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/safari-view-mode/canonical"
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleOpeningMode: .safariView)
        )
        try harness.saveModelContext()

        harness.dependencies.appActions.selectArticle(id: articleModel.id, using: appState)

        #expect(appState.selectedArticleID == articleModel.id)
        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(
                    articleID: articleModel.id,
                    url: URL(string: "https://example.com/articles/safari-view-mode/canonical")!
                )
            )
        )
        #expect(
            appState.presentedSafariRoute == ArticleSafariRoute(
                articleID: articleModel.id,
                url: URL(string: "https://example.com/articles/safari-view-mode/canonical")!
            )
        )
    }

    @Test
    func shellActionEntryPointsSelectArticleFallsBackToReaderWhenDefaultSafariURLIsUnsupported() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/article-opening-unsupported-safari.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "article-opening-unsupported-safari-article",
            url: "https://example.com/articles/article-opening-unsupported-safari",
            title: "Unsupported Safari View Article"
        )
        articleModel.canonicalURL = "mailto:hello@example.com"
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleOpeningMode: .safariView)
        )
        try harness.saveModelContext()

        harness.dependencies.appActions.selectArticle(id: articleModel.id, using: appState)

        #expect(appState.selectedArticleID == articleModel.id)
        #expect(appState.selectedDetailRoute == .article(articleModel.id))
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentFeedTriggersReloadAfterFeedRefresh() async throws {
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

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        let reloadIDAfterSidebarSelection = appState.articleListReloadID

        let result = await harness.dependencies.appActions.refreshCurrentFeed(using: appState)

        #expect(result?.status == .notModified)
        #expect(appState.articleListReloadID != reloadIDAfterSidebarSelection)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshAfterAddingFeedRefreshesNewFeedSelectsItAndClosesModalFlow() async throws {
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
        let sidebarReloadIDBeforeRefresh = appState.sidebarReloadID
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Shell Feed",
                kind: .rss
            )
        )

        harness.dependencies.appActions.showFeedManagement(using: appState)

        let result = await harness.dependencies.appActions.refreshAfterAddingFeed(id: feed.id, using: appState)
        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result?.status == .fetched)
        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeRefresh)
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Shell Refreshed Article")
    }

    @Test
    func shellActionEntryPointsUnsubscribeFeedRemovesFeedAndResetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/unsubscribe.xml",
                title: "Unsubscribe Me",
                kind: .rss
            )
        )
        let sidebarReloadIDBeforeDelete = appState.sidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        harness.dependencies.appActions.unsubscribeFeed(id: feed.id, using: appState)

        #expect(try harness.feedRepository.fetchFeed(id: feed.id) == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeDelete)
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
        let sidebarReloadIDBeforeDelete = appState.sidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.appActions.showFolder(named: "Tech", using: appState)
        harness.dependencies.appActions.deleteFolder(named: "Tech", using: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))

        #expect(try harness.folderRepository.fetchFolder(name: "Tech") == nil)
        #expect(persistedFeed.folder == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeDelete)
        #expect(appState.articleListReloadID != articleReloadIDBeforeDelete)
    }

    @Test
    func shellActionEntryPointsRefreshVisibleFeedsTriggersReloadAfterBatchRefresh() async throws {
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
        let feeds = try harness.insertFeeds(urls: urls)
        let firstFeed = try #require(feeds.first)
        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "expired-archived-unread",
            url: "https://example.com/articles/expired-archived-unread",
            title: "Expired Archived Unread",
            archivedAt: .distantPast
        )
        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "current-unread",
            url: "https://example.com/articles/current-unread",
            title: "Current Unread"
        )
        let reloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sidebarReloadID
        let unreadCountsBeforeRefresh = try harness.articleStateRepository.fetchUnreadCounts(feedIDs: [firstFeed.id])

        let result = await harness.dependencies.appActions.refreshVisibleFeeds(using: appState)
        let unreadCountsAfterRefresh = try harness.articleStateRepository.fetchUnreadCounts(feedIDs: [firstFeed.id])

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(unreadCountsBeforeRefresh[firstFeed.id] == 2)
        #expect(unreadCountsAfterRefresh[firstFeed.id] == 1)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeRefresh)
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
        let sidebarReloadIDBeforeRefresh = appState.sidebarReloadID

        harness.dependencies.appActions.showFolder(named: "Tech", using: appState)

        let result = await harness.dependencies.appActions.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeRefresh)
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

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sidebarReloadID

        let result = await harness.dependencies.appActions.refreshCurrentSelection(
            using: appState,
            requestsArticleListReload: false
        )

        #expect(result?.summary.totalFeedCount == 1)
        #expect(result?.summary.notModifiedCount == 1)
        #expect(appState.articleListReloadID == articleReloadIDBeforeRefresh)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeRefresh)
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

        harness.dependencies.appActions.showInbox(using: appState)

        let result = await harness.dependencies.appActions.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
    }
}
