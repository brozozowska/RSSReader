import Foundation

enum FeedRefreshStatus: String, Sendable {
    case fetched
    case notModified
    case failed
}

struct FeedRefreshDiagnosticsSummary: Sendable, Equatable {
    let parserAnomalyCount: Int
    let rejectedEntryCount: Int

    init(
        parserAnomalyCount: Int = 0,
        rejectedEntryCount: Int = 0
    ) {
        self.parserAnomalyCount = max(0, parserAnomalyCount)
        self.rejectedEntryCount = max(0, rejectedEntryCount)
    }

    init(pipelineDiagnostics: FeedParsePipelineDiagnostics) {
        self.init(
            parserAnomalyCount: pipelineDiagnostics.parserAnomalies.count,
            rejectedEntryCount: pipelineDiagnostics.rejectedEntries.count
        )
    }

    var hasIssues: Bool {
        parserAnomalyCount > 0 || rejectedEntryCount > 0
    }
}

enum FeedRefreshPersistenceComponent: String, Sendable, CaseIterable {
    case articleUpserts
    case articleReconciliation
    case feedContentMetadata
    case feedFetchState
    case feedFetchLog
}

struct FeedRefreshTransactionBoundary: Sendable, Equatable {
    let atomicComponents: Set<FeedRefreshPersistenceComponent>
    let nonAtomicComponents: Set<FeedRefreshPersistenceComponent>

    var allComponents: Set<FeedRefreshPersistenceComponent> {
        atomicComponents.union(nonAtomicComponents)
    }

    var storesArticlesAtomically: Bool {
        atomicComponents.contains(.articleUpserts) &&
        atomicComponents.contains(.articleReconciliation)
    }

    static let singleFeedRefresh = FeedRefreshTransactionBoundary(
        atomicComponents: [
            .articleUpserts,
            .articleReconciliation,
            .feedContentMetadata,
            .feedFetchState
        ],
        nonAtomicComponents: [
            .feedFetchLog
        ]
    )
}

struct FeedRefreshResult: Sendable, Identifiable {
    let feedID: UUID
    let status: FeedRefreshStatus
    let startedAt: Date
    let finishedAt: Date
    let processedEntryCount: Int
    let upsertedEntryCount: Int
    let rejectedEntryCount: Int
    let diagnosticsSummary: FeedRefreshDiagnosticsSummary
    let errorDescription: String?

    var id: UUID {
        feedID
    }

    var duration: TimeInterval {
        max(0, finishedAt.timeIntervalSince(startedAt))
    }

    var isSuccess: Bool {
        status != .failed
    }

    init(
        feedID: UUID,
        status: FeedRefreshStatus,
        startedAt: Date,
        finishedAt: Date,
        processedEntryCount: Int = 0,
        upsertedEntryCount: Int = 0,
        rejectedEntryCount: Int = 0,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary = FeedRefreshDiagnosticsSummary(),
        errorDescription: String? = nil
    ) {
        self.feedID = feedID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.processedEntryCount = max(0, processedEntryCount)
        self.upsertedEntryCount = max(0, upsertedEntryCount)
        self.rejectedEntryCount = max(0, rejectedEntryCount)
        self.diagnosticsSummary = diagnosticsSummary
        self.errorDescription = errorDescription
    }

    static func fetched(
        feedID: UUID,
        startedAt: Date,
        finishedAt: Date = Date(),
        processedEntryCount: Int,
        upsertedEntryCount: Int,
        rejectedEntryCount: Int,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary = FeedRefreshDiagnosticsSummary()
    ) -> FeedRefreshResult {
        FeedRefreshResult(
            feedID: feedID,
            status: .fetched,
            startedAt: startedAt,
            finishedAt: finishedAt,
            processedEntryCount: processedEntryCount,
            upsertedEntryCount: upsertedEntryCount,
            rejectedEntryCount: rejectedEntryCount,
            diagnosticsSummary: diagnosticsSummary
        )
    }

    static func notModified(
        feedID: UUID,
        startedAt: Date,
        finishedAt: Date = Date(),
        diagnosticsSummary: FeedRefreshDiagnosticsSummary = FeedRefreshDiagnosticsSummary()
    ) -> FeedRefreshResult {
        FeedRefreshResult(
            feedID: feedID,
            status: .notModified,
            startedAt: startedAt,
            finishedAt: finishedAt,
            diagnosticsSummary: diagnosticsSummary
        )
    }

    static func failed(
        feedID: UUID,
        startedAt: Date,
        finishedAt: Date = Date(),
        processedEntryCount: Int = 0,
        upsertedEntryCount: Int = 0,
        rejectedEntryCount: Int = 0,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary = FeedRefreshDiagnosticsSummary(),
        errorDescription: String
    ) -> FeedRefreshResult {
        FeedRefreshResult(
            feedID: feedID,
            status: .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            processedEntryCount: processedEntryCount,
            upsertedEntryCount: upsertedEntryCount,
            rejectedEntryCount: rejectedEntryCount,
            diagnosticsSummary: diagnosticsSummary,
            errorDescription: errorDescription
        )
    }
}

struct FeedRefreshBatchSummary: Sendable, Equatable {
    let totalFeedCount: Int
    let fetchedCount: Int
    let notModifiedCount: Int
    let failedCount: Int
    let totalProcessedEntryCount: Int
    let totalUpsertedEntryCount: Int
    let totalRejectedEntryCount: Int
}

struct FeedRefreshBatchResult: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let results: [FeedRefreshResult]
    let summary: FeedRefreshBatchSummary

    init(
        startedAt: Date,
        finishedAt: Date,
        results: [FeedRefreshResult]
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.results = results
        self.summary = Self.makeSummary(from: results)
    }

    var duration: TimeInterval {
        max(0, finishedAt.timeIntervalSince(startedAt))
    }

    var failedResults: [FeedRefreshResult] {
        results.filter { $0.status == .failed }
    }

    var failedFeedIDs: [UUID] {
        failedResults.map(\.feedID)
    }

    var failureDescriptions: [String] {
        failedResults.compactMap(\.errorDescription)
    }

    private static func makeSummary(from results: [FeedRefreshResult]) -> FeedRefreshBatchSummary {
        FeedRefreshBatchSummary(
            totalFeedCount: results.count,
            fetchedCount: results.filter { $0.status == .fetched }.count,
            notModifiedCount: results.filter { $0.status == .notModified }.count,
            failedCount: results.filter { $0.status == .failed }.count,
            totalProcessedEntryCount: results.reduce(0) { $0 + $1.processedEntryCount },
            totalUpsertedEntryCount: results.reduce(0) { $0 + $1.upsertedEntryCount },
            totalRejectedEntryCount: results.reduce(0) { $0 + $1.rejectedEntryCount }
        )
    }
}
