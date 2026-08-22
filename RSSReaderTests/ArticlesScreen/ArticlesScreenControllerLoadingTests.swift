import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Loading")
@MainActor
struct ArticlesScreenControllerLoadingTests {
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
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.navigationTitle == "controller-load.xml")
        #expect(controller.screenState.articles.count == 1)
        #expect(controller.screenState.articles.first?.title == "Controller Load")
    }

    @Test
    func articlesScreenControllerReusesControllerAndReplacesSnapshotWhenSidebarSelectionChanges() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/controller-first.xml",
                "https://example.com/controller-second.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let firstArticle = try harness.insertArticle(
            feed: firstFeed,
            externalID: "controller-first-article",
            url: "https://example.com/articles/controller-first",
            title: "Controller First"
        )
        let secondArticle = try harness.insertArticle(
            feed: secondFeed,
            externalID: "controller-second-article",
            url: "https://example.com/articles/controller-second",
            title: "Controller Second"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(firstFeed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        #expect(controller.screenState.articles.map(\.id) == [firstArticle.id])

        await controller.load(
            selection: .feed(secondFeed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articleListSession.context.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articles.map(\.id) == [secondArticle.id])
    }

    @Test
    func articlesScreenControllerReplacesDelayedScopeAndNavigationChromeAsOneSnapshot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/chrome-first.xml",
                "https://example.com/chrome-second.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let firstArticle = makeArticleListItemDTO(
            feedID: firstFeed.id,
            articleExternalID: "chrome-first",
            title: "First Chrome",
            isRead: false
        )
        let secondArticle = makeArticleListItemDTO(
            feedID: secondFeed.id,
            articleExternalID: "chrome-second",
            title: "Second Chrome",
            isRead: false
        )
        let queryGate = ArticlesScreenSelectionQueryGate(
            suspendedSelection: .feed(secondFeed.id),
            immediateSnapshot: ArticleSearchResultSnapshot(
                articles: [firstArticle],
                hasScopeContent: true
            ),
            suspendedSnapshot: ArticleSearchResultSnapshot(
                articles: [secondArticle],
                hasScopeContent: true,
                nextCursor: makeArticleSearchCursor(seed: 1),
                scopeMetric: ArticleScopeMetric(kind: .unread, count: 12)
            )
        )
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                try await queryGate.execute(request)
            }
        )

        await controller.load(
            selection: .feed(firstFeed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        let firstChrome = controller.screenState.derivedViewState().navigationChrome

        let presentationLoad = try #require(controller.prepareForPresentation(
            selection: .feed(secondFeed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        ))
        let preparedChrome = controller.screenState.derivedViewState().navigationChrome
        #expect(controller.screenState.phase == .loading)
        #expect(controller.screenState.articles.isEmpty)
        #expect(preparedChrome != firstChrome)
        #expect(preparedChrome.sessionContext.selection == .feed(secondFeed.id))
        #expect(preparedChrome.title == secondFeed.displayTitle)
        #expect(preparedChrome.subtitle == ReadingLocalization.loadingArticlesTitle)

        try await waitUntil("second feed query suspended") {
            queryGate.hasSuspendedRequest
        }
        let coalescedLoad = Task { @MainActor in
            await controller.load(
                selection: .feed(secondFeed.id),
                sidebarArticleFilter: .unread,
                dependencies: harness.dependencies,
                retainsSessionFilterMutations: true
            )
        }
        await Task.yield()

        #expect(controller.screenState.phase == .loading)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.derivedViewState().navigationChrome == preparedChrome)
        #expect(queryGate.requestCount == 2)

        queryGate.releaseSuspendedRequest()
        await presentationLoad.value
        await coalescedLoad.value

        let secondChrome = controller.screenState.derivedViewState().navigationChrome
        #expect(secondChrome.sessionContext.selection == .feed(secondFeed.id))
        #expect(secondChrome.title == secondFeed.displayTitle)
        #expect(secondChrome.subtitle == ReadingLocalization.unreadItemsSubtitle(count: 12))
        #expect(controller.screenState.articles == [secondArticle])
    }

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
        try await waitUntil("next page query suspended") {
            queryGate.hasSuspendedRequest
        }
        let secondCaller = Task { @MainActor in
            await controller.loadNextPage(dependencies: harness.dependencies)
        }
        await Task.yield()

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
    func articlesScreenControllerIncludesArchivedArticlesForCurrentSelectionUntilCleanupDeletesThem() async throws {
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
            sidebarArticleFilter: .allItems,
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
            sidebarArticleFilter: .allItems,
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
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
    }

    @Test
    func articlesScreenControllerLoadsSearchResultsIntoSessionSnapshotAndDerivedState() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/search-ui.xml"]).first)
        let matchingArticle = try harness.insertArticle(
            feed: feed,
            externalID: "search-ui-match",
            url: "https://example.com/articles/search-ui-match",
            title: "Needle Result"
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "search-ui-miss",
            url: "https://example.com/articles/search-ui-miss",
            title: "Other Result"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "needle",
            dependencies: harness.dependencies
        )

        let derivedViewState = controller.screenState.derivedViewState()

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "needle")
        #expect(controller.screenState.articles.map(\.id) == [matchingArticle.id])
        #expect(controller.visibleArticleIDs() == [matchingArticle.id])
        #expect(derivedViewState.visibleArticles.map(\.id) == [matchingArticle.id])
        #expect(derivedViewState.navigationChrome.subtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
        #expect(derivedViewState.toolbarActions.isMarkAllAsReadEnabled)
    }

    @Test
    func articlesScreenControllerDistinguishesEmptySelectionFromEmptySearchResults() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feedWithArticles = try #require(try harness.insertFeeds(urls: ["https://example.com/search-empty.xml"]).first)
        let emptyFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/search-empty-selection.xml"]).first)
        _ = try harness.insertArticle(
            feed: feedWithArticles,
            externalID: "search-empty-article",
            url: "https://example.com/articles/search-empty-article",
            title: "Existing Article"
        )
        let searchController = ArticlesScreenController()
        let emptySelectionController = ArticlesScreenController()

        await searchController.load(
            selection: .feed(feedWithArticles.id),
            sidebarArticleFilter: .allItems,
            searchText: "missing",
            dependencies: harness.dependencies
        )
        await emptySelectionController.load(
            selection: .feed(emptyFeed.id),
            sidebarArticleFilter: .allItems,
            searchText: "missing",
            dependencies: harness.dependencies
        )

        let emptySearchViewState = searchController.screenState.derivedViewState()
        let emptySelectionViewState = emptySelectionController.screenState.derivedViewState()

        #expect(searchController.screenState.phase == .empty)
        #expect(emptySearchViewState.searchPlaceholder?.title == ReadingLocalization.noSearchResultsTitle)
        #expect(emptySearchViewState.searchPlaceholder?.description == ReadingLocalization.noSearchResultsDescription(query: "missing"))

        #expect(emptySelectionController.screenState.phase == .empty)
        #expect(emptySelectionViewState.searchPlaceholder == nil)
        #expect(emptySelectionController.screenState.placeholder?.title == ReadingLocalization.noArticlesTitle)
    }

    @Test
    func articlesScreenControllerDebouncesSearchInputAndCancelsSupersededRequest() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/search-debounce.xml"]).first
        )
        let result = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "new-query-result",
            title: "New Query Result"
        )
        let debounceGate = ArticlesScreenSearchDebounceGate()
        var queryRequests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchDebounceOperation: debounceGate.wait,
            searchQueryOperation: { request, _ in
                queryRequests.append(request)
                return ArticleSearchResultSnapshot(
                    articles: [result],
                    hasScopeContent: true
                )
            }
        )

        let supersededLoad = Task { @MainActor in
            await controller.load(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                searchText: "n",
                dependencies: harness.dependencies
            )
        }
        try await waitUntil("first search entered debounce") {
            debounceGate.hasSuspendedRequest
        }

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "new",
            dependencies: harness.dependencies
        )
        debounceGate.releaseSuspendedRequest()
        await supersededLoad.value

        #expect(ArticlesScreenSearchPolicy.debounceDuration == .milliseconds(250))
        #expect(debounceGate.invocationCount == 2)
        #expect(queryRequests.map(\.normalizedQuery) == ["new"])
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "new")
        #expect(controller.screenState.articles == [result])
    }

    @Test
    func articlesScreenControllerCancelsProductionSearchBetweenBoundedScanBatches() async throws {
        let cancelledQuery = "missing-query-token"
        let publishedQuery = "needle"
        let cancellationGate = ArticlesScreenProductionSearchCancellationGate(
            cancelledQuery: cancelledQuery
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(),
            articleSearchScanBatchProbe: cancellationGate.observe
        )
        _ = try ArticleQueryLoadFixture.insert(
            into: harness.modelContainer.mainContext
        )
        let controller = ArticlesScreenController(searchDebounceOperation: {})

        let cancelledLoad = Task { @MainActor in
            await controller.load(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                searchText: cancelledQuery,
                dependencies: harness.dependencies
            )
        }
        defer {
            cancelledLoad.cancel()
            cancellationGate.releaseCancelledQuery()
        }
        let firstCancelledBatch = try await cancellationGate.waitForFirstCancelledBatch()
        let scannedCandidateCountAtSupersedingInput = cancellationGate.cancelledQueryScannedCandidateCount

        #expect(cancellationGate.isCancelledQuerySuspended)
        await controller.load(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            searchText: publishedQuery,
            dependencies: harness.dependencies
        )
        cancellationGate.releaseCancelledQuery()
        await cancelledLoad.value

        let finalCancelledQueryScannedCandidateCount = cancellationGate.cancelledQueryScannedCandidateCount

        #expect(firstCancelledBatch.scannedCandidateCount > 0)
        #expect(scannedCandidateCountAtSupersedingInput > 0)
        #expect(
            finalCancelledQueryScannedCandidateCount
                == scannedCandidateCountAtSupersedingInput
        )
        #expect(
            finalCancelledQueryScannedCandidateCount
                <= ArticleQueryLoadTestContract.maximumCancelledSearchCandidateCount
        )
        #expect(cancellationGate.scannedCandidateCount(for: publishedQuery) > 0)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == publishedQuery)
        #expect(controller.screenState.articles.count == ArticlesScreenPaginationPolicy.pageSize)
        #expect(controller.screenState.articles.allSatisfy { article in
            guard let index = Int(article.articleExternalID.split(separator: "-").last ?? "") else {
                return false
            }
            return index.isMultiple(of: ArticleQueryLoadTestContract.searchMatchInterval)
        })
    }

    @Test
    func articlesScreenControllerRejectsStaleResultAfterNewerGenerationCompletes() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/search-generation.xml"]).first
        )
        let oldResult = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "old-result",
            title: "Old Result"
        )
        let newResult = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "new-result",
            title: "New Result"
        )
        let queryGate = ArticlesScreenSearchQueryGate(
            suspendedQuery: "old",
            suspendedSnapshot: ArticleSearchResultSnapshot(
                articles: [oldResult],
                hasScopeContent: true,
                scopeMetric: ArticleScopeMetric(kind: .unread, count: 99)
            ),
            immediateSnapshot: ArticleSearchResultSnapshot(
                articles: [newResult],
                hasScopeContent: true,
                scopeMetric: ArticleScopeMetric(kind: .unread, count: 3)
            )
        )
        let controller = ArticlesScreenController(
            searchDebounceOperation: {},
            searchQueryOperation: { request, _ in
                try await queryGate.execute(request)
            }
        )

        let staleLoad = Task { @MainActor in
            await controller.load(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                searchText: "old",
                dependencies: harness.dependencies,
                refreshesScopeMetric: true
            )
        }
        try await waitUntil("old query suspended") {
            queryGate.hasSuspendedRequest
        }

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "new",
            dependencies: harness.dependencies,
            refreshesScopeMetric: true
        )
        let newestChrome = controller.screenState.derivedViewState().navigationChrome
        queryGate.releaseSuspendedRequest()
        await staleLoad.value

        #expect(queryGate.requests.map(\.normalizedQuery) == ["old", "new"])
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "new")
        #expect(controller.screenState.articles == [newResult])
        #expect(controller.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: 3))
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 3))
        #expect(controller.screenState.derivedViewState().navigationChrome == newestChrome)
    }

    @Test
    func articlesScreenControllerReusesBaseScopeMetricAcrossSearchQueriesWithoutAggregateReload() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/search-scope-metric.xml"]).first
        )
        let article = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "search-scope-metric",
            title: "Needle"
        )
        var requests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchDebounceOperation: {},
            searchQueryOperation: { request, _ in
                requests.append(request)
                return ArticleSearchResultSnapshot(
                    articles: [article],
                    hasScopeContent: true,
                    scopeMetric: request.scopeMetricLoadingPolicy == .baseScope
                        ? ArticleScopeMetric(kind: .unread, count: 80)
                        : nil
                )
            }
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            refreshesScopeMetric: true
        )
        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "n",
            dependencies: harness.dependencies
        )
        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "ne",
            dependencies: harness.dependencies
        )

        #expect(requests.map(\.scopeMetricLoadingPolicy) == [.baseScope, .none, .none])
        #expect(controller.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: 80))
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 80))
    }

    @Test
    func articlesScreenControllerUsesSingleSearchSnapshotForEmptyContentKind() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/search-single-snapshot.xml"]).first
        )
        var queryRequests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchDebounceOperation: {},
            searchQueryOperation: { request, _ in
                queryRequests.append(request)
                return ArticleSearchResultSnapshot(
                    articles: [],
                    hasScopeContent: true
                )
            }
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "missing",
            dependencies: harness.dependencies
        )

        #expect(queryRequests.count == 1)
        #expect(queryRequests.first?.normalizedQuery == "missing")
        #expect(controller.screenState.emptyContentKind == .searchResults)
        #expect(
            controller.screenState.derivedViewState().searchPlaceholder?.title
                == ReadingLocalization.noSearchResultsTitle
        )
    }

    @Test
    func articlesScreenControllerUsesNewestFirstForAllItemsRegardlessOfUnreadSortSetting() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/all-items-sort.xml"]).first)
        let oldDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let newDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 2)))
        let oldArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "all-items-old",
            url: "https://example.com/articles/all-items-old",
            title: "Old Article",
            publishedAt: oldDate,
            fetchedAt: oldDate
        )
        let newArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "all-items-new",
            url: "https://example.com/articles/all-items-new",
            title: "New Article",
            publishedAt: newDate,
            fetchedAt: newDate
        )
        harness.modelContainer.mainContext.insert(oldArticle)
        harness.modelContainer.mainContext.insert(newArticle)
        try harness.modelContainer.mainContext.save()
        _ = try repository.update(AppSettingsUpdate(unreadArticleSortMode: .publishedAtAscending))
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.articles.map(\.id) == [newArticle.id, oldArticle.id])
    }

    @Test
    func articlesScreenControllerUsesUnreadSortSettingForUnreadFilter() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/unread-sort.xml"]).first)
        let oldDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let newDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 2)))
        let oldArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "unread-old",
            url: "https://example.com/articles/unread-old",
            title: "Old Unread Article",
            publishedAt: oldDate,
            fetchedAt: oldDate
        )
        let newArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "unread-new",
            url: "https://example.com/articles/unread-new",
            title: "New Unread Article",
            publishedAt: newDate,
            fetchedAt: newDate
        )
        harness.modelContainer.mainContext.insert(oldArticle)
        harness.modelContainer.mainContext.insert(newArticle)
        try harness.modelContainer.mainContext.save()
        _ = try repository.update(AppSettingsUpdate(unreadArticleSortMode: .publishedAtAscending))
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.articles.map(\.id) == [oldArticle.id, newArticle.id])
    }
}

@MainActor
private final class ArticlesScreenSearchQueryGate {
    let suspendedQuery: String
    let suspendedSnapshot: ArticleSearchResultSnapshot
    let immediateSnapshot: ArticleSearchResultSnapshot
    private(set) var requests: [ArticleSearchRequest] = []
    private var continuation: CheckedContinuation<ArticleSearchResultSnapshot, Error>?

    init(
        suspendedQuery: String,
        suspendedSnapshot: ArticleSearchResultSnapshot,
        immediateSnapshot: ArticleSearchResultSnapshot
    ) {
        self.suspendedQuery = suspendedQuery
        self.suspendedSnapshot = suspendedSnapshot
        self.immediateSnapshot = immediateSnapshot
    }

    var hasSuspendedRequest: Bool {
        continuation != nil
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        requests.append(request)
        guard request.normalizedQuery == suspendedQuery else {
            return immediateSnapshot
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func releaseSuspendedRequest() {
        continuation?.resume(returning: suspendedSnapshot)
        continuation = nil
    }
}

@MainActor
private final class ArticlesScreenSelectionQueryGate {
    let suspendedSelection: SidebarSelection
    let immediateSnapshot: ArticleSearchResultSnapshot
    let suspendedSnapshot: ArticleSearchResultSnapshot
    private(set) var requestCount = 0
    private var continuation: CheckedContinuation<ArticleSearchResultSnapshot, Error>?

    init(
        suspendedSelection: SidebarSelection,
        immediateSnapshot: ArticleSearchResultSnapshot,
        suspendedSnapshot: ArticleSearchResultSnapshot
    ) {
        self.suspendedSelection = suspendedSelection
        self.immediateSnapshot = immediateSnapshot
        self.suspendedSnapshot = suspendedSnapshot
    }

    var hasSuspendedRequest: Bool {
        continuation != nil
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        requestCount += 1
        guard request.selection == suspendedSelection else {
            return immediateSnapshot
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func releaseSuspendedRequest() {
        continuation?.resume(returning: suspendedSnapshot)
        continuation = nil
    }
}

@MainActor
private final class ArticlesScreenNextPageQueryGate {
    let firstPage: ArticleSearchResultSnapshot
    let nextPage: ArticleSearchResultSnapshot
    private(set) var requests: [ArticleSearchRequest] = []
    private var continuation: CheckedContinuation<ArticleSearchResultSnapshot, Error>?

    init(
        firstPage: ArticleSearchResultSnapshot,
        nextPage: ArticleSearchResultSnapshot
    ) {
        self.firstPage = firstPage
        self.nextPage = nextPage
    }

    var hasSuspendedRequest: Bool {
        continuation != nil
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        requests.append(request)
        guard request.cursor != nil else { return firstPage }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func releaseNextPage() {
        continuation?.resume(returning: nextPage)
        continuation = nil
    }
}

@MainActor
private final class ArticlesScreenStaleNextPageQueryGate {
    let firstPage: ArticleSearchResultSnapshot
    let staleNextPage: ArticleSearchResultSnapshot
    let replacementPage: ArticleSearchResultSnapshot
    private var continuation: CheckedContinuation<ArticleSearchResultSnapshot, Error>?

    init(
        firstPage: ArticleSearchResultSnapshot,
        staleNextPage: ArticleSearchResultSnapshot,
        replacementPage: ArticleSearchResultSnapshot
    ) {
        self.firstPage = firstPage
        self.staleNextPage = staleNextPage
        self.replacementPage = replacementPage
    }

    var hasSuspendedRequest: Bool {
        continuation != nil
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        if request.cursor != nil {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }
        return request.normalizedQuery.isEmpty ? firstPage : replacementPage
    }

    func releaseStaleNextPage() {
        continuation?.resume(returning: staleNextPage)
        continuation = nil
    }
}

@MainActor
private final class ArticlesScreenSearchDebounceGate {
    private(set) var invocationCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var hasSuspendedRequest: Bool {
        continuation != nil
    }

    func wait() async throws {
        invocationCount += 1
        guard invocationCount == 1 else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func releaseSuspendedRequest() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ArticlesScreenProductionSearchCancellationGate {
    private enum WaitError: Error {
        case progressStreamFinished
        case timedOut
    }

    private let cancelledQuery: String
    private let progressStream: AsyncStream<ArticleSearchScanBatchObservation>
    private let progressContinuation: AsyncStream<ArticleSearchScanBatchObservation>.Continuation
    private var didSignalFirstCancelledBatch = false
    private var cancelledQueryContinuation: CheckedContinuation<Void, Never>?
    private var observations: [ArticleSearchScanBatchObservation] = []

    init(cancelledQuery: String) {
        self.cancelledQuery = cancelledQuery
        let progress = AsyncStream.makeStream(of: ArticleSearchScanBatchObservation.self)
        self.progressStream = progress.stream
        self.progressContinuation = progress.continuation
    }

    var cancelledQueryScannedCandidateCount: Int {
        scannedCandidateCount(for: cancelledQuery)
    }

    var isCancelledQuerySuspended: Bool {
        cancelledQueryContinuation != nil
    }

    func scannedCandidateCount(for query: String) -> Int {
        observations
            .filter { $0.normalizedQuery == query }
            .reduce(0) { partialResult, observation in
                partialResult + observation.scannedCandidateCount
            }
    }

    func observe(_ observation: ArticleSearchScanBatchObservation) async {
        observations.append(observation)
        guard observation.normalizedQuery == cancelledQuery,
              didSignalFirstCancelledBatch == false else {
            return
        }

        didSignalFirstCancelledBatch = true
        progressContinuation.yield(observation)
        progressContinuation.finish()
        await withCheckedContinuation { continuation in
            cancelledQueryContinuation = continuation
        }
    }

    func releaseCancelledQuery() {
        cancelledQueryContinuation?.resume()
        cancelledQueryContinuation = nil
    }

    func waitForFirstCancelledBatch(
        timeout: Duration = .seconds(5)
    ) async throws -> ArticleSearchScanBatchObservation {
        let progressStream = progressStream
        return try await withThrowingTaskGroup(
            of: ArticleSearchScanBatchObservation.self
        ) { group in
            group.addTask {
                for await observation in progressStream {
                    return observation
                }
                throw WaitError.progressStreamFinished
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WaitError.timedOut
            }

            guard let observation = try await group.next() else {
                throw WaitError.progressStreamFinished
            }
            group.cancelAll()
            return observation
        }
    }
}

@MainActor
private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(5),
    condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if condition() { return }
        await Task.yield()
    }

    Issue.record("Timed out waiting for \(description)")
}
