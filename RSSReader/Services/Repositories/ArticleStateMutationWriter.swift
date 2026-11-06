import Foundation
import SwiftData

// Owns writes and operation-local save-failure recovery in the caller's context.
@MainActor
struct SwiftDataArticleStateMutationWriter: SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    let persistenceSaveOperation: SwiftDataRepositorySaveOperation
    let conflictResolutionPolicy: ArticleStateConflictResolutionPolicy

    func fetchOrCreate(feedID: UUID, articleExternalID: String) throws -> ArticleState {
        try fetchOrCreate(feedID: feedID, articleExternalID: articleExternalID, saveAfterCreation: true)
    }

    @discardableResult
    func upsert(feedID: UUID, articleExternalID: String, update: ArticleStateUpsert) throws -> ArticleState {
        let existingState = try fetchCanonicalState(
            feedID: feedID,
            articleExternalID: articleExternalID,
            removeDuplicates: true
        )
        let articleState = existingState ?? ArticleState(
            articleExternalID: articleExternalID,
            feedID: feedID,
            updatedAt: .distantPast
        )
        if existingState == nil {
            modelContext.insert(articleState)
        }
        let previousState = ArticleUserStateSnapshot(articleState: articleState)
        apply(update, to: articleState)
        do {
            try saveIfNeeded()
        } catch {
            // Undo only this mutation; unrelated pending context changes belong to their callers.
            if existingState == nil {
                modelContext.delete(articleState)
            } else {
                articleState.isRead = previousState.isRead
                articleState.readAt = previousState.readAt
                articleState.isStarred = previousState.isStarred
                articleState.starredAt = previousState.starredAt
                articleState.isHidden = previousState.isHidden
                articleState.hiddenAt = previousState.hiddenAt
                articleState.lastInteractionAt = previousState.lastInteractionAt
                articleState.updatedAt = previousState.updatedAt
            }
            throw error
        }
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
        try SwiftDataArticleStateSnapshotFetcher(modelContext: modelContext)
            .fetchMatchingStates(feedID: feedID, articleExternalID: articleExternalID)
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
