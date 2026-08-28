import Foundation

enum FeedRefreshStatus: String, Sendable {
    case fetched
    case notModified
    case failed
    case cancelled
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

    var hasSoftFailures: Bool {
        hasIssues
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

struct FeedRefreshNotModifiedPolicy: Sendable, Equatable {
    let resultStatus: FeedRefreshStatus
    let updatesLastFetchedAt: Bool
    let updatesCacheValidatorsFromResponse: Bool
    let clearsLastSyncError: Bool
    let updatesLastSuccessfulFetchAt: Bool

    static let `default` = FeedRefreshNotModifiedPolicy(
        resultStatus: .notModified,
        updatesLastFetchedAt: true,
        updatesCacheValidatorsFromResponse: true,
        clearsLastSyncError: true,
        updatesLastSuccessfulFetchAt: false
    )
}

struct FeedRefreshDiagnosticsPolicy: Sendable, Equatable {
    let includesParserAnomaliesInDiagnostics: Bool
    let includesRejectedEntriesInDiagnostics: Bool
    let logsParserAnomalies: Bool
    let logsRejectedEntries: Bool
    let parserAnomaliesAreSoftFailures: Bool
    let rejectedEntriesAreSoftFailures: Bool
    let maximumLoggedParserAnomalyDetails: Int
    let maximumLoggedRejectedEntryDetails: Int

    static let `default` = FeedRefreshDiagnosticsPolicy(
        includesParserAnomaliesInDiagnostics: true,
        includesRejectedEntriesInDiagnostics: true,
        logsParserAnomalies: true,
        logsRejectedEntries: true,
        parserAnomaliesAreSoftFailures: true,
        rejectedEntriesAreSoftFailures: true,
        maximumLoggedParserAnomalyDetails: 10,
        maximumLoggedRejectedEntryDetails: 10
    )

    func makeSummary(from diagnostics: FeedParsePipelineDiagnostics) -> FeedRefreshDiagnosticsSummary {
        FeedRefreshDiagnosticsSummary(
            parserAnomalyCount: includesParserAnomaliesInDiagnostics ? diagnostics.parserAnomalies.count : 0,
            rejectedEntryCount: includesRejectedEntriesInDiagnostics ? diagnostics.rejectedEntries.count : 0
        )
    }

    func treatsDiagnosticsAsSoftFailure(_ diagnostics: FeedParsePipelineDiagnostics) -> Bool {
        let hasParserAnomalies = parserAnomaliesAreSoftFailures && diagnostics.parserAnomalies.isEmpty == false
        let hasRejectedEntries = rejectedEntriesAreSoftFailures && diagnostics.rejectedEntries.isEmpty == false
        return hasParserAnomalies || hasRejectedEntries
    }
}

enum FeedRefreshReconciliationPolicy: String, Sendable {
    case markMissingArticlesAsArchived
}

enum FeedRefreshBatchErrorPolicy: String, Sendable {
    case continueOnError
}

struct FeedRefreshBatchPolicy: Sendable, Equatable {
    let errorPolicy: FeedRefreshBatchErrorPolicy
    let deduplicatesFeedIDs: Bool
    let maxConcurrentRefreshes: Int

    static let `default` = FeedRefreshBatchPolicy(
        errorPolicy: .continueOnError,
        deduplicatesFeedIDs: true,
        maxConcurrentRefreshes: 3
    )
}

enum FeedRefreshInFlightPolicy: String, Sendable {
    case shareExistingTaskResult
}

enum FeedRefreshInFlightCallerCancellationPolicy: String, Sendable {
    case cancelSharedTaskWhenLastWaiterCancels
}

enum FeedRefreshTrigger: String, Sendable {
    case manual
    case background
}

struct FeedRefreshResult: Sendable, Identifiable {
    let feedID: UUID
    let status: FeedRefreshStatus
    let startedAt: Date
    let finishedAt: Date
    let processedEntryCount: Int
    let upsertedEntryCount: Int
    let reconciledEntryCount: Int
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
        switch status {
        case .fetched, .notModified:
            true
        case .failed, .cancelled:
            false
        }
    }

    init(
        feedID: UUID,
        status: FeedRefreshStatus,
        startedAt: Date,
        finishedAt: Date,
        processedEntryCount: Int = 0,
        upsertedEntryCount: Int = 0,
        reconciledEntryCount: Int = 0,
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
        self.reconciledEntryCount = max(0, reconciledEntryCount)
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
        reconciledEntryCount: Int = 0,
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
            reconciledEntryCount: reconciledEntryCount,
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

    static func cancelled(
        feedID: UUID,
        startedAt: Date,
        finishedAt: Date = Date(),
        processedEntryCount: Int = 0,
        upsertedEntryCount: Int = 0,
        rejectedEntryCount: Int = 0,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary = FeedRefreshDiagnosticsSummary(),
        errorDescription: String = "Refresh cancelled"
    ) -> FeedRefreshResult {
        FeedRefreshResult(
            feedID: feedID,
            status: .cancelled,
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
    let cancelledCount: Int
    let totalProcessedEntryCount: Int
    let totalUpsertedEntryCount: Int
    let totalReconciledEntryCount: Int
    let totalRejectedEntryCount: Int
}

struct FeedRefreshBatchError: Sendable, Equatable, Identifiable {
    let feedID: UUID
    let message: String

    var id: UUID {
        feedID
    }
}

struct FeedRefreshBatchResult: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let targetFeedIDs: [UUID]
    let results: [FeedRefreshResult]
    let batchErrorDescription: String?
    let summary: FeedRefreshBatchSummary

    init(
        startedAt: Date,
        finishedAt: Date,
        results: [FeedRefreshResult],
        targetFeedIDs: [UUID]? = nil,
        batchErrorDescription: String? = nil
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.targetFeedIDs = targetFeedIDs ?? results.map(\.feedID)
        self.results = results
        self.batchErrorDescription = batchErrorDescription
        self.summary = Self.makeSummary(
            from: results,
            targetFeedCount: self.targetFeedIDs.count
        )
    }

    var duration: TimeInterval {
        max(0, finishedAt.timeIntervalSince(startedAt))
    }

    var failedResults: [FeedRefreshResult] {
        results.filter { $0.status == .failed }
    }

    var cancelledResults: [FeedRefreshResult] {
        results.filter { $0.status == .cancelled }
    }

    var failedFeedIDs: [UUID] {
        failedResults.map(\.feedID)
    }

    var retryFeedIDs: [UUID] {
        let resultsByFeedID = Dictionary(grouping: results, by: \.feedID)
        return targetFeedIDs.filter { feedID in
            guard let matchingResults = resultsByFeedID[feedID],
                  matchingResults.count == 1,
                  let result = matchingResults.first else {
                return true
            }
            return result.status == .failed || result.status == .cancelled
        }
    }

    var hasUnsuccessfulOutcome: Bool {
        batchErrorDescription != nil
            || hasExactlyOneOutcomePerTarget == false
            || retryFeedIDs.isEmpty == false
    }

    var isCompleteSuccess: Bool {
        hasUnsuccessfulOutcome == false
    }

    var errors: [FeedRefreshBatchError] {
        failedResults.compactMap { result in
            guard let message = result.errorDescription, message.isEmpty == false else {
                return nil
            }

            return FeedRefreshBatchError(
                feedID: result.feedID,
                message: message
            )
        }
    }

    var failureDescriptions: [String] {
        [batchErrorDescription].compactMap { $0 } + errors.map(\.message)
    }

    private var hasExactlyOneOutcomePerTarget: Bool {
        guard results.count == targetFeedIDs.count else { return false }
        return Dictionary(grouping: results, by: \.feedID).mapValues(\.count)
            == Dictionary(grouping: targetFeedIDs, by: { $0 }).mapValues(\.count)
    }

    private static func makeSummary(
        from results: [FeedRefreshResult],
        targetFeedCount: Int
    ) -> FeedRefreshBatchSummary {
        FeedRefreshBatchSummary(
            totalFeedCount: targetFeedCount,
            fetchedCount: results.filter { $0.status == .fetched }.count,
            notModifiedCount: results.filter { $0.status == .notModified }.count,
            failedCount: results.filter { $0.status == .failed }.count,
            cancelledCount: results.filter { $0.status == .cancelled }.count,
            totalProcessedEntryCount: results.reduce(0) { $0 + $1.processedEntryCount },
            totalUpsertedEntryCount: results.reduce(0) { $0 + $1.upsertedEntryCount },
            totalReconciledEntryCount: results.reduce(0) { $0 + $1.reconciledEntryCount },
            totalRejectedEntryCount: results.reduce(0) { $0 + $1.rejectedEntryCount }
        )
    }
}

struct BackgroundFeedRefreshResult: Sendable {
    let trigger: FeedRefreshTrigger
    let batchResult: FeedRefreshBatchResult

    init(
        trigger: FeedRefreshTrigger = .background,
        batchResult: FeedRefreshBatchResult
    ) {
        self.trigger = trigger
        self.batchResult = batchResult
    }

    var summary: FeedRefreshBatchSummary {
        batchResult.summary
    }

    var duration: TimeInterval {
        batchResult.duration
    }

    var errors: [FeedRefreshBatchError] {
        batchResult.errors
    }
}
