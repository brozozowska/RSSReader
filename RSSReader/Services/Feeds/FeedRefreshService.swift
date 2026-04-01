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
    func refreshAfterAddingFeed(feedID: UUID) async -> FeedRefreshResult
    func makeRefreshContext(for feedID: UUID) throws -> FeedRefreshContext
}

@MainActor
final class FeedRefreshService: FeedRefreshCoordinating {
    let transactionBoundary: FeedRefreshTransactionBoundary = .singleFeedRefresh
    let notModifiedPolicy: FeedRefreshNotModifiedPolicy = .default
    let diagnosticsPolicy: FeedRefreshDiagnosticsPolicy = .default
    let reconciliationPolicy: FeedRefreshReconciliationPolicy = .markMissingArticlesAsDeletedAtSource
    let batchPolicy: FeedRefreshBatchPolicy = .default
    private let logger: Logging
    private let feedFetcher: any FeedFetching
    private let feedRepository: any FeedRepository
    private let articleRepository: any ArticleRepository
    private let feedFetchLogRepository: (any FeedFetchLogRepository)?

    init(
        logger: Logging,
        feedFetcher: any FeedFetching,
        feedRepository: any FeedRepository,
        articleRepository: any ArticleRepository,
        feedFetchLogRepository: (any FeedFetchLogRepository)? = nil
    ) {
        self.logger = logger
        self.feedFetcher = feedFetcher
        self.feedRepository = feedRepository
        self.articleRepository = articleRepository
        self.feedFetchLogRepository = feedFetchLogRepository
    }

    func makeRefreshContext(for feedID: UUID) throws -> FeedRefreshContext {
        guard let metadata = try feedRepository.fetchMetadata(for: feedID) else {
            throw FeedRefreshServiceError.feedNotFound(feedID)
        }

        let request = try makeRequest(for: metadata)
        logger.debug("Prepared refresh context for feed \(feedID.uuidString)")

        return FeedRefreshContext(
            metadata: metadata,
            request: request
        )
    }

    private func makeRequest(for metadata: FeedFetchMetadata) throws -> FeedRequest {
        try FeedRequest(
            feedID: metadata.id,
            urlString: metadata.url,
            ifNoneMatch: metadata.lastETag,
            ifModifiedSince: metadata.lastModifiedHeader
        )
    }

    func refresh(feedID: UUID) async -> FeedRefreshResult {
        let startedAt = Date()

        do {
            let context = try makeRefreshContext(for: feedID)
            let fetchResult = try await feedFetcher.fetch(context.request)

            switch fetchResult {
            case .notModified(let response):
                return try handleNotModifiedResponse(
                    response,
                    metadata: context.metadata,
                    startedAt: startedAt
                )
            case .fetched(let response):
                return try handleFetchedResponse(
                    response,
                    metadata: context.metadata,
                    startedAt: startedAt
                )
            }
        } catch {
            logger.error("Failed to refresh feed \(feedID.uuidString): \(error)")
            return makeFailureResult(
                feedID: feedID,
                startedAt: startedAt,
                errorDescription: String(describing: error)
            )
        }
    }

    func refreshFeeds(_ feedIDs: [UUID]) async -> FeedRefreshBatchResult {
        let startedAt = Date()
        let batchFeedIDs = batchPolicy.deduplicatesFeedIDs
            ? uniquePreservingOrder(feedIDs)
            : feedIDs
        let results = await executeBatchRefresh(feedIDs: batchFeedIDs)

        return FeedRefreshBatchResult(
            startedAt: startedAt,
            finishedAt: Date(),
            results: results
        )
    }

    func refreshAllActiveFeeds() async -> FeedRefreshBatchResult {
        let startedAt = Date()

        do {
            let activeFeedIDs = try feedRepository.fetchActiveFeeds().map(\.id)
            return await refreshFeeds(activeFeedIDs)
        } catch {
            logger.error("Failed to load active feeds for refresh: \(error)")
            return FeedRefreshBatchResult(
                startedAt: startedAt,
                finishedAt: Date(),
                results: []
            )
        }
    }

    func refreshAfterAddingFeed(feedID: UUID) async -> FeedRefreshResult {
        await refresh(feedID: feedID)
    }

    private func makeFailureResult(
        feedID: UUID,
        startedAt: Date,
        errorDescription: String
    ) -> FeedRefreshResult {
        FeedRefreshResult.failed(
            feedID: feedID,
            startedAt: startedAt,
            errorDescription: errorDescription
        )
    }

    private func handleNotModifiedResponse(
        _ response: FeedResponse,
        metadata: FeedFetchMetadata,
        startedAt: Date
    ) throws -> FeedRefreshResult {
        let finishedAt = Date()

        var update = FeedMetadataUpdate(updatedAt: finishedAt)
        if notModifiedPolicy.updatesLastFetchedAt {
            update.lastFetchedAt = finishedAt
        }
        if notModifiedPolicy.updatesCacheValidatorsFromResponse {
            update.lastETag = response.eTag
            update.lastModifiedHeader = response.lastModified
        }
        if notModifiedPolicy.clearsLastSyncError {
            update.clearLastSyncError = true
        }
        if notModifiedPolicy.updatesLastSuccessfulFetchAt {
            update.lastSuccessfulFetchAt = finishedAt
        }

        _ = try feedRepository.updateMetadata(for: metadata.id, with: update)
        logger.info("Feed \(metadata.id.uuidString) not modified; metadata updated after conditional fetch")

        return FeedRefreshResult.notModified(
            feedID: metadata.id,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private func handleFetchedResponse(
        _ response: FeedResponse,
        metadata: FeedFetchMetadata,
        startedAt: Date
    ) throws -> FeedRefreshResult {
        let pipelineResult = try FeedParserService.parsePipelineResult(response)
        let diagnostics = pipelineResult.diagnostics
        let diagnosticsSummary = diagnosticsSummary(for: diagnostics)
        let fetchedAt = Date()

        logDiagnosticsIfNeeded(diagnostics, feedID: metadata.id)

        guard let feed = try feedRepository.fetchFeed(id: metadata.id) else {
            throw FeedRefreshServiceError.feedNotFound(metadata.id)
        }

        let reconciledCount = try reconcileArticles(
            for: metadata.id,
            entries: pipelineResult.feed.entries,
            fetchedAt: fetchedAt
        )
        let upsertedArticles = try articleRepository.upsert(
            pipelineResult.feed.entries,
            into: feed,
            fetchedAt: fetchedAt
        )
        let processedEntryCount = pipelineResult.feed.entries.count + diagnostics.rejectedEntries.count

        if diagnosticsAreSoftFailure(diagnostics) {
            logger.info("Feed \(metadata.id.uuidString) fetched with soft-failure diagnostics")
        }
        if reconciledCount > 0 {
            logger.info("Feed \(metadata.id.uuidString) reconciliation affected \(reconciledCount) articles")
        }

        return FeedRefreshResult.fetched(
            feedID: metadata.id,
            startedAt: startedAt,
            finishedAt: Date(),
            processedEntryCount: processedEntryCount,
            upsertedEntryCount: upsertedArticles.count,
            rejectedEntryCount: diagnostics.rejectedEntries.count,
            diagnosticsSummary: diagnosticsSummary
        )
    }

    private func diagnosticsSummary(for diagnostics: FeedParsePipelineDiagnostics) -> FeedRefreshDiagnosticsSummary {
        diagnosticsPolicy.makeSummary(from: diagnostics)
    }

    private func diagnosticsAreSoftFailure(_ diagnostics: FeedParsePipelineDiagnostics) -> Bool {
        diagnosticsPolicy.treatsDiagnosticsAsSoftFailure(diagnostics)
    }

    private func logDiagnosticsIfNeeded(
        _ diagnostics: FeedParsePipelineDiagnostics,
        feedID: UUID
    ) {
        guard diagnostics.hasIssues else { return }

        if diagnosticsPolicy.logsParserAnomalies, diagnostics.parserAnomalies.isEmpty == false {
            let summary = "Feed \(feedID.uuidString) parser anomalies: \(diagnostics.parserAnomalies.count)"
            logger.info(summary)
            for anomaly in diagnostics.parserAnomalies {
                logger.info("Feed \(feedID.uuidString) anomaly [\(String(describing: anomaly.kind))]: \(anomaly.message)")
            }
        }

        if diagnosticsPolicy.logsRejectedEntries, diagnostics.rejectedEntries.isEmpty == false {
            logger.info("Feed \(feedID.uuidString) rejected entries: \(diagnostics.rejectedEntries.count)")
            for rejectedEntry in diagnostics.rejectedEntries {
                let reasons = rejectedEntry.reasons.map(\.rawValue).joined(separator: ", ")
                logger.info("Feed \(feedID.uuidString) rejected entry reasons: \(reasons)")
            }
        }

        if diagnosticsAreSoftFailure(diagnostics) {
            logger.info("Feed \(feedID.uuidString) refresh diagnostics treated as soft failure")
        }
    }

    private func reconcileArticles(
        for feedID: UUID,
        entries: [ParsedFeedEntryDTO],
        fetchedAt: Date
    ) throws -> Int {
        switch reconciliationPolicy {
        case .markMissingArticlesAsDeletedAtSource:
            let incomingExternalIDs = Set(entries.compactMap(\.externalID))
            let reconciledCount = try articleRepository.reconcileArticles(
                feedID: feedID,
                keepingExternalIDs: incomingExternalIDs,
                fetchedAt: fetchedAt
            )

            if reconciledCount > 0 {
                logger.info(
                    "Feed \(feedID.uuidString) reconciliation marked \(reconciledCount) articles as changed deleted-at-source state"
                )
            }

            return reconciledCount
        }
    }

    private func executeBatchRefresh(feedIDs: [UUID]) async -> [FeedRefreshResult] {
        var results: [FeedRefreshResult] = []
        results.reserveCapacity(feedIDs.count)

        for feedID in feedIDs {
            let result = await refresh(feedID: feedID)
            results.append(result)

            if result.status == .failed {
                logger.error("Batch refresh failed for feed \(feedID.uuidString)")
            }

            switch batchPolicy.errorPolicy {
            case .continueOnError:
                continue
            }
        }

        return results
    }

    private func uniquePreservingOrder(_ feedIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return feedIDs.filter { feedID in
            seen.insert(feedID).inserted
        }
    }
}
