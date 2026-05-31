import Foundation

struct PersistenceBoundedGrowthCleanupResult: Equatable, Sendable {
    let feedFetchLogCutoffDate: Date
    let deletedFeedFetchLogCount: Int
    let inspectedArticleStateCount: Int
    let deletedArticleStateCount: Int
    let retainedStarredArticleStateCount: Int
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
    private let feedFetchLogRetentionInterval: TimeInterval

    init(
        logger: Logging,
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository,
        feedFetchLogRepository: any FeedFetchLogRepository,
        feedFetchLogRetentionInterval: TimeInterval = 604_800
    ) {
        self.logger = logger
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
        self.feedFetchLogRepository = feedFetchLogRepository
        self.feedFetchLogRetentionInterval = feedFetchLogRetentionInterval
    }

    @discardableResult
    func cleanupBoundedGrowth(now: Date = .now) throws -> PersistenceBoundedGrowthCleanupResult {
        let feedFetchLogCutoffDate = now.addingTimeInterval(-feedFetchLogRetentionInterval)
        let deletedFeedFetchLogCount = try feedFetchLogRepository.deleteLogs(
            olderThan: feedFetchLogCutoffDate,
            saveAfterOperation: true
        )
        let articleIdentities = try articleRepository.fetchArticleStateIdentities()
        let articleStateCleanupResult = try articleStateRepository.deleteOrphanStates(
            keepingArticleIdentities: articleIdentities,
            saveAfterOperation: true
        )

        let result = PersistenceBoundedGrowthCleanupResult(
            feedFetchLogCutoffDate: feedFetchLogCutoffDate,
            deletedFeedFetchLogCount: deletedFeedFetchLogCount,
            inspectedArticleStateCount: articleStateCleanupResult.inspectedCount,
            deletedArticleStateCount: articleStateCleanupResult.deletedCount,
            retainedStarredArticleStateCount: articleStateCleanupResult.retainedStarredCount
        )
        logger.info(
            "Persistence bounded growth cleanup finished deletedFeedFetchLogs=\(result.deletedFeedFetchLogCount) inspectedArticleStates=\(result.inspectedArticleStateCount) deletedArticleStates=\(result.deletedArticleStateCount) retainedStarredArticleStates=\(result.retainedStarredArticleStateCount)"
        )
        return result
    }
}
