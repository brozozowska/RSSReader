import Foundation

enum FeedRefreshServiceError: Error {
    case feedNotFound(UUID)
}

struct FeedRefreshContext: Sendable {
    let metadata: FeedFetchMetadata
    let request: FeedRequest
}

@MainActor
protocol FeedRefreshCoordinating {
    var transactionBoundary: FeedRefreshTransactionBoundary { get }
    func refresh(feedID: UUID) async -> FeedRefreshResult
    func refreshFeeds(_ feedIDs: [UUID]) async -> FeedRefreshBatchResult
    func refreshAllActiveFeeds() async -> FeedRefreshBatchResult
    func refreshAllActiveFeedsForBackground() async -> BackgroundFeedRefreshResult
    func refreshAfterAddingFeed(feedID: UUID) async -> FeedRefreshResult
    func makeRefreshContext(for feedID: UUID) throws -> FeedRefreshContext
}

@MainActor
final class FeedRefreshService: FeedRefreshCoordinating {
    let transactionBoundary: FeedRefreshTransactionBoundary = .singleFeedRefresh
    let notModifiedPolicy: FeedRefreshNotModifiedPolicy = .default
    let diagnosticsPolicy: FeedRefreshDiagnosticsPolicy = .default
    let reconciliationPolicy: FeedRefreshReconciliationPolicy = .markMissingArticlesAsArchived
    let batchPolicy: FeedRefreshBatchPolicy = .default
    let inFlightPolicy: FeedRefreshInFlightPolicy = .shareExistingTaskResult
    let logger: Logging
    let feedFetcher: any FeedFetching
    let feedParsingWorker: any FeedParsingWorking
    let feedRepository: any FeedRepository
    let articleRepository: any ArticleRepository
    let feedIconDiscoveryService: (any FeedIconDiscovering)?
    let feedFetchLogRepository: (any FeedFetchLogRepository)?
    var inFlightRefreshTasks: [UUID: Task<FeedRefreshResult, Never>] = [:]

    init(
        logger: Logging,
        feedFetcher: any FeedFetching,
        feedParsingWorker: any FeedParsingWorking = FeedParsingWorker(),
        feedRepository: any FeedRepository,
        articleRepository: any ArticleRepository,
        feedIconDiscoveryService: (any FeedIconDiscovering)? = nil,
        feedFetchLogRepository: (any FeedFetchLogRepository)? = nil
    ) {
        self.logger = logger
        self.feedFetcher = feedFetcher
        self.feedParsingWorker = feedParsingWorker
        self.feedRepository = feedRepository
        self.articleRepository = articleRepository
        self.feedIconDiscoveryService = feedIconDiscoveryService
        self.feedFetchLogRepository = feedFetchLogRepository
    }
}
