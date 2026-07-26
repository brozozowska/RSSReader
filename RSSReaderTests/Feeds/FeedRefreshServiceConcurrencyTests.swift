import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Concurrency")
@MainActor
struct FeedRefreshServiceConcurrencyTests {
    @Test
    func concurrentRefreshOfSameFeedSharesInFlightTaskAndAvoidsDuplicateSideEffects() async throws {
        let feedURL = "https://example.com/concurrent-feed.xml"
        let feedOperations = SwiftDataRepositoryOperationCounter()
        let articleOperations = SwiftDataRepositoryOperationCounter()
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .delayedResponse(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8",
                        "ETag": "\"etag-concurrent\""
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Concurrent Feed",
                        channelLink: "https://example.com/concurrent/",
                        language: "en",
                        itemTitle: "Concurrent Article",
                        itemLink: "https://example.com/concurrent/articles/1",
                        itemGUID: "concurrent-article-1",
                        itemDescription: "Readable concurrent summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    ),
                    delayNanoseconds: 200_000_000
                )
            ]
        )
        let harness = try TestHarness.make(
            httpClient: client,
            feedRepositoryOperationRecorder: feedOperations.record,
            articleRepositoryOperationRecorder: articleOperations.record
        )
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        feedOperations.reset()
        articleOperations.reset()

        let firstTask = Task { @MainActor in
            await harness.service.refresh(feedID: feed.id)
        }
        let secondTask = Task { @MainActor in
            await harness.service.refresh(feedID: feed.id)
        }

        let firstResult = await firstTask.value
        let secondResult = await secondTask.value

        #expect(firstResult.status == .fetched)
        #expect(secondResult.status == .fetched)
        #expect(firstResult.upsertedEntryCount == 1)
        #expect(secondResult.upsertedEntryCount == 1)
        #expect(firstResult.finishedAt == secondResult.finishedAt)
        try await assertSingleFetchedExecution(
            harness: harness,
            feedID: feed.id,
            client: client,
            feedOperations: feedOperations,
            articleOperations: articleOperations
        )
    }

    @Test
    func ownerCancellationLeavesSharedRefreshRunningForJoiningCaller() async throws {
        let harness = try makeCancellationHarness(
            feedURL: "https://example.com/owner-cancelled-feed.xml",
            delayNanoseconds: 500_000_000
        )
        let feed = harness.feed
        harness.feedOperations.reset()
        harness.articleOperations.reset()

        let ownerTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        await waitForRequestCount(1, client: harness.testHarness.httpClient)

        let joiningTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        await waitForWaiterCount(2, feedID: feed.id, service: harness.testHarness.service)

        ownerTask.cancel()
        let ownerResult = await ownerTask.value
        let joiningResult = await joiningTask.value

        #expect(ownerResult.status == .cancelled)
        #expect(joiningResult.status == .fetched)
        try await assertSingleFetchedExecution(
            harness: harness.testHarness,
            feedID: feed.id,
            client: harness.testHarness.httpClient,
            feedOperations: harness.feedOperations,
            articleOperations: harness.articleOperations
        )
    }

    @Test
    func joiningCallerCancellationLeavesSharedRefreshRunningForOwner() async throws {
        let harness = try makeCancellationHarness(
            feedURL: "https://example.com/joiner-cancelled-feed.xml",
            delayNanoseconds: 500_000_000
        )
        let feed = harness.feed
        harness.feedOperations.reset()
        harness.articleOperations.reset()

        let ownerTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        await waitForRequestCount(1, client: harness.testHarness.httpClient)

        let joiningTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        await waitForWaiterCount(2, feedID: feed.id, service: harness.testHarness.service)

        joiningTask.cancel()
        let joiningResult = await joiningTask.value
        let ownerResult = await ownerTask.value

        #expect(joiningResult.status == .cancelled)
        #expect(ownerResult.status == .fetched)
        try await assertSingleFetchedExecution(
            harness: harness.testHarness,
            feedID: feed.id,
            client: harness.testHarness.httpClient,
            feedOperations: harness.feedOperations,
            articleOperations: harness.articleOperations
        )
    }

    @Test
    func simultaneousCallerCancellationCancelsSharedRefreshAndCleansRegistry() async throws {
        let harness = try makeCancellationHarness(
            feedURL: "https://example.com/all-callers-cancelled-feed.xml",
            delayNanoseconds: 5_000_000_000
        )
        let feed = harness.feed
        harness.feedOperations.reset()
        harness.articleOperations.reset()

        let ownerTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        await waitForRequestCount(1, client: harness.testHarness.httpClient)

        let joiningTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        await waitForWaiterCount(2, feedID: feed.id, service: harness.testHarness.service)

        ownerTask.cancel()
        joiningTask.cancel()
        let ownerResult = await ownerTask.value
        let joiningResult = await joiningTask.value
        await waitForRegistryCleanup(feedID: feed.id, service: harness.testHarness.service)

        #expect(ownerResult.status == .cancelled)
        #expect(joiningResult.status == .cancelled)
        #expect(await harness.testHarness.httpClient.recordedRequests().count == 1)
        #expect(harness.testHarness.service.inFlightRefreshTasks[feed.id] == nil)
        #expect(try harness.testHarness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
        let logs = try harness.testHarness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil)
        #expect(logs.count == 1)
        #expect(logs.first?.status == "cancelled")
        #expect(harness.feedOperations.saveCount == 1)
        #expect(harness.articleOperations.saveCount == 0)
        #expect(try harness.testHarness.fetchFeed(id: feed.id)?.lastFetchedAt != nil)
    }

    private func makeCancellationHarness(
        feedURL: String,
        delayNanoseconds: UInt64
    ) throws -> (
        testHarness: TestHarness,
        feed: Feed,
        feedOperations: SwiftDataRepositoryOperationCounter,
        articleOperations: SwiftDataRepositoryOperationCounter
    ) {
        let responseBody = makeValidRSSFeedXML(
            channelTitle: "Coalesced Feed",
            channelLink: "https://example.com/coalesced/",
            language: "en",
            itemTitle: "Coalesced Article",
            itemLink: "https://example.com/coalesced/articles/1",
            itemGUID: "coalesced-article-1",
            itemDescription: "Readable coalesced summary",
            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
        )
        let feedOperations = SwiftDataRepositoryOperationCounter()
        let articleOperations = SwiftDataRepositoryOperationCounter()
        let client = ScriptedHTTPClient(
            steps: [
                .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: responseBody,
                    delayNanoseconds: delayNanoseconds
                )
            ]
        )
        let testHarness = try TestHarness.make(
            httpClient: client,
            feedRepositoryOperationRecorder: feedOperations.record,
            articleRepositoryOperationRecorder: articleOperations.record
        )
        let feed = try #require(try testHarness.insertFeeds(urls: [feedURL]).first)
        return (testHarness, feed, feedOperations, articleOperations)
    }

    private func assertSingleFetchedExecution(
        harness: TestHarness,
        feedID: UUID,
        client: ScriptedHTTPClient,
        feedOperations: SwiftDataRepositoryOperationCounter,
        articleOperations: SwiftDataRepositoryOperationCounter
    ) async throws {
        #expect(await client.recordedRequests().count == 1)
        #expect(harness.service.inFlightRefreshTasks[feedID] == nil)
        #expect(try harness.articleRepository.fetchArticles(feedID: feedID).count == 1)
        let logs = try harness.feedFetchLogRepository.fetchLogs(feedID: feedID, limit: nil)
        #expect(logs.count == 1)
        #expect(logs.first?.status == "fetched")
        #expect(feedOperations.saveCount == 2)
        #expect(articleOperations.saveCount == 0)
    }

    private func waitForRequestCount(_ count: Int, client: ScriptedHTTPClient) async {
        while await client.recordedRequests().count < count {
            await Task.yield()
        }
    }

    private func waitForWaiterCount(
        _ count: Int,
        feedID: UUID,
        service: FeedRefreshService
    ) async {
        while service.inFlightRefreshTasks[feedID]?.waiterCount != count {
            await Task.yield()
        }
    }

    private func waitForRegistryCleanup(feedID: UUID, service: FeedRefreshService) async {
        while service.inFlightRefreshTasks[feedID] != nil {
            await Task.yield()
        }
    }
}
