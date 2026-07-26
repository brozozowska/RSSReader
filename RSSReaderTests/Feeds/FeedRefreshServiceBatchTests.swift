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

        #expect(result.summary.totalFeedCount == expectedInFlightRequestCount)
        #expect(result.summary.fetchedCount == 0)
        #expect(result.summary.cancelledCount == expectedInFlightRequestCount)
        #expect(result.summary.failedCount == 0)
        #expect(result.summary.notModifiedCount == 0)
        #expect(result.results.map(\.status) == Array(repeating: .cancelled, count: expectedInFlightRequestCount))

        let requests = await client.recordedRequests()
        let requestedURLs = requests.map { $0.url.absoluteString }
        #expect(requests.count == expectedInFlightRequestCount)
        #expect(await client.maxConcurrentExecutions() == expectedInFlightRequestCount)
        #expect(Set(requestedURLs) == Set(urls.prefix(expectedInFlightRequestCount)))
        #expect(requestedURLs.contains(urls[expectedInFlightRequestCount]) == false)
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
