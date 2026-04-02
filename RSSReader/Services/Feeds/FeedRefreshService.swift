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
    let reconciliationPolicy: FeedRefreshReconciliationPolicy = .markMissingArticlesAsDeletedAtSource
    let batchPolicy: FeedRefreshBatchPolicy = .default
    let inFlightPolicy: FeedRefreshInFlightPolicy = .shareExistingTaskResult
    private let logger: Logging
    private let feedFetcher: any FeedFetching
    private let feedRepository: any FeedRepository
    private let articleRepository: any ArticleRepository
    private let feedFetchLogRepository: (any FeedFetchLogRepository)?
    private var inFlightRefreshTasks: [UUID: Task<FeedRefreshResult, Never>] = [:]

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

        let request = try makeConditionalFeedRequest(for: metadata)
        logger.debug("Prepared refresh context with conditional request headers for feed \(feedID.uuidString)")

        return FeedRefreshContext(
            metadata: metadata,
            request: request
        )
    }

    private func makeConditionalFeedRequest(for metadata: FeedFetchMetadata) throws -> FeedRequest {
        try FeedRequest(
            feedID: metadata.id,
            urlString: metadata.url,
            ifNoneMatch: metadata.lastETag,
            ifModifiedSince: metadata.lastModifiedHeader
        )
    }

    func refresh(feedID: UUID) async -> FeedRefreshResult {
        switch inFlightPolicy {
        case .shareExistingTaskResult:
            if let inFlightTask = inFlightRefreshTasks[feedID] {
                logger.info("Joining in-flight refresh for feed \(feedID.uuidString)")
                return await inFlightTask.value
            }

            let task = Task<FeedRefreshResult, Never> { [weak self, feedID] in
                guard let self else {
                    return FeedRefreshResult.failed(
                        feedID: feedID,
                        startedAt: Date(),
                        errorDescription: "FeedRefreshService deallocated"
                    )
                }

                let result = await self.performRefresh(feedID: feedID)
                _ = await MainActor.run {
                    self.inFlightRefreshTasks.removeValue(forKey: feedID)
                }
                return result
            }

            inFlightRefreshTasks[feedID] = task
            return await task.value
        }
    }

    private func performRefresh(feedID: UUID) async -> FeedRefreshResult {
        let startedAt = Date()

        do {
            let context = try makeRefreshContext(for: feedID)
            try markRefreshAttemptStarted(for: context.metadata.id, startedAt: startedAt)
            let fetchResult = try await feedFetcher.fetch(context.request)
            try Task.checkCancellation()

            switch fetchResult {
            case .notModified(let response):
                let result = try handleNotModifiedResponse(
                    response,
                    metadata: context.metadata,
                    startedAt: startedAt
                )
                try persistRefreshLog(
                    feedID: context.metadata.id,
                    status: result.status,
                    httpCode: response.statusCode,
                    diagnosticsSummary: result.diagnosticsSummary,
                    errorDescription: result.errorDescription,
                    finishedAt: result.finishedAt,
                    baseMessage: "Feed not modified"
                )
                return result
            case .fetched(let response):
                let result = try handleFetchedResponse(
                    response,
                    metadata: context.metadata,
                    startedAt: startedAt
                )
                try persistRefreshLog(
                    feedID: context.metadata.id,
                    status: result.status,
                    httpCode: response.statusCode,
                    diagnosticsSummary: result.diagnosticsSummary,
                    errorDescription: result.errorDescription,
                    finishedAt: result.finishedAt
                )
                return result
            }
        } catch is CancellationError {
            logger.info("Cancelled refresh for feed \(feedID.uuidString)")
            return makeCancelledResult(feedID: feedID, startedAt: startedAt)
        } catch {
            let finishedAt = Date()
            let errorDescription = String(describing: error)
            feedRepository.rollback()
            try? markRefreshFailed(feedID: feedID, finishedAt: finishedAt, errorDescription: errorDescription)
            try? persistRefreshLog(
                feedID: feedID,
                status: .failed,
                httpCode: httpCode(from: error),
                diagnosticsSummary: FeedRefreshDiagnosticsSummary(),
                errorDescription: errorDescription,
                finishedAt: finishedAt
            )
            logger.error("Failed to refresh feed \(feedID.uuidString): \(error)")
            return makeFailureResult(
                feedID: feedID,
                startedAt: startedAt,
                errorDescription: errorDescription
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
            let activeFeedIDs = try fetchActiveFeedIDs()
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

    func refreshAllActiveFeedsForBackground() async -> BackgroundFeedRefreshResult {
        let batchResult = await refreshAllActiveFeeds()
        return BackgroundFeedRefreshResult(batchResult: batchResult)
    }

    private func fetchActiveFeedIDs() throws -> [UUID] {
        try feedRepository.fetchActiveFeeds().map(\.id)
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

    private func makeCancelledResult(feedID: UUID, startedAt: Date) -> FeedRefreshResult {
        FeedRefreshResult.failed(
            feedID: feedID,
            startedAt: startedAt,
            errorDescription: "Refresh cancelled"
        )
    }

    private func handleNotModifiedResponse(
        _ response: FeedResponse,
        metadata: FeedFetchMetadata,
        startedAt: Date
    ) throws -> FeedRefreshResult {
        try Task.checkCancellation()
        let finishedAt = Date()

        try updateNotModifiedFetchState(from: response, feedID: metadata.id, finishedAt: finishedAt)
        logger.info("Feed \(metadata.id.uuidString) not modified; metadata updated after conditional fetch")

        return FeedRefreshResult.notModified(
            feedID: metadata.id,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private func markRefreshAttemptStarted(for feedID: UUID, startedAt: Date) throws {
        var update = FeedMetadataUpdate(updatedAt: startedAt)
        update.lastFetchedAt = startedAt
        _ = try feedRepository.updateMetadata(for: feedID, with: update)
    }

    private func markRefreshSucceededWithPayload(
        for feedID: UUID,
        finishedAt: Date,
        saveAfterOperation: Bool = true
    ) throws {
        var update = FeedMetadataUpdate(updatedAt: finishedAt)
        update.lastSuccessfulFetchAt = finishedAt
        update.clearLastSyncError = true
        _ = try feedRepository.updateMetadata(
            for: feedID,
            with: update,
            saveAfterOperation: saveAfterOperation
        )
    }

    private func markRefreshFailed(
        feedID: UUID,
        finishedAt: Date,
        errorDescription: String
    ) throws {
        var update = FeedMetadataUpdate(updatedAt: finishedAt)
        update.lastSyncError = errorDescription
        _ = try feedRepository.updateMetadata(for: feedID, with: update)
    }

    private func handleFetchedResponse(
        _ response: FeedResponse,
        metadata: FeedFetchMetadata,
        startedAt: Date
    ) throws -> FeedRefreshResult {
        let pipelineResult = try FeedParserService.parsePipelineResult(response)
        try Task.checkCancellation()
        let diagnostics = pipelineResult.diagnostics
        let diagnosticsSummary = diagnosticsSummary(for: diagnostics)
        let fetchedAt = Date()

        logDiagnosticsIfNeeded(diagnostics, feedID: metadata.id)
        try updateCacheValidators(
            from: response,
            feedID: metadata.id,
            updatedAt: fetchedAt,
            saveAfterOperation: false
        )
        try updateFeedContentMetadata(
            for: metadata.id,
            parsedFeed: pipelineResult.feed,
            updatedAt: fetchedAt,
            saveAfterOperation: false
        )

        guard let feed = try feedRepository.fetchFeed(id: metadata.id) else {
            throw FeedRefreshServiceError.feedNotFound(metadata.id)
        }

        let reconciledCount = try reconcileArticles(
            for: metadata.id,
            entries: pipelineResult.feed.entries,
            fetchedAt: fetchedAt,
            saveAfterOperation: false
        )
        let upsertedArticles = try articleRepository.upsert(
            pipelineResult.feed.entries,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: false
        )
        let processedEntryCount = pipelineResult.feed.entries.count + diagnostics.rejectedEntries.count

        if diagnosticsAreSoftFailure(diagnostics) {
            logger.info("Feed \(metadata.id.uuidString) fetched with soft-failure diagnostics")
        }
        if reconciledCount > 0 {
            logger.info("Feed \(metadata.id.uuidString) reconciliation affected \(reconciledCount) articles")
        }

        let finishedAt = Date()
        try markRefreshSucceededWithPayload(
            for: metadata.id,
            finishedAt: finishedAt,
            saveAfterOperation: false
        )
        try feedRepository.save()

        return FeedRefreshResult.fetched(
            feedID: metadata.id,
            startedAt: startedAt,
            finishedAt: finishedAt,
            processedEntryCount: processedEntryCount,
            upsertedEntryCount: upsertedArticles.count,
            rejectedEntryCount: diagnostics.rejectedEntries.count,
            diagnosticsSummary: diagnosticsSummary
        )
    }

    private func updateNotModifiedFetchState(
        from response: FeedResponse,
        feedID: UUID,
        finishedAt: Date
    ) throws {
        var update = FeedMetadataUpdate(updatedAt: finishedAt)
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

        _ = try feedRepository.updateMetadata(for: feedID, with: update)
    }

    private func updateCacheValidators(
        from response: FeedResponse,
        feedID: UUID,
        updatedAt: Date,
        saveAfterOperation: Bool = true
    ) throws {
        var update = FeedMetadataUpdate(updatedAt: updatedAt)
        update.lastETag = response.eTag
        update.lastModifiedHeader = response.lastModified
        _ = try feedRepository.updateMetadata(
            for: feedID,
            with: update,
            saveAfterOperation: saveAfterOperation
        )
    }

    private func persistRefreshLog(
        feedID: UUID,
        status: FeedRefreshStatus,
        httpCode: Int?,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary,
        errorDescription: String?,
        finishedAt: Date,
        baseMessage: String? = nil
    ) throws {
        guard let feedFetchLogRepository else { return }

        let logEntry = FeedFetchLogEntry(
            feedID: feedID,
            status: normalizedLogStatus(for: status),
            httpCode: httpCode,
            message: logMessage(
                baseMessage: baseMessage,
                diagnosticsSummary: diagnosticsSummary,
                errorDescription: errorDescription
            ),
            createdAt: finishedAt
        )

        try feedFetchLogRepository.insert(logEntry)
    }

    private func normalizedLogStatus(for status: FeedRefreshStatus) -> String {
        switch status {
        case .fetched:
            "fetched"
        case .notModified:
            "not_modified"
        case .failed:
            "failed"
        }
    }

    private func logMessage(
        baseMessage: String?,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary,
        errorDescription: String?
    ) -> String? {
        var parts: [String] = []

        if let baseMessage, baseMessage.isEmpty == false {
            parts.append(baseMessage)
        }

        parts.append(
            "diagnostics(parser_anomalies=\(diagnosticsSummary.parserAnomalyCount), rejected_entries=\(diagnosticsSummary.rejectedEntryCount))"
        )

        if let errorDescription, errorDescription.isEmpty == false {
            parts.append("error=\(errorDescription)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private func httpCode(from error: Error) -> Int? {
        guard case .invalidStatusCode(let statusCode) = error as? FeedFetchError else {
            return nil
        }
        return statusCode
    }

    private func updateFeedContentMetadata(
        for feedID: UUID,
        parsedFeed: ParsedFeedDTO,
        updatedAt: Date,
        saveAfterOperation: Bool = true
    ) throws {
        let metadata = parsedFeed.metadata
        let update = FeedMetadataUpdate(
            siteURL: metadata.siteURL,
            title: metadata.title,
            subtitle: metadata.subtitle,
            iconURL: metadata.iconURL,
            language: metadata.language,
            kind: parsedFeed.kind,
            updatedAt: updatedAt
        )

        _ = try feedRepository.updateMetadata(
            for: feedID,
            with: update,
            saveAfterOperation: saveAfterOperation
        )
        logger.info("Feed \(feedID.uuidString) content metadata updated from parsed payload")
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
        fetchedAt: Date,
        saveAfterOperation: Bool = true
    ) throws -> Int {
        switch reconciliationPolicy {
        case .markMissingArticlesAsDeletedAtSource:
            let incomingExternalIDs = Set(entries.compactMap(\.externalID))
            let reconciledCount = try articleRepository.reconcileArticles(
                feedID: feedID,
                keepingExternalIDs: incomingExternalIDs,
                fetchedAt: fetchedAt,
                saveAfterOperation: saveAfterOperation
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
        guard feedIDs.isEmpty == false else { return [] }

        let concurrencyLimit = max(1, batchPolicy.maxConcurrentRefreshes)
        var resultsByIndex: [Int: FeedRefreshResult] = [:]
        resultsByIndex.reserveCapacity(feedIDs.count)
        var nextIndexToSchedule = 0
        var batchWasCancelled = false

        await withTaskGroup(of: (Int, UUID, FeedRefreshResult).self) { group in
            let initialTaskCount = min(concurrencyLimit, feedIDs.count)
            for _ in 0..<initialTaskCount {
                let index = nextIndexToSchedule
                let feedID = feedIDs[index]
                nextIndexToSchedule += 1
                group.addTask { [weak self] in
                    guard let self else {
                        let failedResult = await MainActor.run {
                            FeedRefreshResult.failed(
                                feedID: feedID,
                                startedAt: Date(),
                                errorDescription: "FeedRefreshService deallocated"
                            )
                        }
                        return (
                            index,
                            feedID,
                            failedResult
                        )
                    }

                    let result = await self.refresh(feedID: feedID)
                    return (index, feedID, result)
                }
            }

            while let (index, feedID, result) = await group.next() {
                resultsByIndex[index] = result

                if result.status == .failed {
                    logger.error("Batch refresh failed for feed \(feedID.uuidString)")
                }

                switch batchPolicy.errorPolicy {
                case .continueOnError:
                    break
                }

                if Task.isCancelled {
                    batchWasCancelled = true
                    group.cancelAll()
                    continue
                }

                if nextIndexToSchedule < feedIDs.count {
                    let nextIndex = nextIndexToSchedule
                    let nextFeedID = feedIDs[nextIndex]
                    nextIndexToSchedule += 1
                    group.addTask { [weak self] in
                        guard let self else {
                            let failedResult = await MainActor.run {
                                FeedRefreshResult.failed(
                                    feedID: nextFeedID,
                                    startedAt: Date(),
                                    errorDescription: "FeedRefreshService deallocated"
                                )
                            }
                            return (
                                nextIndex,
                                nextFeedID,
                                failedResult
                            )
                        }

                        let result = await self.refresh(feedID: nextFeedID)
                        return (nextIndex, nextFeedID, result)
                    }
                }
            }
        }

        let orderedResults = feedIDs.indices.compactMap { resultsByIndex[$0] }

        if batchWasCancelled {
            logger.info("Batch refresh cancelled after completing \(orderedResults.count) feed refresh tasks")
        }

        return orderedResults
    }

    private func uniquePreservingOrder(_ feedIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return feedIDs.filter { feedID in
            seen.insert(feedID).inserted
        }
    }
}
