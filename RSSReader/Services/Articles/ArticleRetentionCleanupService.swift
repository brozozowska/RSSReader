import Foundation

struct ArticleRetentionCleanupResult: Equatable, Sendable {
    let policy: ArticleRetentionPolicy
    let inspectedArchivedCount: Int
    let deletedCount: Int
    let retainedStarredCount: Int
    let cutoffDate: Date
}

struct ArticleArchivePurgeResult: Equatable, Sendable {
    let inspectedArchivedCount: Int
    let deletedCount: Int
    let retainedStarredCount: Int
}

@MainActor
protocol ArticleRetentionCleanupServicing {
    @discardableResult
    func cleanupArchivedArticles(
        policy: ArticleRetentionPolicy,
        now: Date
    ) throws -> ArticleRetentionCleanupResult

    @discardableResult
    func purgeArchivedArticles() throws -> ArticleArchivePurgeResult
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

    @discardableResult
    func purgeArchivedArticles() throws -> ArticleArchivePurgeResult {
        let archivedArticles = try articleRepository.fetchArchivedArticles()
        let stateByCompositeKey = try articleStateRepository.fetchStateSnapshots(for: archivedArticles)
        var articlesToDelete: [Article] = []
        var retainedStarredCount = 0

        for article in archivedArticles {
            let state = stateByCompositeKey[articleCompositeKey(for: article)]
            if state?.isStarred == true {
                retainedStarredCount += 1
                continue
            }

            articlesToDelete.append(article)
        }

        try articleRepository.delete(articlesToDelete, saveAfterOperation: true)

        let result = ArticleArchivePurgeResult(
            inspectedArchivedCount: archivedArticles.count,
            deletedCount: articlesToDelete.count,
            retainedStarredCount: retainedStarredCount
        )
        logger.info(
            "Article archive purge finished inspected=\(result.inspectedArchivedCount) deleted=\(result.deletedCount) retainedStarred=\(result.retainedStarredCount)"
        )
        return result
    }

    private func articleCompositeKey(for article: Article) -> String {
        "\(article.feedID.uuidString)|\(article.externalID)"
    }
}

private extension ArticleRetentionPolicy {
    func retentionCutoffDate(now: Date) -> Date {
        switch ArticleRetentionContract.current.timeRule(for: self) {
        case .whileReturnedByFeed:
            now
        case .sourceAge(let maximumAge):
            now.addingTimeInterval(-maximumAge)
        }
    }
}
