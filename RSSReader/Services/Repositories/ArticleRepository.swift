import Foundation
import SwiftData

@MainActor
protocol ArticleRepository {
    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool) throws -> Int
    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> ArticleFeedSnapshotReconciliationResult
    func fetchArticle(id: UUID) throws -> Article?
    func fetchArticles(ids: [UUID]) throws -> [Article]
    func containsArticle(feedID: UUID, externalID: String) throws -> Bool
    func fetchArticles(feedID: UUID) throws -> [Article]
    func fetchArticleQueryRecordScanBatch(
        matching criteria: ArticleQueryCriteria,
        cursor: ArticleQueryCursor?,
        limit: Int
    ) throws -> ArticleQueryRecordScanBatch
    func hasArchivedArticles() throws -> Bool
    func fetchArchivedRetentionBatch(
        feedID: UUID,
        offset: Int,
        limit: Int
    ) throws -> [Article]

    func delete(_ article: Article) throws
    func delete(_ articles: [Article], saveAfterOperation: Bool) throws
}

extension ArticleRepository {
    func refreshFeedProjection(for feed: Feed) throws -> Int {
        try refreshFeedProjection(for: feed, saveAfterOperation: true)
    }

    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        try reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: true
        )
    }

    func delete(_ articles: [Article]) throws {
        try delete(articles, saveAfterOperation: true)
    }
}

// Stable facade and save boundary; both helpers share this ModelContext.
@MainActor
final class SwiftDataArticleRepository: ArticleRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    private let queryExecutor: SwiftDataArticleQueryExecutor
    private let snapshotReconciler: SwiftDataArticleFeedSnapshotReconciler

    init(
        modelContext: ModelContext,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder = { _ in },
        cancellationCheckpoint: @escaping (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void = { _ in
            try Task.checkCancellation()
        },
        reconciliationProgressProbe: ArticleFeedSnapshotReconciliationProgressProbe? = nil,
        queryBatchSize: Int = ArticleStateQueryPolicy.batchSize,
        articleStateQueryBatchProbe: ArticleStateQueryBatchProbe? = nil,
        queryCancellationCheck: @escaping ArticleQueryCancellationCheck = {
            try Task.checkCancellation()
        }
    ) {
        precondition(queryBatchSize > 0)
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
        let queryExecutor = SwiftDataArticleQueryExecutor(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder,
            queryBatchSize: queryBatchSize,
            articleStateQueryBatchProbe: articleStateQueryBatchProbe,
            queryCancellationCheck: queryCancellationCheck
        )
        self.queryExecutor = queryExecutor
        self.snapshotReconciler = SwiftDataArticleFeedSnapshotReconciler(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder,
            queryExecutor: queryExecutor,
            cancellationCheckpoint: cancellationCheckpoint,
            reconciliationProgressProbe: reconciliationProgressProbe
        )
    }

    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool = true) throws -> Int {
        let updatedCount = try snapshotReconciler.stageFeedProjection(for: feed)
        if updatedCount > 0, saveAfterOperation {
            try saveIfNeeded()
        }
        return updatedCount
    }

    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool = true
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        let result = try snapshotReconciler.stageFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt
        )
        if saveAfterOperation {
            try saveIfNeeded()
        }
        return result
    }

    func fetchArticle(id: UUID) throws -> Article? {
        try queryExecutor.fetchArticle(id: id)
    }

    func fetchArticles(ids: [UUID]) throws -> [Article] {
        try queryExecutor.fetchArticles(ids: ids)
    }

    func containsArticle(feedID: UUID, externalID: String) throws -> Bool {
        try queryExecutor.containsArticle(feedID: feedID, externalID: externalID)
    }

    func fetchArticles(feedID: UUID) throws -> [Article] {
        try queryExecutor.fetchArticles(feedID: feedID)
    }

    func fetchArticleQueryRecordScanBatch(
        matching criteria: ArticleQueryCriteria,
        cursor: ArticleQueryCursor?,
        limit: Int
    ) throws -> ArticleQueryRecordScanBatch {
        try queryExecutor.fetchArticleQueryRecordScanBatch(
            matching: criteria,
            cursor: cursor,
            limit: limit
        )
    }

    func hasArchivedArticles() throws -> Bool {
        try queryExecutor.hasArchivedArticles()
    }

    func fetchArchivedRetentionBatch(
        feedID: UUID,
        offset: Int,
        limit: Int
    ) throws -> [Article] {
        try queryExecutor.fetchArchivedRetentionBatch(feedID: feedID, offset: offset, limit: limit)
    }

    func delete(_ article: Article) throws {
        modelContext.delete(article)
        try saveIfNeeded()
    }

    func delete(_ articles: [Article], saveAfterOperation: Bool = true) throws {
        guard articles.isEmpty == false else { return }

        for article in articles {
            modelContext.delete(article)
        }

        if saveAfterOperation {
            try saveIfNeeded()
        }
    }
}
