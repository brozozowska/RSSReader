import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Starred Session")
@MainActor
struct ArticlesScreenControllerStarredSessionTests {
    @Test
    func articlesScreenControllerRetainsStarredArticleAfterManualUnstarInCurrentSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/manual-unstar-retention.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "manual-unstar-retention-article",
            url: "https://example.com/articles/manual-unstar-retention",
            title: "Manual Unstar Retention"
        )
        _ = try harness.articleStateService.toggleStarred(article: article, at: .now)
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )

        let loadedArticle = try #require(controller.screenState.articles.first)
        controller.toggleStarredState(
            for: loadedArticle,
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try #require(
            try harness.articleStateRepository.fetchState(
                feedID: feed.id,
                articleExternalID: article.externalID
            )
        )

        #expect(persistedState.isStarred == false)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.visibleArticleIDs() == [article.id])
        #expect(controller.screenState.articles.first?.isStarred == false)
        #expect(
            controller.screenState.articleListSession.entries.map(\.membershipStatus)
                == [.retainedAfterFilterMutation]
        )
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.starredItemsSubtitle(count: 0)
        )
    }

    @Test
    func articlesScreenControllerRetainsUnstarredArticleDuringRetainingReload() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/retaining-unstar-reload.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "retaining-unstar-reload-article",
            url: "https://example.com/articles/retaining-unstar-reload",
            title: "Retaining Unstar Reload"
        )
        _ = try harness.articleStateService.toggleStarred(article: article, at: .now)
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )

        let loadedArticle = try #require(controller.screenState.articles.first)
        controller.toggleStarredState(
            for: loadedArticle,
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: true
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articles.first?.isStarred == false)
        #expect(
            controller.screenState.articleListSession.entries.map(\.membershipStatus)
                == [.retainedAfterFilterMutation]
        )
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.starredItemsSubtitle(count: 0)
        )
    }

    @Test
    func articlesScreenControllerRemovesRetainedUnstarredArticleAfterFreshRefreshSnapshot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/unstar-refresh-reset.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "unstar-refresh-reset-article",
            url: "https://example.com/articles/unstar-refresh-reset",
            title: "Unstar Refresh Reset"
        )
        _ = try harness.articleStateService.toggleStarred(article: article, at: .now)
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )

        let loadedArticle = try #require(controller.screenState.articles.first)
        controller.toggleStarredState(
            for: loadedArticle,
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.articles.map(\.id) == [article.id])

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: false,
            retainedSessionMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.visibleArticleIDs().isEmpty)
        #expect(controller.screenState.articleListSession.entries.isEmpty)
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.starredItemsSubtitle(count: 0)
        )
    }

    @Test
    func articlesScreenControllerOmitsUnstarredArticleAfterReenteringWithNewSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/unstar-reentry.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "unstar-reentry-article",
            url: "https://example.com/articles/unstar-reentry",
            title: "Unstar Reentry"
        )
        _ = try harness.articleStateService.toggleStarred(article: article, at: .now)
        let currentSessionController = ArticlesScreenController()

        await currentSessionController.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )

        let loadedArticle = try #require(currentSessionController.screenState.articles.first)
        currentSessionController.toggleStarredState(
            for: loadedArticle,
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(currentSessionController.screenState.articles.map(\.id) == [article.id])

        let reenteredSessionController = ArticlesScreenController()
        await reenteredSessionController.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )

        #expect(reenteredSessionController.screenState.phase == .empty)
        #expect(reenteredSessionController.screenState.articles.isEmpty)
        #expect(reenteredSessionController.visibleArticleIDs().isEmpty)
        #expect(reenteredSessionController.screenState.articleListSession.entries.isEmpty)
        #expect(
            reenteredSessionController.screenState.navigationSubtitle
                == ReadingLocalization.starredItemsSubtitle(count: 0)
        )
    }
}
