import Foundation

struct ArticleRetentionCleanupResult: Equatable, Sendable {
    let policy: ArticleRetentionPolicy
    let inspectedArchivedCount: Int
    let deletedCount: Int
    let retainedStarredCount: Int
    let cutoffDate: Date
}

@MainActor
protocol ArticleRetentionCleanupServicing {
    @discardableResult
    func cleanupArchivedArticles(
        policy: ArticleRetentionPolicy,
        now: Date
    ) throws -> ArticleRetentionCleanupResult
}

@MainActor
final class ArticleRetentionCleanupService: ArticleRetentionCleanupServicing {
    private let logger: Logging
    private let articleRepository: any ArticleRepository
    private let articleStateRepository: any ArticleStateRepository

    init(
        logger: Logging,
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository
    ) {
        self.logger = logger
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
    }

    @discardableResult
    func cleanupArchivedArticles(
        policy: ArticleRetentionPolicy,
        now: Date = .now
    ) throws -> ArticleRetentionCleanupResult {
        let archivedArticles = try articleRepository.fetchArchivedArticles()
        let stateByCompositeKey = try articleStateRepository.fetchStateSnapshots(for: archivedArticles)
        let cutoffDate = policy.retentionCutoffDate(now: now)
        var articlesToDelete: [Article] = []
        var retainedStarredCount = 0

        for article in archivedArticles {
            guard let archivedAt = article.archivedAt, archivedAt <= cutoffDate else {
                continue
            }

            let state = stateByCompositeKey[articleCompositeKey(for: article)]
            if state?.isStarred == true {
                retainedStarredCount += 1
                continue
            }

            articlesToDelete.append(article)
        }

        try articleRepository.delete(articlesToDelete, saveAfterOperation: true)

        let result = ArticleRetentionCleanupResult(
            policy: policy,
            inspectedArchivedCount: archivedArticles.count,
            deletedCount: articlesToDelete.count,
            retainedStarredCount: retainedStarredCount,
            cutoffDate: cutoffDate
        )
        logger.info(
            "Article retention cleanup finished policy=\(policy.rawValue) inspected=\(result.inspectedArchivedCount) deleted=\(result.deletedCount) retainedStarred=\(result.retainedStarredCount)"
        )
        return result
    }

    private func articleCompositeKey(for article: Article) -> String {
        "\(article.feedID.uuidString)|\(article.externalID)"
    }
}

private extension ArticleRetentionPolicy {
    func retentionCutoffDate(now: Date) -> Date {
        now.addingTimeInterval(-retentionInterval)
    }

    var retentionInterval: TimeInterval {
        switch self {
        case .currentFeedOnly:
            0
        case .twoDays:
            2 * 24 * 60 * 60
        case .oneWeek:
            7 * 24 * 60 * 60
        case .twoWeeks:
            14 * 24 * 60 * 60
        case .oneMonth:
            30 * 24 * 60 * 60
        }
    }
}
