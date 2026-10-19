import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Pagination")
@MainActor
struct ArticlesScreenControllerPaginationTests {
    @Test
    func articlesScreenControllerAppendsPagesWithoutReplacingCurrentSessionSnapshot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-pages.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-first",
            title: "First",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        let second = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-second",
            title: "Second",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let third = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-third",
            title: "Third",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        var requests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                requests.append(request)
                if request.cursor == nil {
                    return ArticleSearchResultSnapshot(
                        articles: [first, second],
                        hasScopeContent: true,
                        nextCursor: makeArticleSearchCursor(seed: 2),
                        scopeMetric: ArticleScopeMetric(kind: .unread, count: 7)
                    )
                }
                return ArticleSearchResultSnapshot(
                    articles: [second, third],
                    hasScopeContent: true
                )
            },
            pageSize: 2
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            refreshesScopeMetric: true
        )
        let originalContext = controller.screenState.articleListSession.context
        await controller.loadNextPage(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(requests.map(\.limit) == [2, 2])
        #expect(requests.map(\.scopeMetricLoadingPolicy) == [.baseScope, .none])
        #expect(
            requests.map { $0.cursor?.repositoryCursor.sortDate }
                == [nil, Date(timeIntervalSince1970: 2)]
        )
        #expect(controller.visibleArticleIDs() == [first.id, second.id, third.id])
        #expect(controller.screenState.articleListSession.context == originalContext)
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)
        #expect(controller.screenState.articleListSession.scopeMetric?.count == 7)
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.unreadItemsSubtitle(count: 7)
        )
    }

    @Test
    func articlesScreenControllerSharesOneSessionOwnedNextPageLoadAcrossCallers() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-shared-page.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "shared-page-first",
            title: "First",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let second = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "shared-page-second",
            title: "Second",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let queryGate = ArticlesScreenNextPageQueryGate(
            firstPage: ArticleSearchResultSnapshot(
                articles: [first],
                hasScopeContent: true,
                nextCursor: makeArticleSearchCursor(seed: 1)
            ),
            nextPage: ArticleSearchResultSnapshot(
                articles: [second],
                hasScopeContent: true
            )
        )
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                try await queryGate.execute(request)
            },
            pageSize: 1
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let firstCaller = Task { @MainActor in
            await controller.loadNextPage(dependencies: harness.dependencies)
        }
        defer { firstCaller.cancel(); queryGate.releaseNextPage() }
        try await waitUntil("next page query suspended") {
            queryGate.hasSuspendedRequest
        }
        var secondCallerEntered = false
        let secondCaller = Task { @MainActor in
            secondCallerEntered = true
            return await controller.loadNextPage(dependencies: harness.dependencies)
        }
        try await waitUntil("coalesced pagination caller entered") { secondCallerEntered }

        #expect(queryGate.requests.count == 2)
        queryGate.releaseNextPage()
        let firstSnapshot = await firstCaller.value
        let secondSnapshot = await secondCaller.value

        #expect(firstSnapshot == secondSnapshot)
        #expect(firstSnapshot?.visibleArticleIDs == [first.id, second.id])
        #expect(firstSnapshot?.hasMorePages == false)
        #expect(controller.screenState.isLoadingNextPage == false)
    }

    @Test
    func articlesScreenControllerRejectsCancelledNextPageAfterSessionReplacement() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-stale-page.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "stale-page-first",
            title: "First"
        )
        let staleNext = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "stale-page-next",
            title: "Stale Next"
        )
        let replacement = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "stale-page-replacement",
            title: "Replacement"
        )
        let queryGate = ArticlesScreenStaleNextPageQueryGate(
            firstPage: ArticleSearchResultSnapshot(
                articles: [first],
                hasScopeContent: true,
                nextCursor: makeArticleSearchCursor(seed: 1)
            ),
            staleNextPage: ArticleSearchResultSnapshot(
                articles: [staleNext],
                hasScopeContent: true
            ),
            replacementPage: ArticleSearchResultSnapshot(
                articles: [replacement],
                hasScopeContent: true
            )
        )
        let controller = ArticlesScreenController(
            searchDebounceOperation: {},
            searchQueryOperation: { request, _ in
                try await queryGate.execute(request)
            },
            pageSize: 1
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let staleLoad = Task { @MainActor in
            await controller.loadNextPage(dependencies: harness.dependencies)
        }
        defer { staleLoad.cancel(); queryGate.releaseStaleNextPage() }
        try await waitUntil("stale next page suspended") {
            queryGate.hasSuspendedRequest
        }

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "replacement",
            dependencies: harness.dependencies
        )
        queryGate.releaseStaleNextPage()
        _ = await staleLoad.value

        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "replacement")
        #expect(controller.visibleArticleIDs() == [replacement.id])
        #expect(controller.screenState.isLoadingNextPage == false)
    }

    @Test
    func articleListContinuationCoordinatorExtendsReaderNavigationContextAtPageBoundary() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-reader-page.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-page-first",
            title: "First",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let second = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-page-second",
            title: "Second",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                if request.cursor == nil {
                    return ArticleSearchResultSnapshot(
                        articles: [first],
                        hasScopeContent: true,
                        nextCursor: makeArticleSearchCursor(seed: 1)
                    )
                }
                return ArticleSearchResultSnapshot(
                    articles: [second],
                    hasScopeContent: true
                )
            },
            pageSize: 1
        )
        let appState = AppState()
        appState.selectSidebarSelection(.feed(feed.id))
        appState.selectSidebarArticleFilter(.unread)

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        controller.markArticleAsReadInCurrentSession(first.id)
        appState.updateArticleNavigationContext(
            [first.id],
            sidebarSelection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            articleListSessionID: controller.currentArticleListSessionID
        )
        appState.selectArticle(first.id)

        #expect(
            ArticleListContinuationCoordinator.canLoadNextArticle(
                appState: appState,
                controller: controller
            )
        )
        let nextArticleID = await ArticleListContinuationCoordinator.loadAdjacentArticle(
            .next,
            appState: appState,
            controller: controller,
            dependencies: harness.dependencies
        )

        #expect(nextArticleID == second.id)
        #expect(appState.articleNavigationContextIDs == [first.id, second.id])
        #expect(appState.selectedArticleID == first.id)
        #expect(
            ArticleListContinuationCoordinator.canLoadNextArticle(
                appState: appState,
                controller: controller
            ) == false
        )
    }

    @Test
    func articleListContinuationCoordinatorPrefetchesBeforeReaderReachesPageBoundary() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-reader-lookahead.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-lookahead-first",
            title: "First",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        let second = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-lookahead-second",
            title: "Second",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let third = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-lookahead-third",
            title: "Third",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                if request.cursor == nil {
                    return ArticleSearchResultSnapshot(
                        articles: [first, second],
                        hasScopeContent: true,
                        nextCursor: makeArticleSearchCursor(seed: 2)
                    )
                }
                return ArticleSearchResultSnapshot(
                    articles: [third],
                    hasScopeContent: true
                )
            },
            pageSize: 2
        )
        let appState = AppState()
        appState.selectSidebarSelection(.feed(feed.id))

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        appState.updateArticleNavigationContext(
            [first.id, second.id],
            sidebarSelection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            articleListSessionID: controller.currentArticleListSessionID
        )
        appState.selectArticle(first.id)

        await ArticleListContinuationCoordinator.prefetchNextPageIfNeeded(
            minimumNextArticleCount: 2,
            appState: appState,
            controller: controller,
            dependencies: harness.dependencies
        )

        #expect(appState.articleNavigationContextIDs == [first.id, second.id, third.id])
        #expect(appState.selectedArticleID == first.id)
        #expect(appState.adjacentArticleIDs(.next, limit: 2) == [second.id, third.id])
    }

    @Test
    func articleListContinuationCoordinatorKeepsAppendedContextButRejectsRapidlyChangedReaderSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-reader-race.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-race-first",
            title: "First",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        let second = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-race-second",
            title: "Second",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let third = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "reader-race-third",
            title: "Third",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let queryGate = ArticlesScreenNextPageQueryGate(
            firstPage: ArticleSearchResultSnapshot(
                articles: [first, second],
                hasScopeContent: true,
                nextCursor: makeArticleSearchCursor(seed: 2)
            ),
            nextPage: ArticleSearchResultSnapshot(
                articles: [third],
                hasScopeContent: true
            )
        )
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                try await queryGate.execute(request)
            },
            pageSize: 2
        )
        let appState = AppState()
        appState.selectSidebarSelection(.feed(feed.id))

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        appState.updateArticleNavigationContext(
            [first.id, second.id],
            sidebarSelection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            articleListSessionID: controller.currentArticleListSessionID
        )
        appState.selectArticle(second.id)

        let continuationLoad = Task { @MainActor in
            await ArticleListContinuationCoordinator.loadAdjacentArticle(
                .next,
                appState: appState,
                controller: controller,
                dependencies: harness.dependencies
            )
        }
        defer { continuationLoad.cancel(); queryGate.releaseNextPage() }
        try await waitUntil("reader continuation query suspended") {
            queryGate.hasSuspendedRequest
        }
        appState.selectArticle(first.id)
        queryGate.releaseNextPage()
        let resolvedArticleID = await continuationLoad.value

        #expect(resolvedArticleID == nil)
        #expect(appState.selectedArticleID == first.id)
        #expect(appState.articleNavigationContextIDs == [first.id, second.id, third.id])
    }

    @Test
    func articlesScreenControllerResetsPaginationBeforeUsingCursorWithChangedUnreadSortOrder() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let settingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-sort-pages.xml"]).first
        )
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var articles: [Article] = []
        for index in 0..<5 {
            let article = try harness.insertArticle(
                feed: feed,
                externalID: "sort-page-\(index)",
                url: "https://example.com/articles/sort-page-\(index)",
                title: "Sort Page \(index)"
            )
            article.publishedAt = baseDate.addingTimeInterval(TimeInterval(index))
            article.querySortDate = try #require(article.publishedAt)
            articles.append(article)
        }
        try harness.saveModelContext()
        _ = try settingsRepository.update(
            AppSettingsUpdate(unreadArticleSortMode: .publishedAtAscending)
        )
        let controller = ArticlesScreenController(pageSize: 2)

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            refreshesScopeMetric: true
        )
        let ascendingCursor = try #require(
            controller.screenState.articleListSession.nextPageCursor
        )

        #expect(controller.screenState.articleListSession.context.sortMode == .publishedAtAscending)
        #expect(controller.screenState.articles.map(\.id) == [articles[0].id, articles[1].id])
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.unreadItemsSubtitle(count: 5)
        )

        _ = try settingsRepository.update(
            AppSettingsUpdate(unreadArticleSortMode: .publishedAtDescending)
        )
        await controller.loadNextPage(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.articleListSession.context.sortMode == .publishedAtAscending)
        #expect(controller.screenState.articleListSession.nextPageCursor == ascendingCursor)
        #expect(controller.screenState.articles.map(\.id) == [articles[0].id, articles[1].id])

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            refreshesScopeMetric: true
        )

        #expect(controller.screenState.articleListSession.context.selection == .feed(feed.id))
        #expect(controller.screenState.articleListSession.context.sortMode == .publishedAtDescending)
        #expect(controller.screenState.articles.map(\.id) == [articles[4].id, articles[3].id])
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.unreadItemsSubtitle(count: 5)
        )

        await controller.loadNextPage(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        #expect(
            controller.screenState.articles.map(\.id)
                == [articles[4].id, articles[3].id, articles[2].id, articles[1].id]
        )
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.unreadItemsSubtitle(count: 5)
        )
        await controller.loadNextPage(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        let loadedArticleIDs = controller.visibleArticleIDs()
        #expect(loadedArticleIDs == articles.reversed().map(\.id))
        #expect(Set(loadedArticleIDs).count == articles.count)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 5))
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)
    }


    @Test
    func articlesScreenControllerRetainsContinuationAfterFailureAndAllowsRetry() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-page-retry.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-retry-first",
            title: "First",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let second = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-retry-second",
            title: "Second",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        var nextPageAttemptCount = 0
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                guard request.cursor != nil else {
                    return ArticleSearchResultSnapshot(
                        articles: [first],
                        hasScopeContent: true,
                        nextCursor: makeArticleSearchCursor(seed: 1)
                    )
                }
                nextPageAttemptCount += 1
                if nextPageAttemptCount == 1 {
                    throw URLError(.cannotLoadFromNetwork)
                }
                return ArticleSearchResultSnapshot(
                    articles: [second],
                    hasScopeContent: true
                )
            },
            pageSize: 1
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let originalCursor = controller.screenState.articleListSession.nextPageCursor
        await controller.loadNextPage(dependencies: harness.dependencies)

        #expect(controller.visibleArticleIDs() == [first.id])
        #expect(controller.screenState.articleListSession.nextPageCursor == originalCursor)
        #expect(controller.screenState.canLoadNextPage)

        await controller.loadNextPage(dependencies: harness.dependencies)

        #expect(nextPageAttemptCount == 2)
        #expect(controller.visibleArticleIDs() == [first.id, second.id])
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)
    }


}
