import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Batch")
@MainActor
struct FeedRefreshServiceBatchTests {
    @Test
    func batchRefreshAggregatesPartialSuccessAndIndividualFailures() async throws {
        let feed1URL = "https://example.com/feed-1.xml"
        let feed2URL = "https://example.com/feed-2.xml"
        let feed3URL = "https://example.com/feed-3.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feed1URL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8",
                            "ETag": "\"etag-feed-1\""
                        ],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Feed One",
                            channelLink: "https://example.com/one/",
                            language: "en",
                            itemTitle: "Batch Article One",
                            itemLink: "https://example.com/one/articles/1",
                            itemGUID: "batch-article-1",
                            itemDescription: "Readable summary one",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    ),
                    feed2URL: .response(
                        statusCode: 304,
                        headers: [
                            "ETag": "\"etag-feed-2\"",
                            "Last-Modified": "Wed, 03 Jan 2024 12:00:00 GMT"
                        ],
                        body: ""
                    ),
                    feed3URL: .response(
                        statusCode: 500,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: ""
                    )
                ]
            )
        )

        let feeds = try harness.insertFeeds(urls: [feed1URL, feed2URL, feed3URL])

        let result = await harness.service.refreshFeeds(feeds.map(\.id))

        #expect(result.summary.totalFeedCount == 3)
        #expect(result.summary.fetchedCount == 1)
        #expect(result.summary.notModifiedCount == 1)
        #expect(result.summary.failedCount == 1)
        #expect(result.summary.cancelledCount == 0)
        #expect(result.targetFeedIDs == feeds.map(\.id))
        #expect(result.retryFeedIDs == [feeds[2].id])
        #expect(result.hasUnsuccessfulOutcome)
        #expect(result.isCompleteSuccess == false)
        #expect(result.errors.count == 1)
        #expect(result.failedResults.count == 1)
        #expect(result.results.map(\.status) == [.fetched, .notModified, .failed])
        #expect(result.errors.first?.feedID == feeds[2].id)
        #expect(result.errors.first?.message.contains("invalidStatusCode") == true)

        let feed1Articles = try harness.articleRepository.fetchArticles(feedID: feeds[0].id)
        #expect(feed1Articles.count == 1)

        let fetchedFeed2 = try harness.fetchFeed(id: feeds[1].id)
        let feed2State = try #require(fetchedFeed2)
        #expect(feed2State.lastETag == "\"etag-feed-2\"")

        let fetchedFeed3 = try harness.fetchFeed(id: feeds[2].id)
        let feed3State = try #require(fetchedFeed3)
        #expect(feed3State.lastSyncError?.contains("invalidStatusCode") == true)
    }

    @Test
    func batchRefreshRespectsDefaultConcurrencyLimit() async throws {
        let urls = (1...4).map { "https://example.com/concurrency-\($0).xml" }
        let responses = Dictionary(uniqueKeysWithValues: urls.enumerated().map { index, url in
            (
                url,
                ScriptedHTTPClient.Step.delayedResponse(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Concurrency Feed \(index + 1)",
                        channelLink: "https://example.com/\(index + 1)/",
                        language: "en",
                        itemTitle: "Concurrency Article \(index + 1)",
                        itemLink: "https://example.com/\(index + 1)/articles/1",
                        itemGUID: "concurrency-\(index + 1)",
                        itemDescription: "Readable summary \(index + 1)",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    ),
                    delayNanoseconds: 200_000_000
                )
            )
        })

        let client = ScriptedHTTPClient(responsesByURL: responses)
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)

        let result = await harness.service.refreshFeeds(feeds.map(\.id))

        #expect(result.summary.totalFeedCount == 4)
        #expect(result.summary.fetchedCount == 4)
        #expect(result.summary.failedCount == 0)
        #expect(result.summary.cancelledCount == 0)

        let maxConcurrentExecutions = await client.maxConcurrentExecutions()
        #expect(maxConcurrentExecutions <= 3)

        let requests = await client.recordedRequests()
        #expect(requests.count == 4)
    }

    @Test
    func batchRefreshCancellationReturnsPartialCancelledResults() async throws {
        let urls = (1...4).map { "https://example.com/cancel-\($0).xml" }
        let responseGate = ScriptedHTTPClientResponseGate()
        let expectedInFlightRequestCount = FeedRefreshBatchPolicy.default.maxConcurrentRefreshes
        let responses = Dictionary(uniqueKeysWithValues: urls.enumerated().map { index, url in
            (
                url,
                ScriptedHTTPClient.Step.gatedResponse(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Cancel Feed \(index + 1)",
                        channelLink: "https://example.com/cancel/\(index + 1)/",
                        language: "en",
                        itemTitle: "Cancel Article \(index + 1)",
                        itemLink: "https://example.com/cancel/\(index + 1)/articles/1",
                        itemGUID: "cancel-\(index + 1)",
                        itemDescription: "Readable summary \(index + 1)",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    ),
                    gate: responseGate
                )
            )
        })

        let client = ScriptedHTTPClient(responsesByURL: responses)
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)

        let task = Task { @MainActor in
            await harness.service.refreshFeeds(feeds.map(\.id))
        }

        try await waitUntil("default concurrency requests entered the response gate") {
            await responseGate.enteredCount() == expectedInFlightRequestCount
        }
        #expect(await client.currentInFlightExecutionCount() == expectedInFlightRequestCount)
        #expect(await client.recordedRequests().count == expectedInFlightRequestCount)

        task.cancel()
        await responseGate.release()

        let result = await task.value
        try await waitUntil("cancelled refresh executions cleaned up") {
            let hasActiveExecution = feeds.contains { feed in
                harness.service.inFlightRefreshTasks[feed.id] != nil
            }
            return await client.currentInFlightExecutionCount() == 0 && hasActiveExecution == false
        }

        #expect(result.summary.totalFeedCount == feeds.count)
        #expect(result.summary.fetchedCount == 0)
        #expect(result.summary.cancelledCount == feeds.count)
        #expect(result.summary.failedCount == 0)
        #expect(result.summary.notModifiedCount == 0)
        #expect(result.targetFeedIDs == feeds.map(\.id))
        #expect(result.results.map(\.status) == Array(repeating: .cancelled, count: feeds.count))
        #expect(result.retryFeedIDs == feeds.map(\.id))

        let requests = await client.recordedRequests()
        let requestedURLs = requests.map { $0.url.absoluteString }
        #expect(requests.count == expectedInFlightRequestCount)
        #expect(await client.maxConcurrentExecutions() == expectedInFlightRequestCount)
        #expect(Set(requestedURLs) == Set(urls.prefix(expectedInFlightRequestCount)))
        #expect(requestedURLs.contains(urls[expectedInFlightRequestCount]) == false)
    }

    @Test
    func batchResultTreatsMissingTerminalOutcomeAsRetryable() {
        let completedFeedID = UUID()
        let omittedFeedID = UUID()
        let now = Date()
        let result = FeedRefreshBatchResult(
            startedAt: now,
            finishedAt: now,
            results: [
                .notModified(feedID: completedFeedID, startedAt: now, finishedAt: now)
            ],
            targetFeedIDs: [completedFeedID, omittedFeedID]
        )

        #expect(result.summary.totalFeedCount == 2)
        #expect(result.results.count == 1)
        #expect(result.retryFeedIDs == [omittedFeedID])
        #expect(result.hasUnsuccessfulOutcome)
        #expect(result.isCompleteSuccess == false)
    }

    @Test
    func batchResultRejectsDuplicateOrUnexpectedTerminalOutcomes() {
        let targetFeedID = UUID()
        let unexpectedFeedID = UUID()
        let now = Date()
        let duplicateResult = FeedRefreshBatchResult(
            startedAt: now,
            finishedAt: now,
            results: [
                .notModified(feedID: targetFeedID, startedAt: now, finishedAt: now),
                .notModified(feedID: targetFeedID, startedAt: now, finishedAt: now)
            ],
            targetFeedIDs: [targetFeedID]
        )
        let unexpectedResult = FeedRefreshBatchResult(
            startedAt: now,
            finishedAt: now,
            results: [
                .notModified(feedID: unexpectedFeedID, startedAt: now, finishedAt: now)
            ],
            targetFeedIDs: [targetFeedID]
        )

        #expect(duplicateResult.retryFeedIDs == [targetFeedID])
        #expect(duplicateResult.isCompleteSuccess == false)
        #expect(unexpectedResult.retryFeedIDs == [targetFeedID])
        #expect(unexpectedResult.isCompleteSuccess == false)
    }

    @Test
    func overlappingBatchesShareOneExecutionPerFeedAndReturnCompleteOrderedOutcomes() async throws {
        let urls = (1...3).map { "https://example.com/overlap-\($0).xml" }
        let responseGate = ScriptedHTTPClientResponseGate()
        let client = ScriptedHTTPClient(
            responsesByURL: Dictionary(
                uniqueKeysWithValues: urls.enumerated().map { index, url in
                    (
                        url,
                        .gatedResponse(
                            statusCode: 200,
                            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                            body: makeValidRSSFeedXML(
                                channelTitle: "Overlap Feed \(index + 1)",
                                channelLink: "https://example.com/overlap/\(index + 1)/",
                                language: "en",
                                itemTitle: "Overlap Article \(index + 1)",
                                itemLink: "https://example.com/overlap/\(index + 1)/articles/1",
                                itemGUID: "overlap-\(index + 1)",
                                itemDescription: "Overlap fixture",
                                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                            ),
                            gate: responseGate
                        )
                    )
                }
            )
        )
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)
        let feedIDs = feeds.map(\.id)

        let firstTask = Task { @MainActor in
            await harness.service.refreshFeeds(feedIDs)
        }
        try await waitUntil("first batch started every target") {
            await responseGate.enteredCount() == feedIDs.count
        }

        let secondTask = Task { @MainActor in
            await harness.service.refreshFeeds(feedIDs)
        }
        try await waitUntil("second batch joined every target") {
            feedIDs.allSatisfy { harness.service.inFlightRefreshTasks[$0]?.waiterCount == 2 }
        }
        await responseGate.release()

        let firstResult = await firstTask.value
        let secondResult = await secondTask.value

        #expect(firstResult.targetFeedIDs == feedIDs)
        #expect(secondResult.targetFeedIDs == feedIDs)
        #expect(firstResult.results.map(\.status) == Array(repeating: .fetched, count: feedIDs.count))
        #expect(secondResult.results.map(\.status) == Array(repeating: .fetched, count: feedIDs.count))
        #expect(await client.recordedRequests().count == feedIDs.count)
    }

    @Test
    func allFeedsTargetSnapshotIgnoresConcurrentAddAndKeepsRemovedFeedOutcome() async throws {
        let urls = (1...2).map { "https://example.com/target-snapshot-\($0).xml" }
        let responseGate = ScriptedHTTPClientResponseGate()
        let client = ScriptedHTTPClient(
            responsesByURL: Dictionary(
                uniqueKeysWithValues: urls.enumerated().map { index, url in
                    (
                        url,
                        .gatedResponse(
                            statusCode: 200,
                            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                            body: makeValidRSSFeedXML(
                                channelTitle: "Snapshot Feed \(index + 1)",
                                channelLink: "https://example.com/snapshot/\(index + 1)/",
                                language: "en",
                                itemTitle: "Snapshot Article \(index + 1)",
                                itemLink: "https://example.com/snapshot/\(index + 1)/articles/1",
                                itemGUID: "snapshot-\(index + 1)",
                                itemDescription: "Snapshot fixture",
                                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                            ),
                            gate: responseGate
                        )
                    )
                }
            )
        )
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)
        let originalFeedIDs = feeds.map(\.id)

        let task = Task { @MainActor in
            await harness.service.refreshAllActiveFeeds()
        }
        try await waitUntil("all original targets entered the response gate") {
            await responseGate.enteredCount() == originalFeedIDs.count
        }

        let addedFeed = try harness.feedRepository.insert(
            Feed(url: "https://example.com/target-snapshot-added.xml", title: "Added")
        )
        _ = try harness.feedRepository.delete(feedID: feeds[1].id)
        await responseGate.release()

        let result = await task.value
        let retryResult = await harness.dependencies.appActions.retryFeeds(
            result.retryFeedIDs,
            using: AppState()
        )
        let requestedURLs = await client.recordedRequests().map { $0.url.absoluteString }

        #expect(result.targetFeedIDs == originalFeedIDs)
        #expect(result.results.count == originalFeedIDs.count)
        #expect(result.results[0].status == .fetched)
        #expect(result.results[1].feedID == feeds[1].id)
        #expect(result.results[1].status == .failed)
        #expect(result.retryFeedIDs == [feeds[1].id])
        #expect(retryResult?.targetFeedIDs.isEmpty == true)
        #expect(requestedURLs == urls)
        #expect(requestedURLs.contains(addedFeed.url) == false)
    }

    private func waitUntil(
        _ expectation: String,
        condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            await Task.yield()
        }
        throw BatchWaitError.timedOut(expectation)
    }
}

private enum BatchWaitError: Error {
    case timedOut(String)
}
