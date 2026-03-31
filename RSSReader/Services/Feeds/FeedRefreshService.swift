import Foundation

enum FeedRefreshServiceError: Error {
    case feedNotFound(UUID)
    case refreshPipelineNotImplemented
}

struct FeedRefreshContext: Sendable {
    let metadata: FeedFetchMetadata
    let request: FeedRequest
}

@MainActor
protocol FeedRefreshCoordinating {
    func refresh(feedID: UUID) async -> FeedRefreshResult
    func refreshFeeds(_ feedIDs: [UUID]) async -> FeedRefreshBatchResult
    func refreshAllActiveFeeds() async -> FeedRefreshBatchResult
    func refreshAfterAddingFeed(feedID: UUID) async -> FeedRefreshResult
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

    func refresh(feedID: UUID) async -> FeedRefreshResult {
        let startedAt = Date()

        do {
            _ = try makeRefreshContext(for: feedID)
            return makeNotImplementedResult(feedID: feedID, startedAt: startedAt)
        } catch {
            logger.error("Failed to prepare refresh for feed \(feedID.uuidString): \(error)")
            return makeFailureResult(
                feedID: feedID,
                startedAt: startedAt,
                errorDescription: String(describing: error)
            )
        }
    }

    func refreshFeeds(_ feedIDs: [UUID]) async -> FeedRefreshBatchResult {
        let startedAt = Date()
        let uniqueFeedIDs = uniquePreservingOrder(feedIDs)
        var results: [FeedRefreshResult] = []
        results.reserveCapacity(uniqueFeedIDs.count)

        for feedID in uniqueFeedIDs {
            let result = await refresh(feedID: feedID)
            results.append(result)
        }

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
        FeedRefreshResult(
            feedID: feedID,
            status: .failed,
            startedAt: startedAt,
            finishedAt: Date(),
            errorDescription: errorDescription
        )
    }

    private func makeNotImplementedResult(feedID: UUID, startedAt: Date) -> FeedRefreshResult {
        makeFailureResult(
            feedID: feedID,
            startedAt: startedAt,
            errorDescription: String(describing: FeedRefreshServiceError.refreshPipelineNotImplemented)
        )
    }

    private func uniquePreservingOrder(_ feedIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return feedIDs.filter { feedID in
            seen.insert(feedID).inserted
        }
    }
}
