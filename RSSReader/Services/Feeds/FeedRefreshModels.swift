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
}

struct FeedRefreshBatchSummary: Sendable, Equatable {
    let totalFeedCount: Int
    let fetchedCount: Int
    let notModifiedCount: Int
    let failedCount: Int
    let processedEntryCount: Int
    let upsertedEntryCount: Int
    let rejectedEntryCount: Int
}

struct FeedRefreshBatchResult: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let results: [FeedRefreshResult]

    var duration: TimeInterval {
        max(0, finishedAt.timeIntervalSince(startedAt))
    }

    var summary: FeedRefreshBatchSummary {
        FeedRefreshBatchSummary(
            totalFeedCount: results.count,
            fetchedCount: results.filter { $0.status == .fetched }.count,
            notModifiedCount: results.filter { $0.status == .notModified }.count,
            failedCount: results.filter { $0.status == .failed }.count,
            processedEntryCount: results.reduce(0) { $0 + $1.processedEntryCount },
            upsertedEntryCount: results.reduce(0) { $0 + $1.upsertedEntryCount },
            rejectedEntryCount: results.reduce(0) { $0 + $1.rejectedEntryCount }
        )
    }

    var failedResults: [FeedRefreshResult] {
        results.filter { $0.status == .failed }
    }

    var failureDescriptions: [String] {
        failedResults.compactMap(\.errorDescription)
    }
}

