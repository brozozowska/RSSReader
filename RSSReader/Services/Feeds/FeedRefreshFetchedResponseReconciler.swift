import Foundation

extension FeedRefreshService {
    func handleFetchedResponse(
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

        _ = try articleRepository.refreshFeedProjection(for: feed, saveAfterOperation: false)

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

    func updateCacheValidators(
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

    func updateFeedContentMetadata(
        for feedID: UUID,
        parsedFeed: ParsedFeedDTO,
        updatedAt: Date,
        saveAfterOperation: Bool = true
    ) throws {
        let metadata = parsedFeed.metadata
        let currentMetadata = try feedRepository.fetchMetadata(for: feedID)
        let update = FeedMetadataUpdate(
            siteURL: metadata.siteURL,
            title: metadata.title,
            subtitle: metadata.subtitle,
            iconURL: currentMetadata?.iconURL == nil ? metadata.iconURL : nil,
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

    func reconcileArticles(
        for feedID: UUID,
        entries: [ParsedFeedEntryDTO],
        fetchedAt: Date,
        saveAfterOperation: Bool = true
    ) throws -> Int {
        switch reconciliationPolicy {
        case .markMissingArticlesAsArchived:
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
}
