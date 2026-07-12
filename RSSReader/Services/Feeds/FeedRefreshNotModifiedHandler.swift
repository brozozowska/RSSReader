import Foundation

extension FeedRefreshService {
    func handleNotModifiedResponse(
        _ response: FeedResponse,
        metadata: FeedFetchMetadata,
        startedAt: Date
    ) async throws -> FeedRefreshResult {
        try Task.checkCancellation()
        let finishedAt = Date()
        let discoveredIconURL = await discoverIconURLIfNeeded(
            feedURL: response.sourceURL,
            currentMetadata: metadata,
            parsedMetadata: nil
        )

        try updateNotModifiedFetchState(
            from: response,
            feedID: metadata.id,
            discoveredIconURL: discoveredIconURL,
            finishedAt: finishedAt
        )
        logger.info("Feed \(metadata.id.uuidString) not modified; metadata updated after conditional fetch")

        return FeedRefreshResult.notModified(
            feedID: metadata.id,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    func updateNotModifiedFetchState(
        from response: FeedResponse,
        feedID: UUID,
        discoveredIconURL: URL? = nil,
        finishedAt: Date
    ) throws {
        let currentMetadata = try feedRepository.fetchMetadata(for: feedID)
        var update = FeedMetadataUpdate(updatedAt: finishedAt)
        update.iconURL = updatedIconURL(
            currentIconURL: currentMetadata?.iconURL,
            discoveredIconURL: discoveredIconURL
        )
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
}
