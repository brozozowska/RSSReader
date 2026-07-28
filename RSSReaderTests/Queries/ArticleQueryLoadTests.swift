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
            articleStateRepository: harness.articleStateRepository
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
        for request in requests {
            let snapshot = try await queryService.fetchArticleSearchSnapshot(request)
            #expect(snapshot.articles.count == ArticleQueryLoadTestContract.pageSize)
            #expect(Set(snapshot.articles.map(\.id)).count == snapshot.articles.count)
            #expect(snapshot.nextCursor != nil)
        }
        #expect(
            loadProbe.maximumRequestedOverlayIdentityCount
                <= ArticleQueryLoadTestContract.maximumOverlayIdentityBatchSize
        )

        queryOperations.reset()
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
}
