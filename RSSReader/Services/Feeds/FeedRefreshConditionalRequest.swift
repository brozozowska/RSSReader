import Foundation

extension FeedRefreshService {
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

    func makeConditionalFeedRequest(for metadata: FeedFetchMetadata) throws -> FeedRequest {
        try FeedRequest(
            feedID: metadata.id,
            urlString: metadata.url,
            ifNoneMatch: metadata.lastETag,
            ifModifiedSince: metadata.lastModifiedHeader
        )
    }
}
