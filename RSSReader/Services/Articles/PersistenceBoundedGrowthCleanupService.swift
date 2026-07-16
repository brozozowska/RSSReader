import Foundation

struct PersistenceBoundedGrowthCleanupResult: Equatable, Sendable {
    let feedFetchLogCutoffDate: Date
    let maximumFeedFetchLogCountPerFeed: Int
    let deletedExpiredFeedFetchLogCount: Int
    let deletedFeedFetchLogCountExceedingCountLimit: Int
    let inspectedArticleStateCount: Int
    let deletedArticleStateCount: Int
    let retainedStarredArticleStateCount: Int

    var deletedFeedFetchLogCount: Int {
        deletedExpiredFeedFetchLogCount + deletedFeedFetchLogCountExceedingCountLimit
    }
}

@MainActor
protocol PersistenceBoundedGrowthCleanupServicing {
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

    init(
        logger: Logging,
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository,
        feedFetchLogRepository: any FeedFetchLogRepository,
        feedFetchLogRetentionContract: FeedFetchLogRetentionContract = .current
    ) {
        self.logger = logger
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
        self.feedFetchLogRepository = feedFetchLogRepository
        self.feedFetchLogRetentionContract = feedFetchLogRetentionContract
    }

    @discardableResult
    func cleanupBoundedGrowth(now: Date = .now) throws -> PersistenceBoundedGrowthCleanupResult {
        let feedFetchLogCutoffDate = feedFetchLogRetentionContract.cutoffDate(now: now)
        let deletedExpiredFeedFetchLogCount = try feedFetchLogRepository.deleteLogs(
            olderThan: feedFetchLogCutoffDate,
            saveAfterOperation: true
        )
        let deletedFeedFetchLogCountExceedingCountLimit = try feedFetchLogRepository
            .deleteLogsExceedingPerFeedCount(
                feedFetchLogRetentionContract.maximumLogCountPerFeed,
                saveAfterOperation: true
            )
        let articleIdentities = try articleRepository.fetchArticleStateIdentities()
        let articleStateCleanupResult = try articleStateRepository.deleteOrphanStates(
            keepingArticleIdentities: articleIdentities,
            saveAfterOperation: true
        )

        let result = PersistenceBoundedGrowthCleanupResult(
            feedFetchLogCutoffDate: feedFetchLogCutoffDate,
            maximumFeedFetchLogCountPerFeed: feedFetchLogRetentionContract.maximumLogCountPerFeed,
            deletedExpiredFeedFetchLogCount: deletedExpiredFeedFetchLogCount,
            deletedFeedFetchLogCountExceedingCountLimit: deletedFeedFetchLogCountExceedingCountLimit,
            inspectedArticleStateCount: articleStateCleanupResult.inspectedCount,
            deletedArticleStateCount: articleStateCleanupResult.deletedCount,
            retainedStarredArticleStateCount: articleStateCleanupResult.retainedStarredCount
        )
        logger.info(
            "Persistence bounded growth cleanup finished deletedFeedFetchLogs=\(result.deletedFeedFetchLogCount) deletedExpiredFeedFetchLogs=\(result.deletedExpiredFeedFetchLogCount) deletedFeedFetchLogsByCount=\(result.deletedFeedFetchLogCountExceedingCountLimit) maximumFeedFetchLogsPerFeed=\(result.maximumFeedFetchLogCountPerFeed) inspectedArticleStates=\(result.inspectedArticleStateCount) deletedArticleStates=\(result.deletedArticleStateCount) retainedStarredArticleStates=\(result.retainedStarredArticleStateCount)"
        )
        return result
    }
}
