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
        }
        #expect(
            loadProbe.maximumRequestedOverlayIdentityCount
                <= ArticleQueryLoadTestContract.maximumOverlayIdentityBatchSize
        )

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
            articleStateRepository: harness.articleStateRepository
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
                <= ArticleQueryLoadTestContract.maximumOverlayIdentityBatchSize
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
}
