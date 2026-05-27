import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller")
@MainActor
struct ArticlesScreenControllerTests {
    @Test
    func articlesScreenControllerLoadsFeedArticlesForCurrentSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-load.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-load-article",
            url: "https://example.com/articles/controller-load",
            title: "Controller Load"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.navigationTitle == "controller-load.xml")
        #expect(controller.screenState.articles.count == 1)
        #expect(controller.screenState.articles.first?.title == "Controller Load")
    }

    @Test
    func articlesScreenControllerLoadsArchivedAndCurrentArticlesForCurrentSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-archive.xml"]).first)
        let archivedAt = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-archived-article",
            url: "https://example.com/articles/controller-archived",
            title: "Controller Archived",
            archivedAt: archivedAt
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-current-article",
            url: "https://example.com/articles/controller-current",
            title: "Controller Current"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.count == 2)
        #expect(controller.screenState.articles.contains { $0.title == "Controller Archived" && $0.archivedAt == archivedAt })
        #expect(controller.screenState.articles.contains { $0.title == "Controller Current" && $0.archivedAt == nil })
    }

    @Test
    func articlesScreenControllerUsesFeedDisplayTitleOverrideForNavigationTitle() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = Feed(
            url: "https://example.com/display-title.xml",
            title: "XML Feed Title",
            displayTitleOverride: "My Feed"
        )
        try harness.feedRepository.insert(feed)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "display-title-article",
            url: "https://example.com/articles/display-title",
            title: "Display Title Article"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.navigationTitle == "My Feed")
    }

    @Test
    func articlesScreenControllerUsesUnreadCountForFeedNavigationSubtitle() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = Feed(
            url: "https://example.com/last-refresh.xml",
            title: "Last Refresh"
        )
        try harness.feedRepository.insert(feed)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "last-refresh-article",
            url: "https://example.com/articles/last-refresh",
            title: "Last Refresh Article"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.navigationSubtitle == "1 Unread Item")
    }

    @Test
    func articlesScreenControllerRetainsSessionReadArticleOnlyForRetainingReloads() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-unread.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-unread-article",
            url: "https://example.com/articles/session-unread",
            title: "Session Unread"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionReadArticles: true
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRead])
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.navigationSubtitle == "No Unread Items")

        let newEntryController = ArticlesScreenController()
        await newEntryController.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )

        #expect(newEntryController.screenState.phase == .empty)
        #expect(newEntryController.screenState.articles.isEmpty)
    }

    @Test
    func articlesScreenControllerMarksSessionReadRetentionAfterRefresh() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-refresh.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-refresh-article",
            url: "https://example.com/articles/session-refresh",
            title: "Session Refresh"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionReadArticles: true,
            retainedSessionReadMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRefresh])
        #expect(controller.screenState.navigationSubtitle == "No Unread Items")
    }

    @Test
    func articlesScreenControllerAppliesFreshQuerySnapshotAfterRefreshWithoutRetainingReadEntries() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-refresh-reset.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-refresh-reset-article",
            url: "https://example.com/articles/session-refresh-reset",
            title: "Session Refresh Reset"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionReadArticles: false,
            retainedSessionReadMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.articleListSession.entries.isEmpty)
        #expect(controller.screenState.navigationSubtitle == "No Unread Items")
    }

    @Test
    func articlesScreenControllerResetsSessionWhenSourcesFilterChanges() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-filter-reset.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-filter-reset-article",
            url: "https://example.com/articles/session-filter-reset",
            title: "Session Filter Reset"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies,
            retainsSessionReadArticles: true
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articleListSession.context == ArticleListSession.Context(
            selection: .feed(feed.id),
            sourcesFilter: .allItems
        ))
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articleListSession.entries.map(\.membershipStatus) == [.matchesCurrentQuery])
        #expect(controller.screenState.articles.first?.isRead == true)
    }

    @Test
    func articlesScreenControllerMergesFreshQuerySnapshotWithCurrentRetainedEntries() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-merge.xml"]).first)
        let retainedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "session-merge-retained",
            url: "https://example.com/articles/session-merge-retained",
            title: "Retained Article"
        )
        let currentArticle = try harness.insertArticle(
            feed: feed,
            externalID: "session-merge-current",
            url: "https://example.com/articles/session-merge-current",
            title: "Current Article"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: retainedArticle.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(retainedArticle.id)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "session-merge-new",
            url: "https://example.com/articles/session-merge-new",
            title: "New Article"
        )

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionReadArticles: true,
            retainedSessionReadMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.contains { $0.id == retainedArticle.id })
        #expect(controller.screenState.articles.contains { $0.id == currentArticle.id })
        #expect(controller.screenState.articles.contains { $0.title == "New Article" })
        #expect(
            controller.screenState.articleListSession.entries.first {
                $0.id == retainedArticle.id
            }?.membershipStatus == .retainedAfterRefresh
        )
        #expect(
            controller.screenState.articleListSession.entries.filter {
                $0.membershipStatus == .matchesCurrentQuery
            }.count == 2
        )
    }

    func articlesScreenControllerPresentsRefreshFailureFromBatchRefreshResult() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/controller-refresh.xml": .response(
                    statusCode: 500,
                    headers: [:],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-refresh.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-refresh-article",
            url: "https://example.com/articles/controller-refresh",
            title: "Controller Refresh"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )
        harness.dependencies.showFeed(id: feed.id, using: appState)

        await controller.refreshCurrentSelection(
            selection: .feed(feed.id),
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.refreshFeedback?.message.contains("invalidStatusCode") == true)
    }

    @Test
    func articlesScreenControllerClearsPreviousRefreshErrorAfterSuccessfulRefresh() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/controller-refresh-success.xml": .response(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Refresh Success Feed",
                        channelLink: "https://example.com/refresh-success/",
                        language: "en",
                        itemTitle: "Refreshed Article",
                        itemLink: "https://example.com/articles/refreshed",
                        itemGUID: "refreshed-article",
                        itemDescription: "Readable summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-refresh-success.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-refresh-success-article",
            url: "https://example.com/articles/controller-refresh-success",
            title: "Controller Refresh Success"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )
        controller.screenState.presentRefreshFailure("Previous refresh failed")
        harness.dependencies.showFeed(id: feed.id, using: appState)

        await controller.refreshCurrentSelection(
            selection: .feed(feed.id),
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func articlesScreenControllerClearsStaleRefreshErrorWhenSelectionChanges() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-selection-a.xml"]).first)
        let secondFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-selection-b.xml"]).first)

        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "controller-selection-a-article",
            url: "https://example.com/articles/controller-selection-a",
            title: "First Selection"
        )
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "controller-selection-b-article",
            url: "https://example.com/articles/controller-selection-b",
            title: "Second Selection"
        )

        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(firstFeed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )
        controller.screenState.presentRefreshFailure("Refresh failed for first feed")

        await controller.load(
            selection: .feed(secondFeed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articles.first?.title == "Second Selection")
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func articlesScreenControllerPresentsConfirmationWhenAskBeforeMarkingAllAsReadIsEnabled() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let controller = ArticlesScreenController(
            previewScreenState: .previewLoaded(
                selection: .feed(unreadItem.feedID),
                navigationTitle: "Feed",
                navigationSubtitle: "1 Unread Item",
                articles: [unreadItem]
            )
        )

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: true,
                updatedAt: .distantPast
            )
        )

        controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.pendingConfirmation == .markAllAsRead)
        #expect(controller.screenState.articles.first?.isRead == false)
    }

    @Test
    func articlesScreenControllerMarksAllAsReadImmediatelyWhenAskBeforeMarkingAllAsReadIsDisabled() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let articleStateRepository = try #require(harness.dependencies.articleStateRepository)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let controller = ArticlesScreenController(
            previewScreenState: .previewLoaded(
                selection: .feed(unreadItem.feedID),
                navigationTitle: "Feed",
                navigationSubtitle: "1 Unread Item",
                articles: [unreadItem]
            )
        )

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: false,
                updatedAt: .distantPast
            )
        )

        controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try articleStateRepository.fetchStateSnapshot(
            feedID: unreadItem.feedID,
            articleExternalID: unreadItem.articleExternalID
        )

        #expect(controller.screenState.pendingConfirmation == nil)
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.navigationSubtitle == "No Unread Items")
        #expect(persistedState?.isRead == true)
    }
}
