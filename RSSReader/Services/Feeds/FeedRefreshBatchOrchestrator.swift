import Foundation

extension FeedRefreshService {
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

    func refreshAfterAddingFeed(feedID: UUID) async -> FeedRefreshResult {
        await refresh(feedID: feedID)
    }

    func fetchActiveFeedIDs() throws -> [UUID] {
        try feedRepository.fetchActiveFeeds().map(\.id)
    }

    func executeBatchRefresh(feedIDs: [UUID]) async -> [FeedRefreshResult] {
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
                } else if result.status == .cancelled {
                    logger.info("Batch refresh cancelled for feed \(feedID.uuidString)")
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

    func uniquePreservingOrder(_ feedIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return feedIDs.filter { feedID in
            seen.insert(feedID).inserted
        }
    }
}
