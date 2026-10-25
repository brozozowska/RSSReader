import Foundation
import SwiftData

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
