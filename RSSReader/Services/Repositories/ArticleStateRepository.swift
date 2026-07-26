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
enum ArticleStateCanonicalization {
    static func isOrderedBefore(_ lhs: ArticleState, _ rhs: ArticleState) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
    }
}

@MainActor
struct SwiftDataArticleStateIdentityRepairer: SwiftDataRepositoryContext {
    private struct RepairPlan {
        var canonicalStatesByIdentity: [String: ArticleState]
        var duplicateStates: [ArticleState]
    }

    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder

    init(
        modelContext: ModelContext,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder = { _ in }
    ) {
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
    }

    func stageRepairs(
        feedID: UUID,
        normalizedIdentities: Set<String>,
        cancellationCheckpoint: (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void,
        progressProbe: ArticleFeedSnapshotReconciliationProgressProbe?
    ) throws {
        guard normalizedIdentities.isEmpty == false else { return }

        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID
            }
        )
        try cancellationCheckpoint(.during(.articleStateMaterialization))
        let feedStates = try performFetch(descriptor)
        let matchingStates = try materializeMatchingStates(
            feedStates,
            normalizedIdentities: normalizedIdentities,
            cancellationCheckpoint: cancellationCheckpoint,
            progressProbe: progressProbe
        )
        let repairPlan = try makeRepairPlan(
            matchingStates,
            normalizedIdentities: normalizedIdentities,
            cancellationCheckpoint: cancellationCheckpoint,
            progressProbe: progressProbe
        )
        try deleteDuplicateStates(
            repairPlan.duplicateStates,
            cancellationCheckpoint: cancellationCheckpoint,
            progressProbe: progressProbe
        )
    }

    private func materializeMatchingStates(
        _ feedStates: [ArticleState],
        normalizedIdentities: Set<String>,
        cancellationCheckpoint: (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void,
        progressProbe: ArticleFeedSnapshotReconciliationProgressProbe?
    ) throws -> [ArticleState] {
        let stage = ArticleFeedSnapshotReconciliationStage.articleStateMaterialization
        var matchingStates: [ArticleState] = []
        matchingStates.reserveCapacity(feedStates.count)
        recordProgress(
            stage: stage,
            processedItemCount: 0,
            totalItemCount: feedStates.count,
            progressProbe: progressProbe
        )

        for (index, articleState) in feedStates.enumerated() {
            try checkCancellation(
                stage: stage,
                beforeItemAt: index,
                cancellationCheckpoint: cancellationCheckpoint
            )
            if let identity = normalizedIdentifier(articleState.articleExternalID),
               normalizedIdentities.contains(identity) {
                matchingStates.append(articleState)
            }
            recordProgress(
                stage: stage,
                processedItemCount: index + 1,
                totalItemCount: feedStates.count,
                progressProbe: progressProbe
            )
        }
        try cancellationCheckpoint(.during(stage))
        return matchingStates
    }

    private func makeRepairPlan(
        _ matchingStates: [ArticleState],
        normalizedIdentities: Set<String>,
        cancellationCheckpoint: (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void,
        progressProbe: ArticleFeedSnapshotReconciliationProgressProbe?
    ) throws -> RepairPlan {
        let stage = ArticleFeedSnapshotReconciliationStage.articleStateCanonicalization
        let orderedIdentities = normalizedIdentities.sorted()
        let totalItemCount = matchingStates.count + orderedIdentities.count
        var repairPlan = RepairPlan(
            canonicalStatesByIdentity: [:],
            duplicateStates: []
        )
        repairPlan.canonicalStatesByIdentity.reserveCapacity(normalizedIdentities.count)
        repairPlan.duplicateStates.reserveCapacity(matchingStates.count)
        recordProgress(
            stage: stage,
            processedItemCount: 0,
            totalItemCount: totalItemCount,
            progressProbe: progressProbe
        )

        for (index, articleState) in matchingStates.enumerated() {
            try checkCancellation(
                stage: stage,
                beforeItemAt: index,
                cancellationCheckpoint: cancellationCheckpoint
            )
            let identity = normalizedIdentifier(articleState.articleExternalID)
                ?? articleState.articleExternalID
            if let canonicalState = repairPlan.canonicalStatesByIdentity[identity] {
                if ArticleStateCanonicalization.isOrderedBefore(articleState, canonicalState) {
                    repairPlan.canonicalStatesByIdentity[identity] = articleState
                    repairPlan.duplicateStates.append(canonicalState)
                } else {
                    repairPlan.duplicateStates.append(articleState)
                }
            } else {
                repairPlan.canonicalStatesByIdentity[identity] = articleState
            }
            recordProgress(
                stage: stage,
                processedItemCount: index + 1,
                totalItemCount: totalItemCount,
                progressProbe: progressProbe
            )
        }

        for (index, identity) in orderedIdentities.enumerated() {
            try checkCancellation(
                stage: stage,
                beforeItemAt: index,
                cancellationCheckpoint: cancellationCheckpoint
            )
            repairPlan.canonicalStatesByIdentity[identity]?.articleExternalID = identity
            recordProgress(
                stage: stage,
                processedItemCount: matchingStates.count + index + 1,
                totalItemCount: totalItemCount,
                progressProbe: progressProbe
            )
        }
        try cancellationCheckpoint(.during(stage))
        return repairPlan
    }

    private func deleteDuplicateStates(
        _ duplicateStates: [ArticleState],
        cancellationCheckpoint: (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void,
        progressProbe: ArticleFeedSnapshotReconciliationProgressProbe?
    ) throws {
        let stage = ArticleFeedSnapshotReconciliationStage.articleStateDuplicateDeletion
        recordProgress(
            stage: stage,
            processedItemCount: 0,
            totalItemCount: duplicateStates.count,
            progressProbe: progressProbe
        )

        for (index, duplicateState) in duplicateStates.enumerated() {
            try checkCancellation(
                stage: stage,
                beforeItemAt: index,
                cancellationCheckpoint: cancellationCheckpoint
            )
            modelContext.delete(duplicateState)
            recordProgress(
                stage: stage,
                processedItemCount: index + 1,
                totalItemCount: duplicateStates.count,
                progressProbe: progressProbe
            )
        }
        try cancellationCheckpoint(.during(stage))
    }

    private func checkCancellation(
        stage: ArticleFeedSnapshotReconciliationStage,
        beforeItemAt index: Int,
        cancellationCheckpoint: (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void
    ) throws {
        guard index.isMultiple(
            of: ArticleFeedSnapshotReconciliationPolicy.cancellationCheckpointInterval
        ) else {
            return
        }
        try cancellationCheckpoint(.during(stage))
    }

    private func recordProgress(
        stage: ArticleFeedSnapshotReconciliationStage,
        processedItemCount: Int,
        totalItemCount: Int,
        progressProbe: ArticleFeedSnapshotReconciliationProgressProbe?
    ) {
        progressProbe?(
            ArticleFeedSnapshotReconciliationProgress(
                stage: stage,
                processedItemCount: processedItemCount,
                totalItemCount: totalItemCount
            )
        )
    }
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
    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int]
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

@MainActor
final class SwiftDataArticleStateRepository: ArticleStateRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext
    private let conflictResolutionPolicy: ArticleStateConflictResolutionPolicy

    init(
        modelContext: ModelContext,
        conflictResolutionPolicy: ArticleStateConflictResolutionPolicy = .lastWriteWinsByUpdatedAt
    ) {
        self.modelContext = modelContext
        self.conflictResolutionPolicy = conflictResolutionPolicy
    }

    func fetchState(feedID: UUID, articleExternalID: String) throws -> ArticleState? {
        try fetchMatchingStates(feedID: feedID, articleExternalID: articleExternalID).first
    }

    func fetchOrCreate(feedID: UUID, articleExternalID: String) throws -> ArticleState {
        try fetchOrCreate(feedID: feedID, articleExternalID: articleExternalID, saveAfterCreation: true)
    }

    func fetchStateSnapshot(feedID: UUID, articleExternalID: String) throws -> ArticleUserStateSnapshot? {
        try fetchState(feedID: feedID, articleExternalID: articleExternalID)
            .map(ArticleUserStateSnapshot.init(articleState:))
    }

    func fetchStateSnapshots(feedID: UUID, articleExternalIDs: [String]) throws -> [String: ArticleUserStateSnapshot] {
        let normalizedIDs = normalizedIdentifiers(articleExternalIDs)

        guard normalizedIDs.isEmpty == false else { return [:] }

        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID
                    && normalizedIDs.contains(articleState.articleExternalID)
            }
        )

        let states = try modelContext.fetch(descriptor)
        return states.reduce(into: [String: ArticleUserStateSnapshot]()) { partialResult, state in
            guard normalizedIDs.contains(state.articleExternalID) else { return }
            partialResult[state.articleExternalID] = ArticleUserStateSnapshot(articleState: state)
        }
    }

    func fetchStateSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        let groupedArticleIDs = Dictionary(grouping: articles, by: \.feedID)
        var snapshotsByCompositeKey: [String: ArticleUserStateSnapshot] = [:]

        for (feedID, groupedArticles) in groupedArticleIDs {
            let articleExternalIDs = groupedArticles.map(\.externalID)
            let snapshots = try fetchStateSnapshots(feedID: feedID, articleExternalIDs: articleExternalIDs)

            for (externalID, snapshot) in snapshots {
                snapshotsByCompositeKey[articleCompositeKey(feedID: feedID, articleExternalID: externalID)] = snapshot
            }
        }

        return snapshotsByCompositeKey
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

    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int] {
        let normalizedFeedIDs = Set(feedIDs)
        guard normalizedFeedIDs.isEmpty == false else { return [:] }

        let articleDescriptor = FetchDescriptor<Article>()
        let articles = try modelContext.fetch(articleDescriptor)

        let relevantArticles = articles.filter { normalizedFeedIDs.contains($0.feedID) }
        guard relevantArticles.isEmpty == false else {
            return Dictionary(uniqueKeysWithValues: normalizedFeedIDs.map { ($0, 0) })
        }

        let stateSnapshots = try fetchStateSnapshots(for: relevantArticles)
        var unreadCounts = Dictionary(uniqueKeysWithValues: normalizedFeedIDs.map { ($0, 0) })

        for article in relevantArticles {
            let key = articleCompositeKey(feedID: article.feedID, articleExternalID: article.externalID)
            let state = stateSnapshots[key]
            let isHidden = state?.isHidden ?? false
            let isRead = state?.isRead ?? false

            guard isHidden == false, isRead == false else { continue }
            unreadCounts[article.feedID, default: 0] += 1
        }

        return unreadCounts
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
        let articleState = try fetchOrCreate(
            feedID: feedID,
            articleExternalID: articleExternalID,
            saveAfterCreation: false
        )
        apply(update, to: articleState)
        try saveIfNeeded()
        return articleState
    }

    @discardableResult
    func bulkSetRead(feedID: UUID, articleExternalIDs: [String], isRead: Bool, at: Date = .now) throws -> [ArticleState] {
        try bulkUpdate(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs,
            update: ArticleStateUpsert(
                isRead: isRead,
                readAt: isRead ? at : nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
    }

    @discardableResult
    func bulkSetStarred(feedID: UUID, articleExternalIDs: [String], isStarred: Bool, at: Date = .now) throws -> [ArticleState] {
        try bulkUpdate(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs,
            update: ArticleStateUpsert(
                isStarred: isStarred,
                starredAt: isStarred ? at : nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
    }

    @discardableResult
    func bulkSetHidden(feedID: UUID, articleExternalIDs: [String], isHidden: Bool, at: Date = .now) throws -> [ArticleState] {
        try bulkUpdate(
            feedID: feedID,
            articleExternalIDs: articleExternalIDs,
            update: ArticleStateUpsert(
                isHidden: isHidden,
                hiddenAt: isHidden ? at : nil,
                lastInteractionAt: at,
                updatedAt: at
            )
        )
    }

    func delete(_ states: [ArticleState], saveAfterOperation: Bool = true) throws {
        guard states.isEmpty == false else { return }

        for state in states {
            modelContext.delete(state)
        }
        if saveAfterOperation {
            try saveIfNeeded()
        }
    }

    func save() throws {
        try saveIfNeeded(force: true)
    }

    private func fetchOrCreate(
        feedID: UUID,
        articleExternalID: String,
        saveAfterCreation: Bool
    ) throws -> ArticleState {
        if let existingState = try fetchCanonicalState(
            feedID: feedID,
            articleExternalID: articleExternalID,
            removeDuplicates: true
        ) {
            return existingState
        }

        let articleState = ArticleState(
            articleExternalID: articleExternalID,
            feedID: feedID,
            updatedAt: .distantPast
        )
        modelContext.insert(articleState)
        if saveAfterCreation {
            try saveIfNeeded()
        }
        return articleState
    }

    private func bulkUpdate(
        feedID: UUID,
        articleExternalIDs: [String],
        update: ArticleStateUpsert
    ) throws -> [ArticleState] {
        let normalizedIDs = normalizedIdentifiers(articleExternalIDs)
        guard normalizedIDs.isEmpty == false else { return [] }

        let articleStates = try normalizedIDs.map { articleExternalID in
            let articleState = try fetchOrCreate(
                feedID: feedID,
                articleExternalID: articleExternalID,
                saveAfterCreation: false
            )
            apply(update, to: articleState)
            return articleState
        }

        try saveIfNeeded()
        return articleStates
    }

    private func fetchCanonicalState(
        feedID: UUID,
        articleExternalID: String,
        removeDuplicates: Bool
    ) throws -> ArticleState? {
        let matchingStates = try fetchMatchingStates(feedID: feedID, articleExternalID: articleExternalID)
        guard let canonicalState = matchingStates.first else { return nil }

        if removeDuplicates {
            let duplicateStates = matchingStates.dropFirst()
            if duplicateStates.isEmpty == false {
                for duplicateState in duplicateStates {
                    modelContext.delete(duplicateState)
                }
                try saveIfNeeded()
            }
        }

        return canonicalState
    }

    private func fetchMatchingStates(feedID: UUID, articleExternalID: String) throws -> [ArticleState] {
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID && articleState.articleExternalID == articleExternalID
            }
        )
        let matchingStates = try modelContext.fetch(descriptor)
        return matchingStates.sorted(by: ArticleStateCanonicalization.isOrderedBefore)
    }

    private func apply(_ update: ArticleStateUpsert, to articleState: ArticleState) {
        guard shouldApply(update, to: articleState) else { return }

        var didChange = false

        if let isRead = update.isRead, articleState.isRead != isRead {
            articleState.isRead = isRead
            articleState.readAt = isRead ? (update.readAt ?? update.updatedAt) : nil
            didChange = true
        } else if update.isRead == nil, let readAt = update.readAt {
            articleState.readAt = readAt
            didChange = true
        }

        if let isStarred = update.isStarred, articleState.isStarred != isStarred {
            articleState.isStarred = isStarred
            articleState.starredAt = isStarred ? (update.starredAt ?? update.updatedAt) : nil
            didChange = true
        } else if update.isStarred == nil, let starredAt = update.starredAt {
            articleState.starredAt = starredAt
            didChange = true
        }

        if let isHidden = update.isHidden, articleState.isHidden != isHidden {
            articleState.isHidden = isHidden
            articleState.hiddenAt = isHidden ? (update.hiddenAt ?? update.updatedAt) : nil
            didChange = true
        } else if update.isHidden == nil, let hiddenAt = update.hiddenAt {
            articleState.hiddenAt = hiddenAt
            didChange = true
        }

        if let lastInteractionAt = update.lastInteractionAt {
            articleState.lastInteractionAt = lastInteractionAt
            didChange = true
        } else if didChange {
            articleState.lastInteractionAt = update.updatedAt
        }

        if didChange || update.lastInteractionAt != nil {
            articleState.updatedAt = update.updatedAt
        }
    }

    private func shouldApply(_ update: ArticleStateUpsert, to articleState: ArticleState) -> Bool {
        switch conflictResolutionPolicy {
        case .lastWriteWinsByUpdatedAt:
            return update.updatedAt >= articleState.updatedAt
        }
    }
}
