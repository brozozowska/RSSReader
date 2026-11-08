import Foundation
import SwiftData

struct ArticleUserStateSnapshot: Sendable {
    let articleExternalID: String
    let feedID: UUID
    let isRead: Bool
    let readAt: Date?
    let isStarred: Bool
    let starredAt: Date?
    let isHidden: Bool
    let hiddenAt: Date?
    let lastInteractionAt: Date?
    let updatedAt: Date

    init(articleState: ArticleState) {
        self.articleExternalID = articleState.articleExternalID
        self.feedID = articleState.feedID
        self.isRead = articleState.isRead
        self.readAt = articleState.readAt
        self.isStarred = articleState.isStarred
        self.starredAt = articleState.starredAt
        self.isHidden = articleState.isHidden
        self.hiddenAt = articleState.hiddenAt
        self.lastInteractionAt = articleState.lastInteractionAt
        self.updatedAt = articleState.updatedAt
    }
}

enum ArticleStateQueryBatchKind: Equatable, Sendable {
    case overlay
    case aggregateStateScan
    case unreadArticleCount
    case starredArticleCount
}

struct ArticleStateQueryBatchObservation: Equatable, Sendable {
    let kind: ArticleStateQueryBatchKind
    let feedIDs: Set<UUID>
    let requestedIdentityCount: Int
    let materializedStateCount: Int
    let countedArticleCount: Int
    let appliedKeysetCursor: Bool
}

typealias ArticleStateQueryBatchProbe = @MainActor (ArticleStateQueryBatchObservation) -> Void
typealias ArticleStateAggregateCancellationCheckpoint = @MainActor () throws -> Void

nonisolated enum ArticleStateQueryPolicy {
    static let batchSize = 256
}

struct ArticleStateOrphanCleanupResult: Equatable, Sendable {
    let inspectedCount: Int
    let deletedCount: Int
    let retainedStarredCount: Int
    let processedBatchCount: Int
    let maximumMaterializedBatchCount: Int
}

struct ArticleStateExternalIDBatchResult: Equatable, Sendable {
    let externalIDs: Set<String>
    let processedBatchCount: Int
    let maximumMaterializedBatchCount: Int
}

struct ArticleStateAggregateCounts: Equatable, Sendable {
    let unreadByFeedID: [UUID: Int]
    let starredByFeedID: [UUID: Int]
}

struct ArticleStateUpsert: Sendable {
    var isRead: Bool? = nil
    var readAt: Date? = nil
    var isStarred: Bool? = nil
    var starredAt: Date? = nil
    var isHidden: Bool? = nil
    var hiddenAt: Date? = nil
    var lastInteractionAt: Date? = nil
    var updatedAt: Date = .now
}

enum ArticleStateConflictResolutionPolicy: Sendable {
    case lastWriteWinsByUpdatedAt
}

@MainActor
protocol ArticleStateRepository {
    func fetchState(feedID: UUID, articleExternalID: String) throws -> ArticleState?
    func fetchOrCreate(feedID: UUID, articleExternalID: String) throws -> ArticleState
    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot?
    func fetchStateSnapshots(feedID: UUID, articleExternalIDs: [String]) throws -> [String: ArticleUserStateSnapshot]
    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot]
    func fetchStarredArticleExternalIDs(
        feedID: UUID,
        articleExternalIDs: [String],
        batchSize: Int
    ) throws -> ArticleStateExternalIDBatchResult
    func fetchAggregateCounts(feedIDs: [UUID]) throws -> ArticleStateAggregateCounts
    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int]
    func fetchStarredCounts(feedIDs: [UUID]) throws -> [UUID: Int]
    func fetchGlobalOrphanSweepBatch(offset: Int, limit: Int) throws -> [ArticleState]
    func fetchOrphanSweepBatch(feedID: UUID, offset: Int, limit: Int) throws -> [ArticleState]

    @discardableResult
    func upsert(feedID: UUID, articleExternalID: String, update: ArticleStateUpsert) throws -> ArticleState

    @discardableResult
    func bulkSetRead(feedID: UUID, articleExternalIDs: [String], isRead: Bool, at: Date) throws -> [ArticleState]

    @discardableResult
    func bulkSetStarred(feedID: UUID, articleExternalIDs: [String], isStarred: Bool, at: Date) throws -> [ArticleState]

    @discardableResult
    func bulkSetHidden(feedID: UUID, articleExternalIDs: [String], isHidden: Bool, at: Date) throws -> [ArticleState]

    func delete(_ states: [ArticleState], saveAfterOperation: Bool) throws
    func save() throws
}

// Stable service boundary; helpers share this context without adding save or repair to reads.
@MainActor
final class SwiftDataArticleStateRepository: ArticleStateRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    let persistenceSaveOperation: SwiftDataRepositorySaveOperation
    private let snapshotFetcher: SwiftDataArticleStateSnapshotFetcher
    private let aggregateReader: SwiftDataArticleStateAggregateReader
    private let mutationWriter: SwiftDataArticleStateMutationWriter

    init(
        modelContext: ModelContext,
        conflictResolutionPolicy: ArticleStateConflictResolutionPolicy = .lastWriteWinsByUpdatedAt,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder = { _ in },
        persistenceSaveOperation: @escaping SwiftDataRepositorySaveOperation = { try $0.save() },
        queryBatchSize: Int = ArticleStateQueryPolicy.batchSize,
        queryBatchProbe: ArticleStateQueryBatchProbe? = nil,
        aggregateCancellationCheckpoint: @escaping ArticleStateAggregateCancellationCheckpoint = {
            try Task.checkCancellation()
        }
    ) {
        precondition(queryBatchSize > 0)
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
        self.persistenceSaveOperation = persistenceSaveOperation
        self.snapshotFetcher = SwiftDataArticleStateSnapshotFetcher(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder,
            batchSize: queryBatchSize,
            batchProbe: queryBatchProbe
        )
        self.aggregateReader = SwiftDataArticleStateAggregateReader(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder,
            queryBatchSize: queryBatchSize,
            queryBatchProbe: queryBatchProbe,
            aggregateCancellationCheckpoint: aggregateCancellationCheckpoint
        )
        self.mutationWriter = SwiftDataArticleStateMutationWriter(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder,
            persistenceSaveOperation: persistenceSaveOperation,
            conflictResolutionPolicy: conflictResolutionPolicy
        )
    }

    func fetchState(feedID: UUID, articleExternalID: String) throws -> ArticleState? {
        try snapshotFetcher.fetchMatchingStates(feedID: feedID, articleExternalID: articleExternalID).first
    }

    func fetchOrCreate(feedID: UUID, articleExternalID: String) throws -> ArticleState {
        try mutationWriter.fetchOrCreate(feedID: feedID, articleExternalID: articleExternalID)
    }

    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot? {
        try fetchState(feedID: feedID, articleExternalID: articleExternalID)
            .map(ArticleUserStateSnapshot.init(articleState:))
    }

    func fetchStateSnapshots(feedID: UUID, articleExternalIDs: [String]) throws -> [String: ArticleUserStateSnapshot] {
        try snapshotFetcher.fetchSnapshots(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs
        )
    }

    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        try snapshotFetcher.fetchSnapshots(for: articles)
    }

    func fetchStarredArticleExternalIDs(
        feedID: UUID,
        articleExternalIDs: [String],
        batchSize: Int
    ) throws -> ArticleStateExternalIDBatchResult {
        precondition(batchSize > 0)
        let normalizedIDs = normalizedIdentifiers(articleExternalIDs)
        guard normalizedIDs.isEmpty == false else {
            return ArticleStateExternalIDBatchResult(
                externalIDs: [],
                processedBatchCount: 0,
                maximumMaterializedBatchCount: 0
            )
        }

        var offset = 0
        var starredExternalIDs: Set<String> = []
        var processedBatchCount = 0
        var maximumMaterializedBatchCount = 0

        while true {
            var descriptor = FetchDescriptor<ArticleState>(
                predicate: #Predicate<ArticleState> { articleState in
                    articleState.feedID == feedID
                        && articleState.isStarred
                        && normalizedIDs.contains(articleState.articleExternalID)
                },
                sortBy: [
                    SortDescriptor(\ArticleState.updatedAt, order: .forward),
                    SortDescriptor(\ArticleState.id, order: .forward)
                ]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize
            let states = try modelContext.fetch(descriptor)
            guard states.isEmpty == false else { break }

            processedBatchCount += 1
            maximumMaterializedBatchCount = max(maximumMaterializedBatchCount, states.count)
            starredExternalIDs.formUnion(states.map(\.articleExternalID))
            offset += states.count
        }

        return ArticleStateExternalIDBatchResult(
            externalIDs: starredExternalIDs,
            processedBatchCount: processedBatchCount,
            maximumMaterializedBatchCount: maximumMaterializedBatchCount
        )
    }

    func fetchAggregateCounts(feedIDs: [UUID]) throws -> ArticleStateAggregateCounts {
        try aggregateReader.fetchAggregateCounts(feedIDs: feedIDs)
    }

    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int] {
        try aggregateReader.fetchUnreadCounts(feedIDs: feedIDs)
    }

    func fetchStarredCounts(feedIDs: [UUID]) throws -> [UUID: Int] {
        try aggregateReader.fetchStarredCounts(feedIDs: feedIDs)
    }

    func fetchGlobalOrphanSweepBatch(offset: Int, limit: Int) throws -> [ArticleState] {
        precondition(offset >= 0)
        precondition(limit > 0)
        var descriptor = FetchDescriptor<ArticleState>(
            sortBy: [
                SortDescriptor(\ArticleState.updatedAt, order: .forward),
                SortDescriptor(\ArticleState.id, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func fetchOrphanSweepBatch(feedID: UUID, offset: Int, limit: Int) throws -> [ArticleState] {
        precondition(offset >= 0)
        precondition(limit > 0)
        var descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID
            },
            sortBy: [
                SortDescriptor(\ArticleState.updatedAt, order: .forward),
                SortDescriptor(\ArticleState.id, order: .forward)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    func upsert(feedID: UUID, articleExternalID: String, update: ArticleStateUpsert) throws -> ArticleState {
        try mutationWriter.upsert(feedID: feedID, articleExternalID: articleExternalID, update: update)
    }

    @discardableResult
    func bulkSetRead(feedID: UUID, articleExternalIDs: [String], isRead: Bool, at: Date = .now) throws -> [ArticleState] {
        try mutationWriter.bulkSetRead(feedID: feedID, articleExternalIDs: articleExternalIDs, isRead: isRead, at: at)
    }

    @discardableResult
    func bulkSetStarred(feedID: UUID, articleExternalIDs: [String], isStarred: Bool, at: Date = .now) throws -> [ArticleState] {
        try mutationWriter.bulkSetStarred(feedID: feedID, articleExternalIDs: articleExternalIDs, isStarred: isStarred, at: at)
    }

    @discardableResult
    func bulkSetHidden(feedID: UUID, articleExternalIDs: [String], isHidden: Bool, at: Date = .now) throws -> [ArticleState] {
        try mutationWriter.bulkSetHidden(feedID: feedID, articleExternalIDs: articleExternalIDs, isHidden: isHidden, at: at)
    }

    func delete(_ states: [ArticleState], saveAfterOperation: Bool = true) throws {
        try mutationWriter.delete(states, saveAfterOperation: saveAfterOperation)
    }

    func save() throws {
        try mutationWriter.save()
    }
}
