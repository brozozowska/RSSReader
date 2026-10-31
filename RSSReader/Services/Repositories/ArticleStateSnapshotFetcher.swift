import Foundation
import SwiftData

@MainActor
struct SwiftDataArticleStateSnapshotFetcher: SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    let batchSize: Int
    let batchProbe: ArticleStateQueryBatchProbe?

    init(
        modelContext: ModelContext,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder = { _ in },
        batchSize: Int = ArticleStateQueryPolicy.batchSize,
        batchProbe: ArticleStateQueryBatchProbe? = nil
    ) {
        precondition(batchSize > 0)
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
        self.batchSize = batchSize
        self.batchProbe = batchProbe
    }

    func fetchSnapshots(
        feedID: UUID,
        articleExternalIDs: [String]
    ) throws -> [String: ArticleUserStateSnapshot] {
        let normalizedIDs = normalizedIdentifiers(articleExternalIDs)
        guard normalizedIDs.isEmpty == false else { return [:] }

        var snapshots: [String: ArticleUserStateSnapshot] = [:]
        var canonicalStates: [String: ArticleState] = [:]
        var offset = 0

        while offset < normalizedIDs.count {
            let upperBound = min(offset + batchSize, normalizedIDs.count)
            let identityBatch = Array(normalizedIDs[offset..<upperBound])
            let descriptor = FetchDescriptor<ArticleState>(
                predicate: #Predicate<ArticleState> { articleState in
                    articleState.feedID == feedID
                        && identityBatch.contains(articleState.articleExternalID)
                }
            )
            let states = try performFetch(descriptor)
            batchProbe?(
                ArticleStateQueryBatchObservation(
                    kind: .overlay,
                    feedIDs: [feedID],
                    requestedIdentityCount: identityBatch.count,
                    materializedStateCount: states.count,
                    countedArticleCount: 0,
                    appliedKeysetCursor: false
                )
            )

            for state in states {
                guard identityBatch.contains(state.articleExternalID) else { continue }
                if let existingState = canonicalStates[state.articleExternalID],
                   ArticleStateCanonicalization.isOrderedBefore(existingState, state) {
                    continue
                }
                canonicalStates[state.articleExternalID] = state
            }
            offset = upperBound
        }

        snapshots.reserveCapacity(canonicalStates.count)
        for (externalID, state) in canonicalStates {
            snapshots[externalID] = ArticleUserStateSnapshot(articleState: state)
        }
        return snapshots
    }

    func fetchSnapshots(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        let groupedArticleIDs = Dictionary(grouping: articles, by: \.feedID)
        var snapshotsByCompositeKey: [String: ArticleUserStateSnapshot] = [:]

        for (feedID, groupedArticles) in groupedArticleIDs {
            let snapshots = try fetchSnapshots(
                feedID: feedID,
                articleExternalIDs: groupedArticles.map(\.externalID)
            )
            for (externalID, snapshot) in snapshots {
                snapshotsByCompositeKey[articleCompositeKey(
                    feedID: feedID,
                    articleExternalID: externalID
                )] = snapshot
            }
        }
        return snapshotsByCompositeKey
    }

    func fetchMatchingStates(feedID: UUID, articleExternalID: String) throws -> [ArticleState] {
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { articleState in
                articleState.feedID == feedID && articleState.articleExternalID == articleExternalID
            }
        )
        let matchingStates = try modelContext.fetch(descriptor)
        return matchingStates.sorted(by: ArticleStateCanonicalization.isOrderedBefore)
    }

}
