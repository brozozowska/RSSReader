import Foundation

struct ArticleRetentionCleanupResult: Equatable, Sendable {
    let policy: ArticleRetentionPolicy
    let inspectedArticleCount: Int
    let deletedCount: Int
    let deletedByTimeOrMembershipCount: Int
    let deletedByCountLimitCount: Int
    let retainedStarredCount: Int
    let deletedOrphanArticleStateCount: Int
    let sourceAgeCutoffDate: Date?
}

struct ArticleArchivePurgeResult: Equatable, Sendable {
    let inspectedArchivedCount: Int
    let deletedCount: Int
    let retainedStarredCount: Int
    let deletedOrphanArticleStateCount: Int
}

@MainActor
protocol ArticleRetentionCleanupServicing {
    @discardableResult
    func cleanupArticles(
        policy: ArticleRetentionPolicy,
        now: Date
    ) throws -> ArticleRetentionCleanupResult

    @discardableResult
    func purgeArchivedArticles() throws -> ArticleArchivePurgeResult
}

@MainActor
final class ArticleRetentionCleanupService: ArticleRetentionCleanupServicing {
    private struct RankedArticle {
        let id: UUID
        let externalID: String
        let orderingDate: Date
        let createdAt: Date
    }

    private struct CountSelection {
        let retainedArticleIDs: Set<UUID>
        let retainedArticleExternalIDs: Set<String>
        let inspectedCount: Int
        let unstarredCount: Int
        let starredCount: Int
    }

    private let logger: Logging
    private let feedRepository: any FeedRepository
    private let articleRepository: any ArticleRepository
    private let articleStateRepository: any ArticleStateRepository
    private let contract: ArticleRetentionContract
    private let batchSize: Int

    init(
        logger: Logging,
        feedRepository: any FeedRepository,
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository,
        contract: ArticleRetentionContract = .current,
        batchSize: Int = 256
    ) {
        precondition(batchSize > 0)
        self.logger = logger
        self.feedRepository = feedRepository
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
        self.contract = contract
        self.batchSize = batchSize
    }

    @discardableResult
    func cleanupArticles(
        policy: ArticleRetentionPolicy,
        now: Date = .now
    ) throws -> ArticleRetentionCleanupResult {
        let feeds = try feedRepository.fetchAllFeeds()
        let sourceAgeCutoffDate = contract.sourceAgeCutoffDate(for: policy, now: now)
        var inspectedArticleCount = 0
        var deletedByTimeOrMembershipCount = 0
        var deletedByCountLimitCount = 0
        var retainedStarredCount = 0
        var deletedOrphanArticleStateCount = 0

        for feed in feeds {
            let starredExternalIDs = try articleStateRepository.fetchStarredArticleExternalIDs(feedID: feed.id)
            deletedByTimeOrMembershipCount += try deleteTimeOrMembershipExpiredArticles(
                feedID: feed.id,
                policy: policy,
                sourceAgeCutoffDate: sourceAgeCutoffDate,
                starredExternalIDs: starredExternalIDs
            )

            let countSelection = try selectArticlesWithinCountBudget(
                feedID: feed.id,
                starredExternalIDs: starredExternalIDs
            )
            inspectedArticleCount += countSelection.inspectedCount
            retainedStarredCount += countSelection.starredCount

            if countSelection.unstarredCount > contract.maximumUnstarredArticleCountPerFeed {
                deletedByCountLimitCount += try deleteArticlesOutsideCountBudget(
                    feedID: feed.id,
                    retainedArticleIDs: countSelection.retainedArticleIDs,
                    starredExternalIDs: starredExternalIDs
                )
            }

            let orphanCleanupResult = try articleStateRepository.deleteOrphanStates(
                feedID: feed.id,
                keepingArticleExternalIDs: countSelection.retainedArticleExternalIDs,
                batchSize: batchSize
            )
            deletedOrphanArticleStateCount += orphanCleanupResult.deletedCount
        }

        inspectedArticleCount += deletedByTimeOrMembershipCount
        let deletedCount = deletedByTimeOrMembershipCount + deletedByCountLimitCount
        let result = ArticleRetentionCleanupResult(
            policy: policy,
            inspectedArticleCount: inspectedArticleCount,
            deletedCount: deletedCount,
            deletedByTimeOrMembershipCount: deletedByTimeOrMembershipCount,
            deletedByCountLimitCount: deletedByCountLimitCount,
            retainedStarredCount: retainedStarredCount,
            deletedOrphanArticleStateCount: deletedOrphanArticleStateCount,
            sourceAgeCutoffDate: sourceAgeCutoffDate
        )
        logger.info(
            "Article retention cleanup finished policy=\(policy.rawValue) inspected=\(result.inspectedArticleCount) deleted=\(result.deletedCount) deletedByTimeOrMembership=\(result.deletedByTimeOrMembershipCount) deletedByCount=\(result.deletedByCountLimitCount) retainedStarred=\(result.retainedStarredCount) deletedOrphanStates=\(result.deletedOrphanArticleStateCount)"
        )
        return result
    }

    @discardableResult
    func purgeArchivedArticles() throws -> ArticleArchivePurgeResult {
        let feeds = try feedRepository.fetchAllFeeds()
        var inspectedArchivedCount = 0
        var deletedCount = 0
        var retainedStarredCount = 0
        var deletedOrphanArticleStateCount = 0

        for feed in feeds {
            let starredExternalIDs = try articleStateRepository.fetchStarredArticleExternalIDs(feedID: feed.id)
            var offset = 0

            while true {
                let batch = try articleRepository.fetchRetentionBatch(
                    feedID: feed.id,
                    scope: .archived,
                    offset: offset,
                    limit: batchSize
                )
                guard batch.isEmpty == false else { break }

                let articlesToDelete = batch.filter { article in
                    starredExternalIDs.contains(article.externalID) == false
                }
                inspectedArchivedCount += batch.count
                retainedStarredCount += batch.count - articlesToDelete.count
                try articleRepository.delete(articlesToDelete, saveAfterOperation: true)
                deletedCount += articlesToDelete.count
                offset += batch.count - articlesToDelete.count
            }

            let remainingExternalIDs = try fetchMaterializedExternalIDs(feedID: feed.id)
            let orphanCleanupResult = try articleStateRepository.deleteOrphanStates(
                feedID: feed.id,
                keepingArticleExternalIDs: remainingExternalIDs,
                batchSize: batchSize
            )
            deletedOrphanArticleStateCount += orphanCleanupResult.deletedCount
        }

        let result = ArticleArchivePurgeResult(
            inspectedArchivedCount: inspectedArchivedCount,
            deletedCount: deletedCount,
            retainedStarredCount: retainedStarredCount,
            deletedOrphanArticleStateCount: deletedOrphanArticleStateCount
        )
        logger.info(
            "Article archive purge finished inspected=\(result.inspectedArchivedCount) deleted=\(result.deletedCount) retainedStarred=\(result.retainedStarredCount) deletedOrphanStates=\(result.deletedOrphanArticleStateCount)"
        )
        return result
    }

    private func deleteTimeOrMembershipExpiredArticles(
        feedID: UUID,
        policy: ArticleRetentionPolicy,
        sourceAgeCutoffDate: Date?,
        starredExternalIDs: Set<String>
    ) throws -> Int {
        let scope: ArticleRetentionBatchScope = switch contract.timeRule(for: policy) {
        case .whileReturnedByFeed:
            .archived
        case .sourceAge:
            .all
        }
        var offset = 0
        var deletedCount = 0

        while true {
            let batch = try articleRepository.fetchRetentionBatch(
                feedID: feedID,
                scope: scope,
                offset: offset,
                limit: batchSize
            )
            guard batch.isEmpty == false else { break }

            let articlesToDelete = batch.filter { article in
                guard starredExternalIDs.contains(article.externalID) == false else {
                    return false
                }

                switch contract.timeRule(for: policy) {
                case .whileReturnedByFeed:
                    return article.archivedAt != nil
                case .sourceAge:
                    guard let sourceAgeCutoffDate,
                          let referenceDate = contract.sourceAgeReferenceDate(
                            publishedAt: article.publishedAt,
                            updatedAtSource: article.updatedAtSource,
                            firstMaterializedAt: article.createdAt
                          ) else {
                        return false
                    }
                    return referenceDate <= sourceAgeCutoffDate
                }
            }

            try articleRepository.delete(articlesToDelete, saveAfterOperation: true)
            deletedCount += articlesToDelete.count
            offset += batch.count - articlesToDelete.count
        }

        return deletedCount
    }

    private func selectArticlesWithinCountBudget(
        feedID: UUID,
        starredExternalIDs: Set<String>
    ) throws -> CountSelection {
        var offset = 0
        var inspectedCount = 0
        var unstarredCount = 0
        var starredCount = 0
        var retainedArticles: [RankedArticle] = []
        var materializedStarredExternalIDs: Set<String> = []

        while true {
            let batch = try articleRepository.fetchRetentionBatch(
                feedID: feedID,
                scope: .all,
                offset: offset,
                limit: batchSize
            )
            guard batch.isEmpty == false else { break }

            inspectedCount += batch.count
            offset += batch.count
            var rankedBatch: [RankedArticle] = []
            rankedBatch.reserveCapacity(batch.count)

            for article in batch {
                if starredExternalIDs.contains(article.externalID) {
                    starredCount += 1
                    materializedStarredExternalIDs.insert(article.externalID)
                    continue
                }

                unstarredCount += 1
                rankedBatch.append(
                    RankedArticle(
                        id: article.id,
                        externalID: article.externalID,
                        orderingDate: contract.countOrderingDate(
                            publishedAt: article.publishedAt,
                            updatedAtSource: article.updatedAtSource,
                            firstMaterializedAt: article.createdAt
                        ),
                        createdAt: article.createdAt
                    )
                )
            }

            retainedArticles.append(contentsOf: rankedBatch)
            retainedArticles.sort(by: ranksBefore)
            if retainedArticles.count > contract.maximumUnstarredArticleCountPerFeed {
                retainedArticles.removeLast(
                    retainedArticles.count - contract.maximumUnstarredArticleCountPerFeed
                )
            }
        }

        return CountSelection(
            retainedArticleIDs: Set(retainedArticles.map(\.id)),
            retainedArticleExternalIDs: Set(retainedArticles.map(\.externalID))
                .union(materializedStarredExternalIDs),
            inspectedCount: inspectedCount,
            unstarredCount: unstarredCount,
            starredCount: starredCount
        )
    }

    private func deleteArticlesOutsideCountBudget(
        feedID: UUID,
        retainedArticleIDs: Set<UUID>,
        starredExternalIDs: Set<String>
    ) throws -> Int {
        var offset = 0
        var deletedCount = 0

        while true {
            let batch = try articleRepository.fetchRetentionBatch(
                feedID: feedID,
                scope: .all,
                offset: offset,
                limit: batchSize
            )
            guard batch.isEmpty == false else { break }

            let articlesToDelete = batch.filter { article in
                starredExternalIDs.contains(article.externalID) == false
                    && retainedArticleIDs.contains(article.id) == false
            }
            try articleRepository.delete(articlesToDelete, saveAfterOperation: true)
            deletedCount += articlesToDelete.count
            offset += batch.count - articlesToDelete.count
        }

        return deletedCount
    }

    private func fetchMaterializedExternalIDs(feedID: UUID) throws -> Set<String> {
        var offset = 0
        var externalIDs: Set<String> = []

        while true {
            let batch = try articleRepository.fetchRetentionBatch(
                feedID: feedID,
                scope: .all,
                offset: offset,
                limit: batchSize
            )
            guard batch.isEmpty == false else { break }
            externalIDs.formUnion(batch.map(\.externalID))
            offset += batch.count
        }

        return externalIDs
    }

    private func ranksBefore(_ lhs: RankedArticle, _ rhs: RankedArticle) -> Bool {
        if lhs.orderingDate != rhs.orderingDate {
            return lhs.orderingDate > rhs.orderingDate
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        if lhs.externalID != rhs.externalID {
            return lhs.externalID > rhs.externalID
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
