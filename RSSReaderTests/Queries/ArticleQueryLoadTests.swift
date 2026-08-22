import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Queries / Article Query Load")
@MainActor
struct ArticleQueryLoadTests {
    @Test
    func tenThousandArticleFixtureKeepsPagesCancellationAndSearchNormalizationBounded() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let fixture = try ArticleQueryLoadFixture.insert(
            into: harness.modelContainer.mainContext
        )
        let queryOperations = SwiftDataRepositoryOperationCounter()
        let loadProbe = ArticleQueryLoadProbe()
        let repository = SwiftDataArticleRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceOperationRecorder: queryOperations.record,
            articleStateQueryBatchProbe: loadProbe.recordStateBatch,
            searchableTextRebuildProbe: loadProbe.recordSearchableTextRebuild
        )
        let queryService = DefaultArticleQueryService(
            articleRepository: repository,
            articleStateRepository: harness.articleStateRepository,
            feedRepository: harness.feedRepository,
            searchScanBatchProbe: loadProbe.recordSearchBatch
        )

        let requests = [
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending,
                limit: ArticleQueryLoadTestContract.pageSize
            ),
            ArticleSearchRequest(
                selection: .folder(fixture.folderName),
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending,
                limit: ArticleQueryLoadTestContract.pageSize
            ),
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: ArticleQueryLoadTestContract.pageSize
            ),
            ArticleSearchRequest(
                selection: .unread,
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending,
                limit: ArticleQueryLoadTestContract.pageSize
            ),
            ArticleSearchRequest(
                selection: .starred,
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending,
                limit: ArticleQueryLoadTestContract.pageSize
            )
        ]

        #expect(ArticleQueryLoadTestContract.articleCount >= 10_000)
        #expect(ArticleQueryLoadTestContract.folderArticleCount == 5_000)
        #expect(ArticleQueryLoadTestContract.searchMatchCount == 100)
        #expect(
            requests.count == ArticleQueryLoadTestContract.initialPageBudgets.count
        )
        for (request, budget) in zip(
            requests,
            ArticleQueryLoadTestContract.initialPageBudgets
        ) {
            queryOperations.reset()
            loadProbe.resetQueryMetrics()
            let snapshot = try await queryService.fetchArticleSearchSnapshot(request)
            #expect(snapshot.articles.count == ArticleQueryLoadTestContract.pageSize)
            #expect(Set(snapshot.articles.map(\.id)).count == snapshot.articles.count)
            #expect(snapshot.nextCursor != nil)
            #expect(
                loadProbe.materializedCandidateCount
                    <= budget.maximumMaterializedCandidateCount
            )
            #expect(queryOperations.fetchCount <= budget.maximumFetchCount)
            #expect(queryOperations.saveCount == 0)
            #expect(loadProbe.searchScanBatchCount > 0)
            #expect(
                loadProbe.maximumRequestedOverlayIdentityCount
                    <= ArticleQueryLoadTestContract.maximumRequestedOverlayIdentityCount
            )
            #expect(
                loadProbe.maximumMaterializedOverlayStateCount
                    <= ArticleQueryLoadTestContract.maximumMaterializedOverlayStateCount
            )
        }

        queryOperations.reset()
        loadProbe.resetQueryMetrics()
        for query in ["n", "ne", "nee", "need", "needle"] {
            let snapshot = try await queryService.fetchArticleSearchSnapshot(
                ArticleSearchRequest(
                    selection: .inbox,
                    sidebarArticleFilter: .allItems,
                    query: query,
                    sortMode: .publishedAtDescending,
                    limit: ArticleQueryLoadTestContract.pageSize
                )
            )
            #expect(snapshot.articles.count <= ArticleQueryLoadTestContract.pageSize)
        }
        let rawHTMLOnlySnapshot = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "html-only-token",
                sortMode: .publishedAtDescending,
                limit: ArticleQueryLoadTestContract.pageSize
            )
        )
        #expect(rawHTMLOnlySnapshot.articles.isEmpty)
        #expect(rawHTMLOnlySnapshot.hasScopeContent)
        #expect(loadProbe.searchableTextRebuildCount == 0)
        #expect(queryOperations.saveCount == 0)

        let cancellationProbe = ArticleQueryLoadProbe(
            cancellationCheckLimit: ArticleQueryLoadTestContract.cancellationCheckCount
        )
        let cancellingRepository = SwiftDataArticleRepository(
            modelContext: harness.modelContainer.mainContext,
            articleStateQueryBatchProbe: cancellationProbe.recordStateBatch,
            queryCancellationCheck: cancellationProbe.checkCancellation,
            searchableTextRebuildProbe: cancellationProbe.recordSearchableTextRebuild
        )
        let cancellingQueryService = DefaultArticleQueryService(
            articleRepository: cancellingRepository,
            articleStateRepository: harness.articleStateRepository,
            feedRepository: harness.feedRepository
        )

        await #expect(throws: CancellationError.self) {
            _ = try await cancellingQueryService.fetchArticleSearchSnapshot(
                ArticleSearchRequest(
                    selection: .inbox,
                    sidebarArticleFilter: .allItems,
                    query: "missing-query-token",
                    sortMode: .publishedAtDescending,
                    limit: ArticleQueryLoadTestContract.pageSize
                )
            )
        }
        #expect(
            cancellationProbe.cancellationCheckCount
                == ArticleQueryLoadTestContract.cancellationCheckCount
        )
        #expect(
            cancellationProbe.maximumRequestedOverlayIdentityCount
                <= ArticleQueryLoadTestContract.maximumRequestedOverlayIdentityCount
        )
        #expect(
            cancellationProbe.maximumMaterializedOverlayStateCount
                <= ArticleQueryLoadTestContract.maximumMaterializedOverlayStateCount
        )
        #expect(cancellationProbe.searchableTextRebuildCount == 0)
    }

    @Test
    func sparseSearchPaginatesToTerminalPageWithinIndependentWorkBudgets() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        _ = try ArticleQueryLoadFixture.insert(
            into: harness.modelContainer.mainContext
        )
        let operations = SwiftDataRepositoryOperationCounter()
        let loadProbe = ArticleQueryLoadProbe()
        let repository = SwiftDataArticleRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceOperationRecorder: operations.record,
            articleStateQueryBatchProbe: loadProbe.recordStateBatch,
            searchableTextRebuildProbe: loadProbe.recordSearchableTextRebuild
        )
        let queryService = DefaultArticleQueryService(
            articleRepository: repository,
            articleStateRepository: harness.articleStateRepository,
            feedRepository: harness.feedRepository,
            searchScanBatchProbe: loadProbe.recordSearchBatch
        )
        var cursor: ArticleSearchRequest.Cursor?
        var articleIDs: [UUID] = []

        repeat {
            let snapshot = try await queryService.fetchArticleSearchSnapshot(
                ArticleSearchRequest(
                    selection: .inbox,
                    sidebarArticleFilter: .allItems,
                    query: "needle",
                    sortMode: .publishedAtDescending,
                    limit: ArticleQueryLoadTestContract.pageSize,
                    cursor: cursor
                )
            )
            articleIDs.append(contentsOf: snapshot.articles.map(\.id))
            cursor = snapshot.nextCursor
        } while cursor != nil

        #expect(articleIDs.count == ArticleQueryLoadTestContract.searchMatchCount)
        #expect(Set(articleIDs).count == articleIDs.count)
        #expect(
            loadProbe.materializedCandidateCount
                <= ArticleQueryLoadTestContract.maximumSparseSearchCandidateCount
        )
        #expect(
            operations.fetchCount
                <= ArticleQueryLoadTestContract.maximumSparseSearchFetchCount
        )
        #expect(loadProbe.searchableTextRebuildCount == 0)
        #expect(operations.saveCount == 0)
    }

    @Test
    func denseTiePaginationKeepsStableOrderAndBoundedWorkAfterStateMutations() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let fixture = try ArticleQueryLoadFixture.insert(
            into: harness.modelContainer.mainContext,
            sortDateDistribution: .denseTie
        )
        let operations = SwiftDataRepositoryOperationCounter()
        let loadProbe = ArticleQueryLoadProbe()
        let repository = SwiftDataArticleRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceOperationRecorder: operations.record,
            articleStateQueryBatchProbe: loadProbe.recordStateBatch,
            searchableTextRebuildProbe: loadProbe.recordSearchableTextRebuild
        )
        let queryService = DefaultArticleQueryService(
            articleRepository: repository,
            articleStateRepository: harness.articleStateRepository,
            feedRepository: harness.feedRepository,
            searchScanBatchProbe: loadProbe.recordSearchBatch
        )

        let descendingUnreadIDs = try await fetchAllArticleIDs(
            queryService: queryService,
            selection: .unread,
            sortMode: .publishedAtDescending
        ) { firstPage in
            try setRead(
                true,
                for: firstPage,
                at: fixture.mutationDate,
                articleStateRepository: harness.articleStateRepository
            )
        }
        #expect(
            descendingUnreadIDs
                == Array(fixture.initiallyUnreadArticleIDsInAscendingSortOrder.reversed())
        )
        assertDenseTieBudget(
            ArticleQueryLoadTestContract.denseTieUnreadDescendingBudget,
            operations: operations,
            loadProbe: loadProbe
        )

        operations.reset()
        loadProbe.resetQueryMetrics()
        let ascendingStarredIDs = try await fetchAllArticleIDs(
            queryService: queryService,
            selection: .starred,
            sortMode: .publishedAtAscending
        ) { firstPage in
            try setStarred(
                false,
                for: firstPage,
                at: fixture.mutationDate,
                articleStateRepository: harness.articleStateRepository
            )
        }
        #expect(
            ascendingStarredIDs
                == fixture.initiallyStarredArticleIDsInAscendingSortOrder
        )
        assertDenseTieBudget(
            ArticleQueryLoadTestContract.denseTieStarredAscendingBudget,
            operations: operations,
            loadProbe: loadProbe
        )
    }

    @Test
    func tenThousandArticleFixtureChecksArchivedExistenceWithoutMaterializingArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        _ = try ArticleQueryLoadFixture.insert(
            into: harness.modelContainer.mainContext
        )
        let modelContext = harness.modelContainer.mainContext
        var descriptor = FetchDescriptor<Article>()
        descriptor.fetchLimit = 1
        let archivedArticle = try #require(try modelContext.fetch(descriptor).first)
        archivedArticle.archivedAt = .now
        try modelContext.save()

        let operations = SwiftDataRepositoryOperationCounter()
        let repository = SwiftDataArticleRepository(
            modelContext: modelContext,
            persistenceOperationRecorder: operations.record
        )

        #expect(try repository.hasArchivedArticles())
        #expect(operations.fetchCountQueryCount == 1)
        #expect(operations.fetchCount == 1)

        archivedArticle.archivedAt = nil
        try modelContext.save()
        operations.reset()

        #expect(try repository.hasArchivedArticles() == false)
        #expect(operations.fetchCountQueryCount == 1)
        #expect(operations.fetchCount == 1)
    }

    private func fetchAllArticleIDs(
        queryService: any ArticleQueryService,
        selection: SidebarSelection,
        sortMode: ArticleSortMode,
        mutateAfterFirstPage: ([ArticleListItemDTO]) throws -> Void
    ) async throws -> [UUID] {
        var cursor: ArticleSearchRequest.Cursor?
        var articleIDs: [UUID] = []
        var isFirstPage = true

        repeat {
            let snapshot = try await queryService.fetchArticleSearchSnapshot(
                ArticleSearchRequest(
                    selection: selection,
                    sidebarArticleFilter: .allItems,
                    query: "",
                    sortMode: sortMode,
                    limit: ArticleQueryLoadTestContract.pageSize,
                    cursor: cursor
                )
            )
            let pageIDs = snapshot.articles.map(\.id)
            #expect(snapshot.articles.count <= ArticleQueryLoadTestContract.pageSize)
            #expect(Set(pageIDs).count == pageIDs.count)
            #expect(Set(articleIDs).isDisjoint(with: pageIDs))
            articleIDs.append(contentsOf: pageIDs)
            cursor = snapshot.nextCursor

            if isFirstPage {
                try mutateAfterFirstPage(snapshot.articles)
                isFirstPage = false
            }
        } while cursor != nil

        return articleIDs
    }

    private func setRead(
        _ isRead: Bool,
        for articles: [ArticleListItemDTO],
        at date: Date,
        articleStateRepository: any ArticleStateRepository
    ) throws {
        for (feedID, items) in Dictionary(grouping: articles, by: \.feedID) {
            _ = try articleStateRepository.bulkSetRead(
                feedID: feedID,
                articleExternalIDs: items.map(\.articleExternalID),
                isRead: isRead,
                at: date
            )
        }
    }

    private func setStarred(
        _ isStarred: Bool,
        for articles: [ArticleListItemDTO],
        at date: Date,
        articleStateRepository: any ArticleStateRepository
    ) throws {
        for (feedID, items) in Dictionary(grouping: articles, by: \.feedID) {
            _ = try articleStateRepository.bulkSetStarred(
                feedID: feedID,
                articleExternalIDs: items.map(\.articleExternalID),
                isStarred: isStarred,
                at: date
            )
        }
    }

    private func assertDenseTieBudget(
        _ budget: ArticleQueryLoadTestContract.DenseTiePaginationBudget,
        operations: SwiftDataRepositoryOperationCounter,
        loadProbe: ArticleQueryLoadProbe
    ) {
        #expect(
            loadProbe.materializedCandidateCount
                >= ArticleQueryLoadTestContract.articleCount
        )
        #expect(
            loadProbe.materializedCandidateCount
                <= budget.maximumMaterializedCandidateCount
        )
        #expect(loadProbe.searchScanBatchCount <= budget.maximumSearchScanBatchCount)
        #expect(operations.fetchCount <= budget.maximumFetchCount)
        #expect(operations.saveCount == 0)
        #expect(loadProbe.searchableTextRebuildCount == 0)
        #expect(
            loadProbe.maximumRequestedOverlayIdentityCount
                <= ArticleQueryLoadTestContract.maximumRequestedOverlayIdentityCount
        )
        #expect(
            loadProbe.maximumMaterializedOverlayStateCount
                <= ArticleQueryLoadTestContract.maximumMaterializedOverlayStateCount
        )
    }
}
