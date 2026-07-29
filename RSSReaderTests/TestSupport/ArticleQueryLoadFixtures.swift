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
    static let maximumOverlayIdentityBatchSize = 65
    static let cancellationCheckCount = 320
    static let maximumSparseSearchCandidateCount = 10_128
    static let maximumSparseSearchFetchCount = 324

    struct QueryBudget {
        let maximumMaterializedCandidateCount: Int
        let maximumFetchCount: Int
    }

    static let initialPageBudgets = [
        QueryBudget(maximumMaterializedCandidateCount: 64, maximumFetchCount: 2),
        QueryBudget(maximumMaterializedCandidateCount: 64, maximumFetchCount: 2),
        QueryBudget(maximumMaterializedCandidateCount: 5_200, maximumFetchCount: 164),
        QueryBudget(maximumMaterializedCandidateCount: 128, maximumFetchCount: 4),
        QueryBudget(maximumMaterializedCandidateCount: 1_100, maximumFetchCount: 36)
    ]
}

struct ArticleQueryLoadFixture {
    let folderName: String
    let feedIDs: [UUID]

    @MainActor
    static func insert(into modelContext: ModelContext) throws -> ArticleQueryLoadFixture {
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
        for index in 0..<ArticleQueryLoadTestContract.articleCount {
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
                feedID: feed.id,
                feedTitle: feed.displayTitle,
                feedSiteURL: feed.siteURL,
                feedFolderName: feed.folder?.name,
                externalID: externalID,
                url: "https://example.com/query-load/articles/\(index)",
                title: "Query Load Article \(index)",
                contentHTML: contentHTML,
                searchableText: searchableText,
                publishedAt: baseDate.addingTimeInterval(TimeInterval(index)),
                fetchedAt: baseDate,
                createdAt: baseDate,
                updatedAt: baseDate
            )
            modelContext.insert(article)

            let isRead = index.isMultiple(of: 3)
            let isStarred = index.isMultiple(of: 20)
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
        return ArticleQueryLoadFixture(
            folderName: folderName,
            feedIDs: feeds.map(\.id)
        )
    }
}

@MainActor
final class ArticleQueryLoadProbe {
    private(set) var maximumRequestedOverlayIdentityCount = 0
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
