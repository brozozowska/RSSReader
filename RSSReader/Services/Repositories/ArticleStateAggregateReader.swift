import Foundation
import SwiftData

private struct ArticleStateAggregateCursor {
    let updatedAt: Date
    let stateID: UUID
}

private struct ArticleStateAggregateMetrics: OptionSet {
    let rawValue: Int

    static let unread = ArticleStateAggregateMetrics(rawValue: 1 << 0)
    static let starred = ArticleStateAggregateMetrics(rawValue: 1 << 1)
    static let all: ArticleStateAggregateMetrics = [.unread, .starred]
}

// Read-only engine shared by combined sidebar counts and metric-specific badge queries.
@MainActor
struct SwiftDataArticleStateAggregateReader: SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    let queryBatchSize: Int
    let queryBatchProbe: ArticleStateQueryBatchProbe?
    let aggregateCancellationCheckpoint: ArticleStateAggregateCancellationCheckpoint

    func fetchAggregateCounts(feedIDs: [UUID]) throws -> ArticleStateAggregateCounts {
        try fetchAggregateCounts(feedIDs: feedIDs, metrics: .all)
    }

    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int] {
        try fetchAggregateCounts(feedIDs: feedIDs, metrics: .unread).unreadByFeedID
    }

    func fetchStarredCounts(feedIDs: [UUID]) throws -> [UUID: Int] {
        try fetchAggregateCounts(feedIDs: feedIDs, metrics: .starred).starredByFeedID
    }

    private func fetchAggregateCounts(
        feedIDs: [UUID],
        metrics: ArticleStateAggregateMetrics
    ) throws -> ArticleStateAggregateCounts {
        let normalizedFeedIDs = Set(feedIDs)
        guard normalizedFeedIDs.isEmpty == false else {
            return ArticleStateAggregateCounts(unreadByFeedID: [:], starredByFeedID: [:])
        }

        try aggregateCancellationCheckpoint()
        let requestedFeedIDs = normalizedFeedIDs.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
        var totalArticleCountsByFeedID: [UUID: Int] = [:]
        var excludedUnreadCountsByFeedID: [UUID: Int] = [:]
        var starredCountsByFeedID: [UUID: Int] = [:]
        totalArticleCountsByFeedID.reserveCapacity(requestedFeedIDs.count)

        for feedID in requestedFeedIDs {
            try aggregateCancellationCheckpoint()
            if metrics.contains(.unread) {
                let articleDescriptor = FetchDescriptor<Article>(
                    predicate: #Predicate<Article> { article in
                        article.feedID == feedID
                    }
                )
                totalArticleCountsByFeedID[feedID] = try performFetchCount(articleDescriptor)
            }

            var pendingExcludedUnreadIDs: [String] = []
            var pendingStarredIDs: [String] = []
            var cursor: ArticleStateAggregateCursor?
            var canonicalExternalIDs: Set<String> = []

            while true {
                try aggregateCancellationCheckpoint()
                let states = try fetchAggregateStateBatch(feedID: feedID, cursor: cursor)
                guard states.isEmpty == false else { break }

                queryBatchProbe?(
                    ArticleStateQueryBatchObservation(
                        kind: .aggregateStateScan,
                        feedIDs: [feedID],
                        requestedIdentityCount: 0,
                        materializedStateCount: states.count,
                        countedArticleCount: 0,
                        appliedKeysetCursor: cursor != nil
                    )
                )

                for state in states {
                    guard canonicalExternalIDs.insert(state.articleExternalID).inserted else {
                        continue
                    }

                    if metrics.contains(.unread), state.isRead || state.isHidden {
                        pendingExcludedUnreadIDs.append(state.articleExternalID)
                        if pendingExcludedUnreadIDs.count == queryBatchSize {
                            excludedUnreadCountsByFeedID[feedID, default: 0] += try countArticles(
                                feedID: feedID,
                                externalIDs: pendingExcludedUnreadIDs,
                                kind: .unreadArticleCount
                            )
                            pendingExcludedUnreadIDs.removeAll(keepingCapacity: true)
                        }
                    }
                    if metrics.contains(.starred), state.isStarred && state.isHidden == false {
                        pendingStarredIDs.append(state.articleExternalID)
                        if pendingStarredIDs.count == queryBatchSize {
                            starredCountsByFeedID[feedID, default: 0] += try countArticles(
                                feedID: feedID,
                                externalIDs: pendingStarredIDs,
                                kind: .starredArticleCount
                            )
                            pendingStarredIDs.removeAll(keepingCapacity: true)
                        }
                    }
                }

                guard let lastState = states.last else { break }
                cursor = ArticleStateAggregateCursor(
                    updatedAt: lastState.updatedAt,
                    stateID: lastState.id
                )
                try aggregateCancellationCheckpoint()
            }

            if metrics.contains(.unread), pendingExcludedUnreadIDs.isEmpty == false {
                excludedUnreadCountsByFeedID[feedID, default: 0] += try countArticles(
                    feedID: feedID,
                    externalIDs: pendingExcludedUnreadIDs,
                    kind: .unreadArticleCount
                )
            }
            if metrics.contains(.starred), pendingStarredIDs.isEmpty == false {
                starredCountsByFeedID[feedID, default: 0] += try countArticles(
                    feedID: feedID,
                    externalIDs: pendingStarredIDs,
                    kind: .starredArticleCount
                )
            }
        }
        try aggregateCancellationCheckpoint()

        let unreadCountsByFeedID: [UUID: Int]
        if metrics.contains(.unread) {
            unreadCountsByFeedID = Dictionary(uniqueKeysWithValues: requestedFeedIDs.map { feedID in
                let totalCount = totalArticleCountsByFeedID[feedID, default: 0]
                let excludedCount = excludedUnreadCountsByFeedID[feedID, default: 0]
                return (feedID, max(0, totalCount - excludedCount))
            })
        } else {
            unreadCountsByFeedID = [:]
        }
        let resolvedStarredCountsByFeedID: [UUID: Int]
        if metrics.contains(.starred) {
            resolvedStarredCountsByFeedID = Dictionary(uniqueKeysWithValues: requestedFeedIDs.map { feedID in
                (feedID, starredCountsByFeedID[feedID, default: 0])
            })
        } else {
            resolvedStarredCountsByFeedID = [:]
        }
        return ArticleStateAggregateCounts(
            unreadByFeedID: unreadCountsByFeedID,
            starredByFeedID: resolvedStarredCountsByFeedID
        )
    }

    private func fetchAggregateStateBatch(
        feedID: UUID,
        cursor: ArticleStateAggregateCursor?
    ) throws -> [ArticleState] {
        let sortDescriptors = [
            SortDescriptor(\ArticleState.updatedAt, order: .reverse),
            SortDescriptor(\ArticleState.id, order: .reverse)
        ]
        var descriptor: FetchDescriptor<ArticleState>
        if let cursor {
            let cursorUpdatedAt = cursor.updatedAt
            let cursorStateID = cursor.stateID
            descriptor = FetchDescriptor<ArticleState>(
                predicate: #Predicate<ArticleState> { articleState in
                    articleState.feedID == feedID
                        && (
                            articleState.updatedAt < cursorUpdatedAt
                                || (
                                    articleState.updatedAt == cursorUpdatedAt
                                        && articleState.id < cursorStateID
                                )
                        )
                },
                sortBy: sortDescriptors
            )
        } else {
            descriptor = FetchDescriptor<ArticleState>(
                predicate: #Predicate<ArticleState> { articleState in
                    articleState.feedID == feedID
                },
                sortBy: sortDescriptors
            )
        }
        descriptor.fetchLimit = queryBatchSize
        return try performFetch(descriptor)
    }

    private func countArticles(
        feedID: UUID,
        externalIDs: [String],
        kind: ArticleStateQueryBatchKind
    ) throws -> Int {
        try aggregateCancellationCheckpoint()
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID && externalIDs.contains(article.externalID)
            }
        )
        let count = try performFetchCount(descriptor)
        queryBatchProbe?(
            ArticleStateQueryBatchObservation(
                kind: kind,
                feedIDs: [feedID],
                requestedIdentityCount: externalIDs.count,
                materializedStateCount: 0,
                countedArticleCount: count,
                appliedKeysetCursor: false
            )
        )
        return count
    }

}
