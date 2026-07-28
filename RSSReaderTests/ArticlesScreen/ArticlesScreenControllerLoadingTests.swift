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
    func articlesScreenControllerAppendsPagesWithoutReplacingCurrentSessionSnapshot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/controller-pages.xml"]).first
        )
        let first = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-first",
            title: "First"
        )
        let second = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-second",
            title: "Second"
        )
        let third = makeArticleListItemDTO(
            feedID: feed.id,
            articleExternalID: "page-third",
            title: "Third"
        )
        var requests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                requests.append(request)
                if request.cursor == nil {
                    return ArticleSearchResultSnapshot(
                        articles: [first, second],
                        hasScopeContent: true,
                        nextCursor: ArticleSearchRequest.Cursor(repositoryOffset: 2)
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
            dependencies: harness.dependencies
        )
        let originalContext = controller.screenState.articleListSession.context
        await controller.loadNextPage(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(requests.map(\.limit) == [2, 2])
        #expect(requests.map { $0.cursor?.repositoryOffset } == [nil, 2])
        #expect(controller.visibleArticleIDs() == [first.id, second.id, third.id])
        #expect(controller.screenState.articleListSession.context == originalContext)
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
        #expect(derivedViewState.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
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
        var debounceInvocationCount = 0
        var queryRequests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchDebounceOperation: {
                debounceInvocationCount += 1
                if debounceInvocationCount == 1 {
                    try await Task.sleep(for: .seconds(60))
                }
            },
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
            debounceInvocationCount == 1
        }

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "new",
            dependencies: harness.dependencies
        )
        await supersededLoad.value

        #expect(ArticlesScreenSearchPolicy.debounceDuration == .milliseconds(250))
        #expect(debounceInvocationCount == 2)
        #expect(queryRequests.map(\.normalizedQuery) == ["new"])
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "new")
        #expect(controller.screenState.articles == [result])
    }

    @Test
    func articlesScreenControllerCancelsProductionSearchBetweenBoundedScanBatches() async throws {
        var scanObservations: [ArticleSearchScanBatchObservation] = []
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(),
            articleSearchScanBatchProbe: { observation in
                scanObservations.append(observation)
            }
        )
        _ = try ArticleQueryLoadFixture.insert(
            into: harness.modelContainer.mainContext
        )
        let controller = ArticlesScreenController(searchDebounceOperation: {})
        var scannedCandidateCountBeforeSupersedingInput = 0

        let supersedingLoad = Task { @MainActor in
            while scanObservations.contains(where: { observation in
                observation.normalizedQuery == "missing-query-token"
            }) == false {
                await Task.yield()
            }
            scannedCandidateCountBeforeSupersedingInput = scanObservations
                .filter { observation in
                    observation.normalizedQuery == "missing-query-token"
                }
                .reduce(0) { partialResult, observation in
                    partialResult + observation.scannedCandidateCount
                }

            await controller.load(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                searchText: "needle",
                dependencies: harness.dependencies
            )
        }

        await controller.load(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            searchText: "missing-query-token",
            dependencies: harness.dependencies
        )
        await supersedingLoad.value

        #expect(scannedCandidateCountBeforeSupersedingInput > 0)
        #expect(
            scannedCandidateCountBeforeSupersedingInput
                < ArticleQueryLoadTestContract.articleCount
        )
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "needle")
        #expect(controller.screenState.articles.count == ArticlesScreenPaginationPolicy.pageSize)
        #expect(controller.screenState.articles.allSatisfy { article in
            article.searchableText.localizedCaseInsensitiveContains("needle")
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
                hasScopeContent: true
            ),
            immediateSnapshot: ArticleSearchResultSnapshot(
                articles: [newResult],
                hasScopeContent: true
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
                dependencies: harness.dependencies
            )
        }
        try await waitUntil("old query suspended") {
            queryGate.hasSuspendedRequest
        }

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            searchText: "new",
            dependencies: harness.dependencies
        )
        queryGate.releaseSuspendedRequest()
        await staleLoad.value

        #expect(queryGate.requests.map(\.normalizedQuery) == ["old", "new"])
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "new")
        #expect(controller.screenState.articles == [newResult])
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
