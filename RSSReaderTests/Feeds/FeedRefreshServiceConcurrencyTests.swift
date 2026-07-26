import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Concurrency")
@MainActor
struct FeedRefreshServiceConcurrencyTests {
    @Test
    func concurrentRefreshOfSameFeedSharesInFlightTaskAndAvoidsDuplicateSideEffects() async throws {
        let feedURL = "https://example.com/concurrent-feed.xml"
        let responseGate = ScriptedHTTPClientResponseGate()
        let feedOperations = SwiftDataRepositoryOperationCounter()
        let articleOperations = SwiftDataRepositoryOperationCounter()
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .gatedResponse(
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
                    gate: responseGate
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
        try await waitForGateEntry(responseGate)
        let secondTask = Task { @MainActor in
            await harness.service.refresh(feedID: feed.id)
        }
        try await waitForWaiterCount(2, feedID: feed.id, service: harness.service)
        await responseGate.release()

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
            feedURL: "https://example.com/owner-cancelled-feed.xml"
        )
        let feed = harness.feed
        harness.feedOperations.reset()
        harness.articleOperations.reset()

        let ownerTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        try await waitForGateEntry(harness.responseGate)

        let joiningTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        try await waitForWaiterCount(2, feedID: feed.id, service: harness.testHarness.service)

        ownerTask.cancel()
        let ownerResult = await ownerTask.value
        await harness.responseGate.release()
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
            feedURL: "https://example.com/joiner-cancelled-feed.xml"
        )
        let feed = harness.feed
        harness.feedOperations.reset()
        harness.articleOperations.reset()

        let ownerTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        try await waitForGateEntry(harness.responseGate)

        let joiningTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        try await waitForWaiterCount(2, feedID: feed.id, service: harness.testHarness.service)

        joiningTask.cancel()
        let joiningResult = await joiningTask.value
        await harness.responseGate.release()
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
            feedURL: "https://example.com/all-callers-cancelled-feed.xml"
        )
        let feed = harness.feed
        harness.feedOperations.reset()
        harness.articleOperations.reset()

        let ownerTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        try await waitForGateEntry(harness.responseGate)

        let joiningTask = Task { @MainActor in
            await harness.testHarness.service.refresh(feedID: feed.id)
        }
        try await waitForWaiterCount(2, feedID: feed.id, service: harness.testHarness.service)

        ownerTask.cancel()
        joiningTask.cancel()
        let ownerResult = await ownerTask.value
        let joiningResult = await joiningTask.value
        #expect(harness.testHarness.service.inFlightRefreshTasks[feed.id]?.phase == .draining)
        await harness.responseGate.release()
        try await waitForRegistryCleanup(feedID: feed.id, service: harness.testHarness.service)

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

    @Test
    func callerArrivingWhileCancelledExecutionDrainsStartsAfterCleanup() async throws {
        let feedURL = "https://example.com/draining-retry-feed.xml"
        let cancelledExecutionGate = ScriptedHTTPClientResponseGate()
        let retryExecutionGate = ScriptedHTTPClientResponseGate()
        let responseBody = makeCoalescedFeedXML()
        let feedOperations = SwiftDataRepositoryOperationCounter()
        let articleOperations = SwiftDataRepositoryOperationCounter()
        let client = ScriptedHTTPClient(
            steps: [
                .gatedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: responseBody,
                    gate: cancelledExecutionGate
                ),
                .gatedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: responseBody,
                    gate: retryExecutionGate
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

        let cancelledCaller = Task { @MainActor in
            await harness.service.refresh(feedID: feed.id)
        }
        try await waitForGateEntry(cancelledExecutionGate)

        cancelledCaller.cancel()
        let cancelledResult = await cancelledCaller.value
        #expect(cancelledResult.status == .cancelled)
        #expect(harness.service.inFlightRefreshTasks[feed.id]?.phase == .draining)

        let retryCaller = Task { @MainActor in
            await harness.service.refresh(feedID: feed.id)
        }
        try await waitForQueuedWaiterCount(1, feedID: feed.id, service: harness.service)

        #expect(await client.recordedRequests().count == 1)
        #expect(await retryExecutionGate.hasEntered() == false)
        await cancelledExecutionGate.release()

        try await waitForGateEntry(retryExecutionGate)
        #expect(await client.recordedRequests().count == 2)
        #expect(await client.maxConcurrentExecutions() == 1)
        #expect(harness.service.inFlightRefreshTasks[feed.id]?.phase == .running)
        #expect(harness.service.inFlightRefreshTasks[feed.id]?.waiterCount == 1)

        await retryExecutionGate.release()
        let retryResult = await retryCaller.value
        try await waitForRegistryCleanup(feedID: feed.id, service: harness.service)

        #expect(retryResult.status == .fetched)
        #expect(retryResult.upsertedEntryCount == 1)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).count == 1)
        let logs = try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil)
        #expect(logs.count == 2)
        #expect(Set(logs.map(\.status)) == Set(["cancelled", "fetched"]))
        #expect(feedOperations.saveCount == 3)
        #expect(articleOperations.saveCount == 0)
    }

    private func makeCancellationHarness(
        feedURL: String
    ) throws -> (
        testHarness: TestHarness,
        feed: Feed,
        feedOperations: SwiftDataRepositoryOperationCounter,
        articleOperations: SwiftDataRepositoryOperationCounter,
        responseGate: ScriptedHTTPClientResponseGate
    ) {
        let responseGate = ScriptedHTTPClientResponseGate()
        let responseBody = makeCoalescedFeedXML()
        let feedOperations = SwiftDataRepositoryOperationCounter()
        let articleOperations = SwiftDataRepositoryOperationCounter()
        let client = ScriptedHTTPClient(
            steps: [
                .gatedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: responseBody,
                    gate: responseGate
                )
            ]
        )
        let testHarness = try TestHarness.make(
            httpClient: client,
            feedRepositoryOperationRecorder: feedOperations.record,
            articleRepositoryOperationRecorder: articleOperations.record
        )
        let feed = try #require(try testHarness.insertFeeds(urls: [feedURL]).first)
        return (testHarness, feed, feedOperations, articleOperations, responseGate)
    }

    private func makeCoalescedFeedXML() -> String {
        makeValidRSSFeedXML(
            channelTitle: "Coalesced Feed",
            channelLink: "https://example.com/coalesced/",
            language: "en",
            itemTitle: "Coalesced Article",
            itemLink: "https://example.com/coalesced/articles/1",
            itemGUID: "coalesced-article-1",
            itemDescription: "Readable coalesced summary",
            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
        )
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

    private func waitForGateEntry(_ gate: ScriptedHTTPClientResponseGate) async throws {
        try await waitUntil("HTTP response gate entry") {
            await gate.hasEntered()
        }
    }

    private func waitForWaiterCount(
        _ count: Int,
        feedID: UUID,
        service: FeedRefreshService
    ) async throws {
        try await waitUntil("in-flight waiter count \(count)") {
            service.inFlightRefreshTasks[feedID]?.waiterCount == count
        }
    }

    private func waitForQueuedWaiterCount(
        _ count: Int,
        feedID: UUID,
        service: FeedRefreshService
    ) async throws {
        try await waitUntil("queued waiter count \(count)") {
            service.inFlightRefreshTasks[feedID]?.queuedWaiterCount == count
        }
    }

    private func waitForRegistryCleanup(
        feedID: UUID,
        service: FeedRefreshService
    ) async throws {
        try await waitUntil("in-flight registry cleanup") {
            service.inFlightRefreshTasks[feedID] == nil
        }
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
        throw ConcurrencyWaitError.timedOut(expectation)
    }
}

private enum ConcurrencyWaitError: Error {
    case timedOut(String)
}
