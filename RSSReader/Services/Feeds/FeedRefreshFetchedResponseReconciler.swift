import Foundation

extension FeedRefreshService {
    func handleFetchedResponse(
        _ response: FeedResponse,
        metadata: FeedFetchMetadata,
        startedAt: Date
    ) async throws -> FeedRefreshResult {
        let pipelineResult = try await feedParsingWorker.parse(response)
        try Task.checkCancellation()
        let diagnostics = pipelineResult.diagnostics
        let diagnosticsSummary = diagnosticsSummary(for: diagnostics)
        let fetchedAt = Date()
        let currentMetadata = try feedRepository.fetchMetadata(for: metadata.id)
        try Task.checkCancellation()
        let discoveredIconURL = try await discoverIconURLIfNeeded(
            feedURL: response.sourceURL,
            currentMetadata: currentMetadata,
            parsedMetadata: pipelineResult.feed.metadata
        )
        try Task.checkCancellation()

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
            discoveredIconURL: discoveredIconURL,
            updatedAt: fetchedAt,
            saveAfterOperation: false
        )

        guard let feed = try feedRepository.fetchFeed(id: metadata.id) else {
            throw FeedRefreshServiceError.feedNotFound(metadata.id)
        }
        try Task.checkCancellation()

        let articleReconciliationResult: ArticleFeedSnapshotReconciliationResult
        switch reconciliationPolicy {
        case .markMissingArticlesAsArchived:
            articleReconciliationResult = try articleRepository.reconcileFeedSnapshot(
                pipelineResult.feed.entries,
                into: feed,
                fetchedAt: fetchedAt,
                saveAfterOperation: false
            )
        }
        try Task.checkCancellation()
        let processedEntryCount = pipelineResult.feed.entries.count + diagnostics.rejectedEntries.count

        if diagnosticsAreSoftFailure(diagnostics) {
            logger.info("Feed \(metadata.id.uuidString) fetched with soft-failure diagnostics")
        }
        if articleReconciliationResult.reconciledArticleCount > 0 {
            logger.info(
                "Feed \(metadata.id.uuidString) reconciliation affected "
                    + "\(articleReconciliationResult.reconciledArticleCount) articles"
            )
        }

        let finishedAt = Date()
        try markRefreshSucceededWithPayload(
            for: metadata.id,
            finishedAt: finishedAt,
            saveAfterOperation: false
        )
        try Task.checkCancellation()
        try feedRepository.save()

        return FeedRefreshResult.fetched(
            feedID: metadata.id,
            startedAt: startedAt,
            finishedAt: finishedAt,
            processedEntryCount: processedEntryCount,
            upsertedEntryCount: articleReconciliationResult.upsertedArticleCount,
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
        discoveredIconURL: URL? = nil,
        updatedAt: Date,
        saveAfterOperation: Bool = true
    ) throws {
        let metadata = parsedFeed.metadata
        let currentMetadata = try feedRepository.fetchMetadata(for: feedID)
        let update = FeedMetadataUpdate(
            siteURL: metadata.siteURL,
            title: metadata.title,
            subtitle: metadata.subtitle,
            iconURL: updatedIconURL(
                currentIconURL: currentMetadata?.iconURL,
                discoveredIconURL: discoveredIconURL
            ),
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

    func discoverIconURLIfNeeded(
        feedURL: URL,
        currentMetadata: FeedFetchMetadata?,
        parsedMetadata: ParsedFeedMetadataDTO?
    ) async throws -> URL? {
        try Task.checkCancellation()
        guard let feedIconDiscoveryService else {
            return nil
        }

        let siteURL = (parsedMetadata?.siteURL ?? currentMetadata?.siteURL).flatMap(URL.init(string:))
        let metadataIconURLString = currentMetadata?.iconURL ?? parsedMetadata?.iconURL
        let metadataIconURL = metadataIconURLString.flatMap { iconURL in
            URL(string: iconURL, relativeTo: siteURL ?? feedURL)?.absoluteURL
        }

        return try await feedIconDiscoveryService.discoverIconURL(
            feedURL: feedURL,
            siteURL: siteURL,
            metadataIconURL: metadataIconURL
        )
    }

    func updatedIconURL(
        currentIconURL: String?,
        discoveredIconURL: URL?
    ) -> String? {
        guard let discoveredIconURLString = discoveredIconURL?.absoluteString else {
            return nil
        }

        guard currentIconURL != discoveredIconURLString else {
            return nil
        }

        return discoveredIconURLString
    }

}
