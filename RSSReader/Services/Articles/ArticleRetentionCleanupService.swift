import Foundation

enum ArticleRetentionCleanupScope: Equatable, Sendable {
    case allFeeds
    case feedIDs([UUID])
}

struct ArticleRetentionCleanupDiagnostics: Equatable, Sendable {
    let processedFeedCount: Int
    let processedFeedBatchCount: Int
    let processedArticleBatchCount: Int
    let processedArticleStateBatchCount: Int
    let maximumMaterializedFeedBatchCount: Int
    let maximumMaterializedArticleBatchCount: Int
    let maximumMaterializedArticleStateBatchCount: Int
}

struct ArticleRetentionCleanupResult: Equatable, Sendable {
    let policy: ArticleRetentionPolicy
    let inspectedArticleCount: Int
    let deletedCount: Int
    let deletedByTimeOrMembershipCount: Int
    let deletedByCountLimitCount: Int
    let retainedStarredCount: Int
    let deletedOrphanArticleStateCount: Int
    let archiveCutoffDate: Date?
    let diagnostics: ArticleRetentionCleanupDiagnostics
}

struct ArticleArchivePurgeResult: Equatable, Sendable {
    let inspectedArchivedCount: Int
    let deletedCount: Int
    let retainedStarredCount: Int
    let deletedOrphanArticleStateCount: Int
    let diagnostics: ArticleRetentionCleanupDiagnostics
}

@MainActor
protocol ArticleRetentionCleanupServicing {
    @discardableResult
    func cleanupArticles(
        policy: ArticleRetentionPolicy,
        scope: ArticleRetentionCleanupScope,
        now: Date
    ) throws -> ArticleRetentionCleanupResult

    @discardableResult
    func purgeArchivedArticles() throws -> ArticleArchivePurgeResult
}

extension ArticleRetentionCleanupServicing {
    @discardableResult
    func cleanupArticles(
        policy: ArticleRetentionPolicy,
        now: Date
    ) throws -> ArticleRetentionCleanupResult {
        try cleanupArticles(policy: policy, scope: .allFeeds, now: now)
    }
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
        let inspectedCount: Int
        let unstarredCount: Int
        let starredCount: Int
    }

    private struct MutableDiagnostics {
        var processedFeedCount = 0
        var processedFeedBatchCount = 0
        var processedArticleBatchCount = 0
        var processedArticleStateBatchCount = 0
        var maximumMaterializedFeedBatchCount = 0
        var maximumMaterializedArticleBatchCount = 0
        var maximumMaterializedArticleStateBatchCount = 0

        mutating func observeFeedBatch(count: Int) {
            guard count > 0 else { return }
            processedFeedCount += count
            processedFeedBatchCount += 1
            maximumMaterializedFeedBatchCount = max(maximumMaterializedFeedBatchCount, count)
        }

        mutating func observeArticleBatch(count: Int) {
            guard count > 0 else { return }
            processedArticleBatchCount += 1
            maximumMaterializedArticleBatchCount = max(maximumMaterializedArticleBatchCount, count)
        }

        mutating func observeArticleStateBatch(count: Int) {
            guard count > 0 else { return }
            processedArticleStateBatchCount += 1
            maximumMaterializedArticleStateBatchCount = max(
                maximumMaterializedArticleStateBatchCount,
                count
            )
        }

        mutating func observeArticleStateBatches(
            processedCount: Int,
            maximumMaterializedCount: Int
        ) {
            processedArticleStateBatchCount += processedCount
            maximumMaterializedArticleStateBatchCount = max(
                maximumMaterializedArticleStateBatchCount,
                maximumMaterializedCount
            )
        }

        var snapshot: ArticleRetentionCleanupDiagnostics {
            ArticleRetentionCleanupDiagnostics(
                processedFeedCount: processedFeedCount,
                processedFeedBatchCount: processedFeedBatchCount,
                processedArticleBatchCount: processedArticleBatchCount,
                processedArticleStateBatchCount: processedArticleStateBatchCount,
                maximumMaterializedFeedBatchCount: maximumMaterializedFeedBatchCount,
                maximumMaterializedArticleBatchCount: maximumMaterializedArticleBatchCount,
                maximumMaterializedArticleStateBatchCount: maximumMaterializedArticleStateBatchCount
            )
        }
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
        scope: ArticleRetentionCleanupScope,
        now: Date = .now
    ) throws -> ArticleRetentionCleanupResult {
        let archiveCutoffDate = contract.archiveCutoffDate(for: policy, now: now)
        var inspectedArticleCount = 0
        var deletedByTimeOrMembershipCount = 0
        var deletedByCountLimitCount = 0
        var retainedStarredCount = 0
        var deletedOrphanArticleStateCount = 0
        var diagnostics = MutableDiagnostics()

        try forEachFeedID(in: scope, diagnostics: &diagnostics) { feedID, diagnostics in
            deletedByTimeOrMembershipCount += try deleteTimeOrMembershipExpiredArticles(
                feedID: feedID,
                policy: policy,
                archiveCutoffDate: archiveCutoffDate,
                diagnostics: &diagnostics
            )

            let countSelection = try selectArticlesWithinCountBudget(
                feedID: feedID,
                diagnostics: &diagnostics
            )
            inspectedArticleCount += countSelection.inspectedCount
            retainedStarredCount += countSelection.starredCount

            if countSelection.unstarredCount > contract.maximumArchivedUnstarredArticleCountPerFeed {
                deletedByCountLimitCount += try deleteArticlesOutsideCountBudget(
                    feedID: feedID,
                    retainedArticleIDs: countSelection.retainedArticleIDs,
                    diagnostics: &diagnostics
                )
            }

            let orphanCleanupResult = try deleteOrphanStates(
                feedID: feedID,
                diagnostics: &diagnostics
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
            archiveCutoffDate: archiveCutoffDate,
            diagnostics: diagnostics.snapshot
        )
        logger.info(
            "Article retention cleanup finished policy=\(policy.rawValue) scope=\(scope.logDescription) inspected=\(result.inspectedArticleCount) deleted=\(result.deletedCount) deletedByTimeOrMembership=\(result.deletedByTimeOrMembershipCount) deletedByCount=\(result.deletedByCountLimitCount) retainedStarred=\(result.retainedStarredCount) deletedOrphanStates=\(result.deletedOrphanArticleStateCount) feeds=\(result.diagnostics.processedFeedCount) feedBatches=\(result.diagnostics.processedFeedBatchCount) articleBatches=\(result.diagnostics.processedArticleBatchCount) articleStateBatches=\(result.diagnostics.processedArticleStateBatchCount) maximumMaterializedFeedBatch=\(result.diagnostics.maximumMaterializedFeedBatchCount) maximumMaterializedArticleBatch=\(result.diagnostics.maximumMaterializedArticleBatchCount) maximumMaterializedArticleStateBatch=\(result.diagnostics.maximumMaterializedArticleStateBatchCount)"
        )
        return result
    }

    @discardableResult
    func purgeArchivedArticles() throws -> ArticleArchivePurgeResult {
        var inspectedArchivedCount = 0
        var deletedCount = 0
        var retainedStarredCount = 0
        var deletedOrphanArticleStateCount = 0
        var diagnostics = MutableDiagnostics()

        try forEachFeedID(in: .allFeeds, diagnostics: &diagnostics) { feedID, diagnostics in
            var offset = 0

            while true {
                let batch = try articleRepository.fetchArchivedRetentionBatch(
                    feedID: feedID,
                    offset: offset,
                    limit: batchSize
                )
                guard batch.isEmpty == false else { break }
                diagnostics.observeArticleBatch(count: batch.count)
                let starredExternalIDs = try fetchStarredExternalIDs(
                    feedID: feedID,
                    articles: batch,
                    diagnostics: &diagnostics
                )
                let articlesToDelete = batch.filter { article in
                    starredExternalIDs.contains(article.externalID) == false
                }
                inspectedArchivedCount += batch.count
                retainedStarredCount += batch.count - articlesToDelete.count
                try articleRepository.delete(articlesToDelete, saveAfterOperation: true)
                deletedCount += articlesToDelete.count
                offset += batch.count - articlesToDelete.count
            }

            let orphanCleanupResult = try deleteOrphanStates(
                feedID: feedID,
                diagnostics: &diagnostics
            )
            deletedOrphanArticleStateCount += orphanCleanupResult.deletedCount
        }

        let result = ArticleArchivePurgeResult(
            inspectedArchivedCount: inspectedArchivedCount,
            deletedCount: deletedCount,
            retainedStarredCount: retainedStarredCount,
            deletedOrphanArticleStateCount: deletedOrphanArticleStateCount,
            diagnostics: diagnostics.snapshot
        )
        logger.info(
            "Article archive purge finished inspected=\(result.inspectedArchivedCount) deleted=\(result.deletedCount) retainedStarred=\(result.retainedStarredCount) deletedOrphanStates=\(result.deletedOrphanArticleStateCount) feeds=\(result.diagnostics.processedFeedCount) feedBatches=\(result.diagnostics.processedFeedBatchCount) articleBatches=\(result.diagnostics.processedArticleBatchCount) articleStateBatches=\(result.diagnostics.processedArticleStateBatchCount) maximumMaterializedFeedBatch=\(result.diagnostics.maximumMaterializedFeedBatchCount) maximumMaterializedArticleBatch=\(result.diagnostics.maximumMaterializedArticleBatchCount) maximumMaterializedArticleStateBatch=\(result.diagnostics.maximumMaterializedArticleStateBatchCount)"
        )
        return result
    }

    private func forEachFeedID(
        in scope: ArticleRetentionCleanupScope,
        diagnostics: inout MutableDiagnostics,
        operation: (UUID, inout MutableDiagnostics) throws -> Void
    ) throws {
        switch scope {
        case .allFeeds:
            var offset = 0
            while true {
                let feedIDs = try feedRepository.fetchRetentionFeedIDBatch(
                    offset: offset,
                    limit: batchSize
                )
                guard feedIDs.isEmpty == false else { break }
                diagnostics.observeFeedBatch(count: feedIDs.count)
                for feedID in feedIDs {
                    try operation(feedID, &diagnostics)
                }
                offset += feedIDs.count
            }
        case .feedIDs(let feedIDs):
            var offset = 0
            while offset < feedIDs.count {
                let upperBound = min(offset + batchSize, feedIDs.count)
                let batch = Array(feedIDs[offset..<upperBound])
                diagnostics.observeFeedBatch(count: batch.count)
                for feedID in batch {
                    try operation(feedID, &diagnostics)
                }
                offset = upperBound
            }
        }
    }

    private func deleteTimeOrMembershipExpiredArticles(
        feedID: UUID,
        policy: ArticleRetentionPolicy,
        archiveCutoffDate: Date?,
        diagnostics: inout MutableDiagnostics
    ) throws -> Int {
        var offset = 0
        var deletedCount = 0

        while true {
            let batch = try articleRepository.fetchArchivedRetentionBatch(
                feedID: feedID,
                offset: offset,
                limit: batchSize
            )
            guard batch.isEmpty == false else { break }
            diagnostics.observeArticleBatch(count: batch.count)
            let starredExternalIDs = try fetchStarredExternalIDs(
                feedID: feedID,
                articles: batch,
                diagnostics: &diagnostics
            )

            let articlesToDelete = batch.filter { article in
                guard let archivedAt = article.archivedAt,
                      starredExternalIDs.contains(article.externalID) == false else {
                    return false
                }

                switch contract.timeRule(for: policy) {
                case .removeOnFeedAbsence:
                    return true
                case .archivedAge:
                    guard let archiveCutoffDate else {
                        return false
                    }
                    return archivedAt <= archiveCutoffDate
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
        diagnostics: inout MutableDiagnostics
    ) throws -> CountSelection {
        var offset = 0
        var inspectedCount = 0
        var unstarredCount = 0
        var starredCount = 0
        var retainedArticles: [RankedArticle] = []

        while true {
            let batch = try articleRepository.fetchArchivedRetentionBatch(
                feedID: feedID,
                offset: offset,
                limit: batchSize
            )
            guard batch.isEmpty == false else { break }
            diagnostics.observeArticleBatch(count: batch.count)
            let starredExternalIDs = try fetchStarredExternalIDs(
                feedID: feedID,
                articles: batch,
                diagnostics: &diagnostics
            )

            inspectedCount += batch.count
            offset += batch.count
            var rankedBatch: [RankedArticle] = []
            rankedBatch.reserveCapacity(batch.count)

            for article in batch {
                guard let archivedAt = article.archivedAt else {
                    continue
                }
                if starredExternalIDs.contains(article.externalID) {
                    starredCount += 1
                    continue
                }

                unstarredCount += 1
                rankedBatch.append(
                    RankedArticle(
                        id: article.id,
                        externalID: article.externalID,
                        orderingDate: archivedAt,
                        createdAt: article.createdAt
                    )
                )
            }

            retainedArticles.append(contentsOf: rankedBatch)
            retainedArticles.sort(by: ranksBefore)
            if retainedArticles.count > contract.maximumArchivedUnstarredArticleCountPerFeed {
                retainedArticles.removeLast(
                    retainedArticles.count - contract.maximumArchivedUnstarredArticleCountPerFeed
                )
            }
        }

        return CountSelection(
            retainedArticleIDs: Set(retainedArticles.map(\.id)),
            inspectedCount: inspectedCount,
            unstarredCount: unstarredCount,
            starredCount: starredCount
        )
    }

    private func deleteArticlesOutsideCountBudget(
        feedID: UUID,
        retainedArticleIDs: Set<UUID>,
        diagnostics: inout MutableDiagnostics
    ) throws -> Int {
        var offset = 0
        var deletedCount = 0

        while true {
            let batch = try articleRepository.fetchArchivedRetentionBatch(
                feedID: feedID,
                offset: offset,
                limit: batchSize
            )
            guard batch.isEmpty == false else { break }
            diagnostics.observeArticleBatch(count: batch.count)
            let starredExternalIDs = try fetchStarredExternalIDs(
                feedID: feedID,
                articles: batch,
                diagnostics: &diagnostics
            )

            let articlesToDelete = batch.filter { article in
                article.archivedAt != nil
                    && starredExternalIDs.contains(article.externalID) == false
                    && retainedArticleIDs.contains(article.id) == false
            }
            try articleRepository.delete(articlesToDelete, saveAfterOperation: true)
            deletedCount += articlesToDelete.count
            offset += batch.count - articlesToDelete.count
        }

        return deletedCount
    }

    private func fetchStarredExternalIDs(
        feedID: UUID,
        articles: [Article],
        diagnostics: inout MutableDiagnostics
    ) throws -> Set<String> {
        let result = try articleStateRepository.fetchStarredArticleExternalIDs(
            feedID: feedID,
            articleExternalIDs: articles.map(\.externalID),
            batchSize: batchSize
        )
        diagnostics.observeArticleStateBatches(
            processedCount: result.processedBatchCount,
            maximumMaterializedCount: result.maximumMaterializedBatchCount
        )
        return result.externalIDs
    }

    private func deleteOrphanStates(
        feedID: UUID,
        diagnostics: inout MutableDiagnostics
    ) throws -> ArticleStateOrphanCleanupResult {
        var offset = 0
        var inspectedCount = 0
        var deletedCount = 0
        var retainedStarredCount = 0
        var processedBatchCount = 0
        var maximumMaterializedBatchCount = 0

        while true {
            let states = try articleStateRepository.fetchOrphanSweepBatch(
                feedID: feedID,
                offset: offset,
                limit: batchSize
            )
            guard states.isEmpty == false else { break }

            diagnostics.observeArticleStateBatch(count: states.count)
            processedBatchCount += 1
            maximumMaterializedBatchCount = max(maximumMaterializedBatchCount, states.count)
            var retainedCount = 0
            var statesToDelete: [ArticleState] = []
            statesToDelete.reserveCapacity(states.count)

            for state in states {
                inspectedCount += 1
                let isLinked = try articleRepository.containsArticle(
                    feedID: feedID,
                    externalID: state.articleExternalID
                )
                if isLinked || state.isStarred {
                    retainedCount += 1
                    if isLinked == false, state.isStarred {
                        retainedStarredCount += 1
                    }
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

private extension ArticleRetentionCleanupScope {
    var logDescription: String {
        switch self {
        case .allFeeds:
            "allFeeds"
        case .feedIDs(let feedIDs):
            "feedIDs(count:\(feedIDs.count))"
        }
    }
}
