import Foundation

extension FeedRefreshService {
    func handleNotModifiedResponse(
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

    func updateNotModifiedFetchState(
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
}
