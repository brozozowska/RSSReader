import Foundation

struct ArticleFeedSnapshotReconciliationResult {
    let projectionUpdateCount: Int
    let reconciledArticleCount: Int
    let upsertedArticleCount: Int
}

enum ArticleFeedSnapshotReconciliationStage: CaseIterable, Hashable, Sendable {
    case incomingIdentityMaterialization
    case snapshotCanonicalization
    case articleStateMaterialization
    case articleStateCanonicalization
    case articleStateDuplicateDeletion
    case projectionAndArchive
    case duplicateDeletion
    case payloadApply
}

struct ArticleFeedSnapshotReconciliationProgress: Sendable {
    let stage: ArticleFeedSnapshotReconciliationStage
    let processedItemCount: Int
    let totalItemCount: Int
}

typealias ArticleFeedSnapshotReconciliationProgressProbe = @MainActor (
    ArticleFeedSnapshotReconciliationProgress
) -> Void

enum ArticleFeedSnapshotCancellationCheckpoint: Equatable, Sendable {
    case beforeSnapshot
    case during(ArticleFeedSnapshotReconciliationStage)
    case beforeUpsert
    case afterUpsert
}

enum ArticleFeedSnapshotReconciliationPolicy {
    static let cancellationCheckpointInterval = 32
}
