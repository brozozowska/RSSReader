import Foundation

struct FeedFetchLogCleanupResult: Equatable, Sendable {
    let cutoffDate: Date
    let maximumCountPerFeed: Int
    let deletedExpiredCount: Int
    let deletedExceedingCountLimit: Int
    let processedBatchCount: Int
    let maximumMaterializedBatchCount: Int

    var deletedCount: Int {
        deletedExpiredCount + deletedExceedingCountLimit
    }
}

struct PersistenceBoundedGrowthCleanupResult: Equatable, Sendable {
    let feedFetchLogCutoffDate: Date
    let maximumFeedFetchLogCountPerFeed: Int
    let deletedExpiredFeedFetchLogCount: Int
    let deletedFeedFetchLogCountExceedingCountLimit: Int
    let feedFetchLogProcessedBatchCount: Int
    let maximumMaterializedFeedFetchLogBatchCount: Int
    let inspectedArticleStateCount: Int
    let deletedArticleStateCount: Int
    let retainedStarredArticleStateCount: Int
    let articleStateProcessedBatchCount: Int
    let maximumMaterializedArticleStateBatchCount: Int

    var deletedFeedFetchLogCount: Int {
        deletedExpiredFeedFetchLogCount + deletedFeedFetchLogCountExceedingCountLimit
    }
}

@MainActor
protocol PersistenceBoundedGrowthCleanupServicing {
    @discardableResult
    func cleanupFeedFetchLogs(now: Date) throws -> FeedFetchLogCleanupResult

    @discardableResult
    func cleanupBoundedGrowth(now: Date) throws -> PersistenceBoundedGrowthCleanupResult
}

@MainActor
final class PersistenceBoundedGrowthCleanupService: PersistenceBoundedGrowthCleanupServicing {
    private let logger: Logging
    private let articleRepository: any ArticleRepository
    private let articleStateRepository: any ArticleStateRepository
    private let feedFetchLogRepository: any FeedFetchLogRepository
    private let feedFetchLogRetentionContract: FeedFetchLogRetentionContract
    private let batchSize: Int

    init(
        logger: Logging,
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository,
        feedFetchLogRepository: any FeedFetchLogRepository,
        feedFetchLogRetentionContract: FeedFetchLogRetentionContract = .current,
        batchSize: Int = 256
    ) {
        precondition(batchSize > 0)
        self.logger = logger
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
        self.feedFetchLogRepository = feedFetchLogRepository
        self.feedFetchLogRetentionContract = feedFetchLogRetentionContract
        self.batchSize = batchSize
    }

    @discardableResult
    func cleanupFeedFetchLogs(now: Date = .now) throws -> FeedFetchLogCleanupResult {
        let result = try performFeedFetchLogCleanup(now: now)
        logger.info(
            "Feed fetch log cleanup finished deleted=\(result.deletedCount) deletedExpired=\(result.deletedExpiredCount) deletedByCount=\(result.deletedExceedingCountLimit) maximumPerFeed=\(result.maximumCountPerFeed) batches=\(result.processedBatchCount) maximumMaterializedBatch=\(result.maximumMaterializedBatchCount)"
        )
        return result
    }

    @discardableResult
    func cleanupBoundedGrowth(now: Date = .now) throws -> PersistenceBoundedGrowthCleanupResult {
        let feedFetchLogResult = try performFeedFetchLogCleanup(now: now)
        let articleStateCleanupResult = try cleanupGlobalOrphanArticleStates()

        let result = PersistenceBoundedGrowthCleanupResult(
            feedFetchLogCutoffDate: feedFetchLogResult.cutoffDate,
            maximumFeedFetchLogCountPerFeed: feedFetchLogResult.maximumCountPerFeed,
            deletedExpiredFeedFetchLogCount: feedFetchLogResult.deletedExpiredCount,
            deletedFeedFetchLogCountExceedingCountLimit: feedFetchLogResult.deletedExceedingCountLimit,
            feedFetchLogProcessedBatchCount: feedFetchLogResult.processedBatchCount,
            maximumMaterializedFeedFetchLogBatchCount: feedFetchLogResult.maximumMaterializedBatchCount,
            inspectedArticleStateCount: articleStateCleanupResult.inspectedCount,
            deletedArticleStateCount: articleStateCleanupResult.deletedCount,
            retainedStarredArticleStateCount: articleStateCleanupResult.retainedStarredCount,
            articleStateProcessedBatchCount: articleStateCleanupResult.processedBatchCount,
            maximumMaterializedArticleStateBatchCount: articleStateCleanupResult.maximumMaterializedBatchCount
        )
        logger.info(
            "Persistence bounded growth cleanup finished deletedFeedFetchLogs=\(result.deletedFeedFetchLogCount) deletedExpiredFeedFetchLogs=\(result.deletedExpiredFeedFetchLogCount) deletedFeedFetchLogsByCount=\(result.deletedFeedFetchLogCountExceedingCountLimit) maximumFeedFetchLogsPerFeed=\(result.maximumFeedFetchLogCountPerFeed) feedFetchLogBatches=\(result.feedFetchLogProcessedBatchCount) maximumMaterializedFeedFetchLogBatch=\(result.maximumMaterializedFeedFetchLogBatchCount) inspectedArticleStates=\(result.inspectedArticleStateCount) deletedArticleStates=\(result.deletedArticleStateCount) retainedStarredArticleStates=\(result.retainedStarredArticleStateCount) articleStateBatches=\(result.articleStateProcessedBatchCount) maximumMaterializedArticleStateBatch=\(result.maximumMaterializedArticleStateBatchCount)"
        )
        return result
    }

    private func performFeedFetchLogCleanup(now: Date) throws -> FeedFetchLogCleanupResult {
        let cutoffDate = feedFetchLogRetentionContract.cutoffDate(now: now)
        let expiredResult = try feedFetchLogRepository.deleteLogs(
            olderThan: cutoffDate,
            batchSize: batchSize
        )
        let countResult = try feedFetchLogRepository.deleteLogsExceedingPerFeedCount(
            feedFetchLogRetentionContract.maximumLogCountPerFeed,
            batchSize: batchSize
        )

        return FeedFetchLogCleanupResult(
            cutoffDate: cutoffDate,
            maximumCountPerFeed: feedFetchLogRetentionContract.maximumLogCountPerFeed,
            deletedExpiredCount: expiredResult.deletedCount,
            deletedExceedingCountLimit: countResult.deletedCount,
            processedBatchCount: expiredResult.processedBatchCount + countResult.processedBatchCount,
            maximumMaterializedBatchCount: max(
                expiredResult.maximumMaterializedBatchCount,
                countResult.maximumMaterializedBatchCount
            )
        )
    }

    private func cleanupGlobalOrphanArticleStates() throws -> ArticleStateOrphanCleanupResult {
        var offset = 0
        var inspectedCount = 0
        var deletedCount = 0
        var retainedStarredCount = 0
        var processedBatchCount = 0
        var maximumMaterializedBatchCount = 0

        while true {
            let states = try articleStateRepository.fetchGlobalOrphanSweepBatch(
                offset: offset,
                limit: batchSize
            )
            guard states.isEmpty == false else { break }

            processedBatchCount += 1
            maximumMaterializedBatchCount = max(maximumMaterializedBatchCount, states.count)
            var retainedCount = 0
            var statesToDelete: [ArticleState] = []
            statesToDelete.reserveCapacity(states.count)

            for state in states {
                inspectedCount += 1
                let isLinked = try articleRepository.containsArticle(
                    feedID: state.feedID,
                    externalID: state.articleExternalID
                )
                if isLinked {
                    retainedCount += 1
                    continue
                }
                if state.isStarred {
                    retainedCount += 1
                    retainedStarredCount += 1
                    continue
                }
                statesToDelete.append(state)
            }

            try articleStateRepository.delete(statesToDelete, saveAfterOperation: true)
            deletedCount += statesToDelete.count
            offset += retainedCount
        }

        return ArticleStateOrphanCleanupResult(
            inspectedCount: inspectedCount,
            deletedCount: deletedCount,
            retainedStarredCount: retainedStarredCount,
            processedBatchCount: processedBatchCount,
            maximumMaterializedBatchCount: maximumMaterializedBatchCount
        )
    }
}
