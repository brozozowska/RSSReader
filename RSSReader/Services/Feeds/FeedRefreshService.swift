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
    func makeRefreshContext(for feedID: UUID) throws -> FeedRefreshContext
}

@MainActor
final class FeedRefreshService: FeedRefreshCoordinating {
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
}
