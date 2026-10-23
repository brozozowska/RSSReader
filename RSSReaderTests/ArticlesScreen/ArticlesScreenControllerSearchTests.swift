import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Search")
@MainActor
struct ArticlesScreenControllerSearchTests {
    @Test(arguments: ["match", ""])
    func searchTransitionKeepsCommittedSnapshotAndBlocksActionsUntilQueryCompletes(_ query: String) async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let article = makeArticleListItemDTO(title: "Previous")
        let result = makeArticleListItemDTO(feedID: article.feedID, title: "Match")
        let gate = ArticlesScreenSearchQueryGate(
            suspendedQuery: query,
            suspendedSnapshot: ArticleSearchResultSnapshot(articles: [result], hasScopeContent: true),
            immediateSnapshot: ArticleSearchResultSnapshot(
                articles: [article], hasScopeContent: true,
                nextCursor: makeArticleSearchCursor(seed: 1),
                scopeMetric: ArticleScopeMetric(kind: .unread, count: 12)
            )
        )
        let controller = ArticlesScreenController(
            searchDebounceOperation: {}, searchQueryOperation: { request, _ in try await gate.execute(request) }
        )
        await controller.load(
            selection: .inbox, sidebarArticleFilter: .allItems, searchText: "seed",
            dependencies: harness.dependencies
        )
        let chrome = controller.screenState.derivedViewState().navigationChrome
        let animation = controller.screenState.listAnimationState
        let originalID = controller.currentArticleListSessionID
        let pending = Task { @MainActor in
            await controller.load(
                selection: .inbox, sidebarArticleFilter: .allItems, searchText: query,
                dependencies: harness.dependencies, retainsSessionFilterMutations: true
            )
        }
        defer { pending.cancel(); gate.releaseSuspendedRequest() }
        try await waitUntil("search query suspended") { gate.hasSuspendedRequest }
        #expect(controller.currentArticleListSessionID != originalID)
        #expect(controller.screenState.articles == [article])
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.derivedViewState().navigationChrome == chrome)
        #expect(controller.screenState.listAnimationState == animation)
        #expect(controller.screenState.showsPrimaryLoadingIndicator == false)
        #expect(controller.screenState.refreshState == .idle)
        #expect(controller.screenState.customRefreshState == .idle)
        #expect(controller.screenState.canLoadNextPage == false)
        #expect(controller.screenState.toolbarActions.isMarkAllAsReadEnabled == false)
        #expect(controller.screenState.derivedViewState().toolbarActions.isMarkAllAsReadEnabled == false)
        #expect(await controller.loadNextPage(dependencies: harness.dependencies) == nil)
        controller.toggleArticleReadStatus(
            article, selection: .inbox, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, isPreviewMode: true
        )
        controller.toggleStarredState(
            for: article, selection: .inbox, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, isPreviewMode: true
        )
        await controller.confirmMarkAllAsRead(
            searchText: query, selection: .inbox, sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies, isPreviewMode: true
        )
        #expect(controller.screenState.articles == [article])
        #expect(gate.requests.count == 2)

        gate.releaseSuspendedRequest()
        await pending.value
        #expect(controller.screenState.pendingSearchContext == nil)
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == query)
        #expect(controller.screenState.articles == [result])
        #expect(controller.screenState.articleListSession.scopeMetric?.count == 12)
        #expect(controller.screenState.listAnimationState.changeKind == .searchTransition)
        #expect(controller.screenState.listAnimationState.revision == animation.revision + 1)
        #expect(controller.screenState.listAnimationState.allowsAnimation(reduceMotion: false))
        #expect(controller.screenState.listAnimationState.animation(reduceMotion: true) == nil)
    }

    @Test(arguments: ["new", ""])
    func rapidSearchEditsRejectSupersededResultsWhileKeepingPresentation(_ newestQuery: String) async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let previous = makeArticleListItemDTO(title: "Committed")
        let stale = makeArticleListItemDTO(title: "Stale")
        let gate = ArticlesScreenSearchQueryGate(
            suspendedQuery: "old",
            suspendedSnapshot: ArticleSearchResultSnapshot(
                articles: [stale], hasScopeContent: true,
                scopeMetric: ArticleScopeMetric(kind: .unread, count: 99)
            ),
            immediateSnapshot: ArticleSearchResultSnapshot(
                articles: [previous], hasScopeContent: true,
                scopeMetric: ArticleScopeMetric(kind: .unread, count: 3)
            )
        )
        let controller = ArticlesScreenController(
            searchDebounceOperation: {}, searchQueryOperation: { request, _ in try await gate.execute(request) }
        )
        await controller.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        let staleLoad = Task { @MainActor in
            await controller.load(
                selection: .inbox, sidebarArticleFilter: .allItems, searchText: "old",
                dependencies: harness.dependencies
            )
        }
        defer { staleLoad.cancel(); gate.releaseSuspendedRequest() }
        try await waitUntil("superseded search suspended") { gate.hasSuspendedRequest }
        #expect(controller.screenState.articles == [previous])
        await controller.load(
            selection: .inbox, sidebarArticleFilter: .allItems, searchText: newestQuery,
            dependencies: harness.dependencies
        )
        let committed = controller.screenState.articleListSession
        let animation = controller.screenState.listAnimationState
        gate.releaseSuspendedRequest()
        await staleLoad.value
        #expect(controller.screenState.articleListSession == committed)
        #expect(committed.context.normalizedSearchText == newestQuery)
        #expect(committed.scopeMetric?.count == 3)
        #expect(controller.screenState.articles == [previous])
        #expect(controller.screenState.listAnimationState == animation)
        #expect(animation.changeKind == .searchTransition)
    }

    @Test(arguments: [false, true])
    func failedSearchPreservesLoadedOrEmptyCommittedSnapshot(_ startsEmpty: Bool) async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let previous = startsEmpty ? [] : [makeArticleListItemDTO()]
        let controller = ArticlesScreenController(
            searchDebounceOperation: {},
            searchQueryOperation: { request, _ in
                if request.normalizedQuery == "failure" { throw URLError(.timedOut) }
                return ArticleSearchResultSnapshot(articles: previous, hasScopeContent: true)
            }
        )
        await controller.load(
            selection: .inbox, sidebarArticleFilter: .allItems, searchText: "committed",
            dependencies: harness.dependencies
        )
        let context = controller.screenState.articleListSession.context
        let placeholder = controller.screenState.derivedViewState().searchPlaceholder
        let chrome = controller.screenState.derivedViewState().navigationChrome
        let animation = controller.screenState.listAnimationState
        await controller.load(
            selection: .inbox, sidebarArticleFilter: .allItems, searchText: "failure",
            dependencies: harness.dependencies
        )
        #expect(controller.screenState.articleListSession.context == context)
        #expect(controller.screenState.articles == previous)
        #expect(controller.screenState.phase == (startsEmpty ? .empty : .loaded))
        #expect(controller.screenState.derivedViewState().searchPlaceholder == placeholder)
        #expect(controller.screenState.derivedViewState().navigationChrome == chrome)
        #expect(controller.screenState.listAnimationState == animation)
        #expect(controller.screenState.refreshFeedback != nil)
        #expect(controller.screenState.pendingSearchContext == nil)
    }

    @Test
    func searchDebouncePreservesRowsAndCancellationRestoresCommittedContext() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let article = makeArticleListItemDTO()
        let gate = ArticlesScreenSearchDebounceGate()
        var requests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchDebounceOperation: gate.wait,
            searchQueryOperation: { request, _ in
                requests.append(request)
                return ArticleSearchResultSnapshot(articles: [article], hasScopeContent: true)
            }
        )
        await controller.load(selection: .inbox, sidebarArticleFilter: .allItems, dependencies: harness.dependencies)
        let animation = controller.screenState.listAnimationState
        let pending = Task { @MainActor in
            await controller.load(
                selection: .inbox, sidebarArticleFilter: .allItems, searchText: "cancelled",
                dependencies: harness.dependencies
            )
        }
        defer { pending.cancel(); gate.releaseSuspendedRequest() }
        try await waitUntil("search debounce suspended") { gate.hasSuspendedRequest }
        #expect(requests.count == 1)
        #expect(controller.screenState.articles == [article])
        #expect(controller.screenState.showsPrimaryLoadingIndicator == false)
        pending.cancel()
        gate.releaseSuspendedRequest()
        await pending.value
        #expect(requests.count == 1)
        #expect(controller.screenState.pendingSearchContext == nil)
        #expect(controller.screenState.articleListSession.context.normalizedSearchText.isEmpty)
        #expect(controller.screenState.articles == [article])
        #expect(controller.screenState.listAnimationState == animation)
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
        defer { supersededLoad.cancel(); debounceGate.releaseSuspendedRequest() }
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
        defer { staleLoad.cancel(); queryGate.releaseSuspendedRequest() }
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


}
