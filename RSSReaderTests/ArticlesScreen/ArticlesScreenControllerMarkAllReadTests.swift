import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Mark All Read")
@MainActor
struct ArticlesScreenControllerMarkAllReadTests {
    @Test
    func articlesScreenControllerPresentsConfirmationWhenAskBeforeMarkingAllAsReadIsEnabled() async throws {
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

        await controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.pendingConfirmation == .markAllAsRead)
        #expect(controller.screenState.articles.first?.isRead == false)
    }

    @Test
    func articlesScreenControllerMarksAllAsReadImmediatelyWhenAskBeforeMarkingAllAsReadIsDisabled() async throws {
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

        await controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try articleStateRepository.fetchStateSnapshot(
            feedID: unreadItem.feedID,
            articleExternalID: unreadItem.articleExternalID
        )

        #expect(controller.screenState.pendingConfirmation == nil)
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articlesScreenControllerMarksAccumulatedPagesAndPreservesContinuationCursor() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let first = makeArticleListItemDTO(
            articleExternalID: "mark-page-first",
            isRead: false,
            isStarred: false
        )
        let second = makeArticleListItemDTO(
            feedID: first.feedID,
            articleExternalID: "mark-page-second",
            isRead: false,
            isStarred: false
        )
        let nextCursor = makeArticleSearchCursor(seed: 2)
        var screenState = ArticlesScreenState()
        screenState.applyLoadedArticles(
            [first, second],
            selection: .feed(first.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 2),
            sessionContext: ArticleListSession.Context(
                selection: .feed(first.feedID),
                sidebarArticleFilter: .allItems
            ),
            nextPageCursor: nextCursor
        )
        let controller = ArticlesScreenController(previewScreenState: screenState)

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .feed(first.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: true
        )

        #expect(controller.screenState.articles.allSatisfy { $0.isRead })
        #expect(controller.screenState.articleListSession.nextPageCursor == nextCursor)
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.unreadItemsLowerBoundSubtitle(count: 0)
        )
    }

    @Test
    func articlesScreenControllerReloadsPaginatedUnreadSessionAfterMarkingVisiblePageAsRead() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-unread-pages.xml"]).first
        )
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var persistedArticles: [Article] = []
        for index in 0..<3 {
            persistedArticles.append(
                try harness.insertArticle(
                    feed: feed,
                    externalID: "mark-unread-page-\(index)",
                    url: "https://example.com/articles/mark-unread-page-\(index)",
                    title: "Unread Page \(index)",
                    publishedAt: baseDate.addingTimeInterval(TimeInterval(index))
                )
            )
        }
        var requests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, articleQueryService in
                requests.append(request)
                return try await articleQueryService.fetchArticleSearchSnapshot(request)
            },
            pageSize: 1
        )

        await controller.load(
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let markedArticle = try #require(controller.screenState.articles.first)
        let originalContext = controller.screenState.articleListSession.context
        _ = try #require(controller.screenState.articleListSession.nextPageCursor)

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let continuedArticle = try #require(controller.screenState.articles.first)
        let markedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: markedArticle.feedID,
            articleExternalID: markedArticle.articleExternalID
        )
        let untouchedArticles = persistedArticles.filter { $0.id != markedArticle.id }

        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.cursor == nil })
        #expect(markedState?.isRead == true)
        #expect(continuedArticle.id != markedArticle.id)
        #expect(continuedArticle.isRead == false)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articleListSession.context == originalContext)
        #expect(controller.screenState.articleListSession.nextPageCursor != nil)
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.unreadItemsLowerBoundSubtitle(count: 1)
        )
        for article in untouchedArticles {
            let state = try harness.articleStateRepository.fetchStateSnapshot(
                feedID: article.feedID,
                articleExternalID: article.externalID
            )
            #expect(state == nil)
        }
    }

    @Test
    func articlesScreenControllerEndsUnreadSessionAfterMarkingTerminalPageAsRead() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-unread-terminal.xml"]).first
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "mark-unread-terminal",
            url: "https://example.com/articles/mark-unread-terminal",
            title: "Unread Terminal"
        )
        var requestCount = 0
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, articleQueryService in
                requestCount += 1
                return try await articleQueryService.fetchArticleSearchSnapshot(request)
            },
            pageSize: 1
        )

        await controller.load(
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let markedArticle = try #require(controller.screenState.articles.first)
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let markedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: markedArticle.feedID,
            articleExternalID: markedArticle.articleExternalID
        )

        #expect(requestCount == 1)
        #expect(markedState?.isRead == true)
        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
    }
}
