import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Session Reload")
@MainActor
struct ArticlesScreenControllerSessionReloadTests {
    @Test
    func articlesScreenControllerRetainsUnreadArticleAfterManualReadToggleInCurrentSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/manual-read-retention.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "manual-read-retention-article",
            url: "https://example.com/articles/manual-read-retention",
            title: "Manual Read Retention"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )

        let loadedArticle = try #require(controller.screenState.articles.first)
        controller.toggleArticleReadStatus(
            loadedArticle,
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try #require(
            try harness.articleStateRepository.fetchState(
                feedID: feed.id,
                articleExternalID: article.externalID
            )
        )

        #expect(persistedState.isRead)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRead])
        #expect(controller.screenState.navigationSubtitle == "No Unread Items")
        #expect(controller.screenState.toolbarActions.isMarkAllAsReadEnabled == false)
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
    func articlesScreenControllerKeepsScrollPositionAndRemovesRetainedReadArticleAfterReturnRefresh() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/return-refresh.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "return-refresh-article",
            url: "https://example.com/articles/return-refresh",
            title: "Return Refresh"
        )
        let appState = AppState()
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies
        )
        appState.updateArticleListScrollPosition(
            article.id,
            sourceSelection: .feed(feed.id),
            sourcesFilter: .unread
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRead])

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionReadArticles: false,
            retainedSessionReadMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(
            appState.articleListScrollPositionID(
                sourceSelection: .feed(feed.id),
                sourcesFilter: .unread
            ) == article.id
        )
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
}
