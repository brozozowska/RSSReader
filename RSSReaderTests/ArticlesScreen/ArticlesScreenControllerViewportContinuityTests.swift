import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Viewport Continuity")
@MainActor
struct ArticlesScreenControllerViewportContinuityTests {
    @Test
    func coveringArticleListCancelsInFlightReloadWithoutPublishingFirstPageSnapshot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/viewport-cancellation.xml"]).first
        )
        let materializedArticles = (0..<150).map { index in
            makeArticleListItemDTO(
                feedID: feed.id,
                articleExternalID: "covered-\(index)",
                title: "Covered \(index)",
                publishedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index))
            )
        }
        let queryGate = CoveredArticleListReloadQueryGate(
            initialSnapshot: ArticleSearchResultSnapshot(
                articles: materializedArticles,
                hasScopeContent: true
            ),
            suspendedSnapshot: ArticleSearchResultSnapshot(
                articles: Array(materializedArticles.prefix(50)),
                hasScopeContent: true,
                nextCursor: makeArticleSearchCursor(seed: 1)
            )
        )
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                try await queryGate.execute(request)
            },
            pageSize: 50
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let sessionID = controller.currentArticleListSessionID
        let reloadTask = Task { @MainActor in
            await controller.load(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                dependencies: harness.dependencies,
                retainsSessionFilterMutations: true
            )
        }
        try await waitForCoveredArticleListReload(queryGate)

        #expect(controller.suspendLoadsForCoveredArticleList())
        queryGate.releaseSuspendedReload()
        await reloadTask.value

        #expect(controller.currentArticleListSessionID == sessionID)
        #expect(controller.screenState.articles.map(\.id) == materializedArticles.map(\.id))
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)
    }

    @Test
    func coveredListReloadPreservesThreeMaterializedPagesForEveryRequiredScope() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/viewport-continuity.xml"]).first
        )
        let firstCursor = makeArticleSearchCursor(seed: 1)
        let secondCursor = makeArticleSearchCursor(seed: 2)
        let articles = (0..<150).map { index in
            makeArticleListItemDTO(
                feedID: feed.id,
                feedTitle: "Viewport Feed",
                articleExternalID: "viewport-\(index)",
                title: "Article \(index)",
                publishedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index)),
                isRead: false,
                isStarred: true
            )
        }
        let refreshedFirstPage = articles.prefix(50).enumerated().map { index, article in
            makeArticleListItemDTO(
                id: article.id,
                feedID: article.feedID,
                feedTitle: article.feedTitle,
                articleExternalID: article.articleExternalID,
                title: "Refreshed \(index)",
                publishedAt: article.publishedAt,
                isRead: article.isRead,
                isStarred: article.isStarred
            )
        }
        let requiredScopes: [(SidebarSelection, SidebarArticleFilter)] = [
            (.feed(feed.id), .allItems),
            (.folder("Viewport Folder"), .unread),
            (.inbox, .allItems),
            (.unread, .allItems),
            (.feed(feed.id), .starred)
        ]

        for (selection, sidebarArticleFilter) in requiredScopes {
            var firstPageLoadCount = 0
            let controller = ArticlesScreenController(
                searchQueryOperation: { request, _ in
                    if request.cursor == nil {
                        firstPageLoadCount += 1
                        return ArticleSearchResultSnapshot(
                            articles: firstPageLoadCount == 1
                                ? Array(articles.prefix(50))
                                : refreshedFirstPage,
                            hasScopeContent: true,
                            nextCursor: firstCursor
                        )
                    }
                    if request.cursor == firstCursor {
                        return ArticleSearchResultSnapshot(
                            articles: Array(articles[50..<100]),
                            hasScopeContent: true,
                            nextCursor: secondCursor
                        )
                    }
                    return ArticleSearchResultSnapshot(
                        articles: Array(articles[100..<150]),
                        hasScopeContent: true
                    )
                },
                pageSize: 50
            )

            await controller.load(
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                dependencies: harness.dependencies
            )
            await controller.loadNextPage(dependencies: harness.dependencies)
            await controller.loadNextPage(dependencies: harness.dependencies)

            let materializedSessionID = controller.currentArticleListSessionID
            let farArticleID = try #require(controller.screenState.articles.dropFirst(125).first?.id)
            #expect(controller.screenState.articles.count == 150)
            #expect(controller.screenState.articleListSession.nextPageCursor == nil)

            await controller.load(
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                dependencies: harness.dependencies,
                retainsSessionFilterMutations: true,
                preservesMaterializedSessionSnapshot: true
            )

            #expect(controller.currentArticleListSessionID == materializedSessionID)
            #expect(controller.screenState.articles.count == 150)
            #expect(controller.screenState.articles.contains(where: { $0.id == farArticleID }))
            #expect(controller.screenState.articleListSession.nextPageCursor == nil)
            #expect(controller.screenState.articles.first?.title == "Refreshed 0")
        }
    }

    @Test
    func materializedSnapshotMergeKeepsRetainedReadRowAndCanonicalOrder() {
        let newest = makeArticleListItemDTO(
            title: "Newest",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        let retained = makeArticleListItemDTO(
            title: "Retained",
            publishedAt: Date(timeIntervalSince1970: 200),
            isRead: true
        )
        let oldest = makeArticleListItemDTO(
            title: "Oldest",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let currentEntries = [
            ArticleListEntry(article: newest),
            ArticleListEntry(article: retained, membershipStatus: .retainedAfterFilterMutation),
            ArticleListEntry(article: oldest)
        ]

        let mergedEntries = ArticleListSessionMergePolicy.mergePreservingMaterializedSnapshot(
            currentEntries: currentEntries,
            loadedArticles: [newest],
            sortMode: .publishedAtDescending
        )

        #expect(mergedEntries.map(\.id) == [newest.id, retained.id, oldest.id])
        #expect(mergedEntries[1].membershipStatus == .retainedAfterFilterMutation)
    }
}

@MainActor
private final class CoveredArticleListReloadQueryGate {
    private let initialSnapshot: ArticleSearchResultSnapshot
    private let suspendedSnapshot: ArticleSearchResultSnapshot
    private var requestCount = 0
    private var continuation: CheckedContinuation<ArticleSearchResultSnapshot, Error>?

    init(
        initialSnapshot: ArticleSearchResultSnapshot,
        suspendedSnapshot: ArticleSearchResultSnapshot
    ) {
        self.initialSnapshot = initialSnapshot
        self.suspendedSnapshot = suspendedSnapshot
    }

    var hasSuspendedReload: Bool {
        continuation != nil
    }

    func execute(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        requestCount += 1
        guard requestCount > 1 else { return initialSnapshot }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func releaseSuspendedReload() {
        continuation?.resume(returning: suspendedSnapshot)
        continuation = nil
    }
}

@MainActor
private func waitForCoveredArticleListReload(
    _ queryGate: CoveredArticleListReloadQueryGate,
    timeout: Duration = .seconds(5)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if queryGate.hasSuspendedReload { return }
        await Task.yield()
    }

    Issue.record("Timed out waiting for covered article-list reload")
}
