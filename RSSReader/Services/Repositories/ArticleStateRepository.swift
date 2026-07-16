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
    func fetchStarredArticleExternalIDs(feedID: UUID) throws -> Set<String>
    func fetchUnreadCounts(feedIDs: [UUID]) throws -> [UUID: Int]
    func fetchGlobalOrphanSweepBatch(offset: Int, limit: Int) throws -> [ArticleState]
    func deleteOrphanStates(
        feedID: UUID,
        keepingArticleExternalIDs articleExternalIDs: Set<String>,
        batchSize: Int
    ) throws -> ArticleStateOrphanCleanupResult

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

    func fetchStarredArticleExternalIDs(feedID: UUID) throws -> Set<String> {
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID && articleState.isStarred
            }
        )
        return Set(try modelContext.fetch(descriptor).map(\.articleExternalID))
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

    func deleteOrphanStates(
        feedID: UUID,
        keepingArticleExternalIDs articleExternalIDs: Set<String>,
        batchSize: Int
    ) throws -> ArticleStateOrphanCleanupResult {
        precondition(batchSize > 0)
        var offset = 0
        var inspectedCount = 0
        var deletedCount = 0
        var retainedStarredCount = 0
        var processedBatchCount = 0
        var maximumMaterializedBatchCount = 0

        while true {
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
            descriptor.fetchLimit = batchSize
            let states = try modelContext.fetch(descriptor)
            guard states.isEmpty == false else { break }

            processedBatchCount += 1
            maximumMaterializedBatchCount = max(maximumMaterializedBatchCount, states.count)
            var retainedCount = 0
            for state in states {
                inspectedCount += 1
                if articleExternalIDs.contains(state.articleExternalID) {
                    retainedCount += 1
                    continue
                }
                if state.isStarred {
                    retainedCount += 1
                    retainedStarredCount += 1
                    continue
                }

                modelContext.delete(state)
                deletedCount += 1
            }

            try saveIfNeeded()
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
        return matchingStates.sorted(by: articleStateCanonicalOrder)
    }

    private func articleStateCanonicalOrder(_ lhs: ArticleState, _ rhs: ArticleState) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
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
