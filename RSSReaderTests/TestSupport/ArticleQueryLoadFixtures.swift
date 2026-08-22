import Foundation
import SwiftData
@testable import RSSReader

nonisolated enum ArticleQueryLoadTestContract {
    static let articleCount = 10_000
    static let pageSize = 50
    static let feedCount = 4
    static let articlesPerFeed = articleCount / feedCount
    static let folderArticleCount = articlesPerFeed * 2
    static let searchMatchInterval = 100
    static let searchMatchCount = articleCount / searchMatchInterval
    static let starredInterval = 20
    static let maximumRequestedOverlayIdentityCount = 65
    static let maximumMaterializedOverlayStateCount = 65
    static let maximumAggregateMaterializedStateBatchSize = 256
    static let maximumAggregateRequestedIdentityBatchSize = 256
    static let cancellationCheckCount = 320
    static let maximumCancelledSearchCandidateCount = 64
    static let maximumSparseSearchCandidateCount = 10_128
    static let maximumSparseSearchFetchCount = 324

    struct DenseTiePaginationBudget {
        let maximumMaterializedCandidateCount: Int
        let maximumSearchScanBatchCount: Int
        let maximumFetchCount: Int
    }

    struct QueryBudget {
        let maximumMaterializedCandidateCount: Int
        let maximumFetchCount: Int
    }

    struct AggregateBudget {
        let maximumStateScanBatchCount: Int
        let maximumIdentityCountBatchCount: Int
        let maximumFetchQueryCount: Int
        let maximumFetchCountQueryCount: Int
    }

    static let initialPageBudgets = [
        QueryBudget(maximumMaterializedCandidateCount: 64, maximumFetchCount: 2),
        QueryBudget(maximumMaterializedCandidateCount: 64, maximumFetchCount: 2),
        QueryBudget(maximumMaterializedCandidateCount: 5_200, maximumFetchCount: 164),
        QueryBudget(maximumMaterializedCandidateCount: 128, maximumFetchCount: 4),
        QueryBudget(maximumMaterializedCandidateCount: 1_100, maximumFetchCount: 36)
    ]

    static let unreadAggregateBudget = AggregateBudget(
        maximumStateScanBatchCount: 20,
        maximumIdentityCountBatchCount: 20,
        maximumFetchQueryCount: 24,
        maximumFetchCountQueryCount: 24
    )
    static let starredAggregateBudget = AggregateBudget(
        maximumStateScanBatchCount: 20,
        maximumIdentityCountBatchCount: 8,
        maximumFetchQueryCount: 24,
        maximumFetchCountQueryCount: 8
    )
    static let denseTieUnreadDescendingBudget = DenseTiePaginationBudget(
        maximumMaterializedCandidateCount: 20_000,
        maximumSearchScanBatchCount: 300,
        maximumFetchCount: 700
    )
    static let denseTieStarredAscendingBudget = DenseTiePaginationBudget(
        maximumMaterializedCandidateCount: 11_000,
        maximumSearchScanBatchCount: 200,
        maximumFetchCount: 400
    )
}

struct ArticleQueryLoadFixture {
    enum SortDateDistribution {
        case unique
        case denseTie
    }

    let folderName: String
    let feedIDs: [UUID]
    let initiallyUnreadArticleIDsInAscendingSortOrder: [UUID]
    let initiallyStarredArticleIDsInAscendingSortOrder: [UUID]
    let mutationDate: Date

    @MainActor
    static func insert(
        into modelContext: ModelContext,
        sortDateDistribution: SortDateDistribution = .unique
    ) throws -> ArticleQueryLoadFixture {
        let folderName = "Query Load Folder"
        let folder = Folder(name: folderName)
        modelContext.insert(folder)

        let feeds = (0..<ArticleQueryLoadTestContract.feedCount).map { index in
            Feed(
                url: "https://example.com/query-load-\(index).xml",
                title: "Query Load Feed \(index)",
                folder: index < 2 ? folder : nil
            )
        }
        for feed in feeds {
            modelContext.insert(feed)
        }

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let insertionIndices: [Int]
        switch sortDateDistribution {
        case .unique:
            insertionIndices = Array(0..<ArticleQueryLoadTestContract.articleCount)
        case .denseTie:
            insertionIndices = Array(
                stride(from: 1, to: ArticleQueryLoadTestContract.articleCount, by: 2)
            ) + Array(
                stride(from: 0, to: ArticleQueryLoadTestContract.articleCount, by: 2)
            )
        }

        for index in insertionIndices {
            let feed = feeds[index / ArticleQueryLoadTestContract.articlesPerFeed]
            let externalID = "query-load-article-\(index)"
            let isSearchMatch = index.isMultiple(
                of: ArticleQueryLoadTestContract.searchMatchInterval
            )
            let searchableText = isSearchMatch
                ? "Query load article \(index) needle"
                : "Query load article \(index)"
            let contentHTML = isSearchMatch
                ? "<article><p>Query load <strong>needle</strong> \(index)</p><span>html-only-token</span></article>"
                : "<article><p>Query load body \(index)</p><span>html-only-token</span></article>"
            let article = Article(
                id: articleID(for: index),
                feedID: feed.id,
                feedTitle: feed.displayTitle,
                feedSiteURL: feed.siteURL,
                feedFolderName: feed.folder?.name,
                externalID: externalID,
                url: "https://example.com/query-load/articles/\(index)",
                title: "Query Load Article \(index)",
                contentHTML: contentHTML,
                searchableText: searchableText,
                publishedAt: sortDate(
                    for: index,
                    baseDate: baseDate,
                    distribution: sortDateDistribution
                ),
                fetchedAt: baseDate,
                createdAt: baseDate,
                updatedAt: baseDate
            )
            modelContext.insert(article)

            let isRead = index.isMultiple(of: 3)
            let isStarred = index.isMultiple(of: ArticleQueryLoadTestContract.starredInterval)
            if isRead || isStarred {
                modelContext.insert(
                    ArticleState(
                        articleExternalID: externalID,
                        feedID: feed.id,
                        isRead: isRead,
                        isStarred: isStarred,
                        updatedAt: baseDate
                    )
                )
            }
        }

        try modelContext.save()
        let articleIDsInAscendingSortOrder = (0..<ArticleQueryLoadTestContract.articleCount)
            .map(articleID(for:))
        return ArticleQueryLoadFixture(
            folderName: folderName,
            feedIDs: feeds.map(\.id),
            initiallyUnreadArticleIDsInAscendingSortOrder: articleIDsInAscendingSortOrder.enumerated()
                .compactMap { index, articleID in
                    index.isMultiple(of: 3) ? nil : articleID
                },
            initiallyStarredArticleIDsInAscendingSortOrder: articleIDsInAscendingSortOrder.enumerated()
                .compactMap { index, articleID in
                    index.isMultiple(of: ArticleQueryLoadTestContract.starredInterval)
                        ? articleID
                        : nil
                },
            mutationDate: baseDate.addingTimeInterval(1)
        )
    }

    private static func articleID(for index: Int) -> UUID {
        let suffix = String(format: "%012llX", UInt64(index + 1))
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    private static func sortDate(
        for index: Int,
        baseDate: Date,
        distribution: SortDateDistribution
    ) -> Date {
        switch distribution {
        case .unique:
            baseDate.addingTimeInterval(TimeInterval(index))
        case .denseTie:
            baseDate
        }
    }
}

@MainActor
final class ArticleQueryLoadProbe {
    private(set) var maximumRequestedOverlayIdentityCount = 0
    private(set) var maximumMaterializedOverlayStateCount = 0
    private(set) var searchableTextRebuildCount = 0
    private(set) var cancellationCheckCount = 0
    private(set) var materializedCandidateCount = 0
    private(set) var searchScanBatchCount = 0
    private let cancellationCheckLimit: Int?

    init(cancellationCheckLimit: Int? = nil) {
        self.cancellationCheckLimit = cancellationCheckLimit
    }

    func recordStateBatch(_ observation: ArticleStateQueryBatchObservation) {
        guard observation.kind == .overlay else { return }
        maximumRequestedOverlayIdentityCount = max(
            maximumRequestedOverlayIdentityCount,
            observation.requestedIdentityCount
        )
        maximumMaterializedOverlayStateCount = max(
            maximumMaterializedOverlayStateCount,
            observation.materializedStateCount
        )
    }

    func recordSearchableTextRebuild(articleID _: UUID) {
        searchableTextRebuildCount += 1
    }

    func recordSearchBatch(_ observation: ArticleSearchScanBatchObservation) {
        materializedCandidateCount += observation.scannedCandidateCount
        searchScanBatchCount += 1
    }

    func resetQueryMetrics() {
        maximumRequestedOverlayIdentityCount = 0
        maximumMaterializedOverlayStateCount = 0
        materializedCandidateCount = 0
        searchScanBatchCount = 0
    }

    func checkCancellation() throws {
        cancellationCheckCount += 1
        if cancellationCheckCount == cancellationCheckLimit {
            throw CancellationError()
        }
    }
}
