import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Large Feed Pipeline")
@MainActor
struct FeedRefreshServiceLargeFeedTests {
    @Test
    func largeFeedParsingKeepsMainActorResponsiveWithinDeterministicMemoryBudget() async throws {
        let fixture = LargeFeedPipelineFixture.make()
        let repeatedFixture = LargeFeedPipelineFixture.make()
        let probe = LargeFeedParsingProbe()
        let worker = FeedParsingWorker { response in
            try probe.parse(response)
        }
        let heartbeat = Task { @MainActor in
            while Task.isCancelled == false {
                probe.recordMainActorHeartbeatIfParsing()
                await Task.yield()
            }
        }

        let result: FeedParsePipelineResult
        do {
            result = try await worker.parse(fixture.makeResponse())
        } catch {
            heartbeat.cancel()
            await heartbeat.value
            throw error
        }
        heartbeat.cancel()
        await heartbeat.value

        #expect(fixture.body == repeatedFixture.body)
        #expect(fixture.rawEntryCount == LargeFeedPipelineTestContract.rawEntryCount)
        #expect(
            Int64(fixture.bodyByteCount)
                <= AppResourceBudgetContract.current.feedXML.body.maximumCompressedBodyBytes
        )
        #expect(
            fixture.estimatedWorkingSetByteCount
                <= LargeFeedPipelineTestContract.maximumEstimatedWorkingSetBytes
        )
        #expect(probe.didRunOffMainThread)
        #expect(probe.mainActorHeartbeatCount > 0)
        #expect(result.feed.kind == .rss)
        #expect(result.feed.entries.count == fixture.expectedAcceptedEntryCount)
        #expect(result.diagnostics.rejectedEntries.count == fixture.expectedRejectedEntryCount)
    }

    @Test
    func largeFeedRefreshUsesConstantRepositoryOperationsWithinWallClockBudget() async throws {
        let fixture = LargeFeedPipelineFixture.make()
        let client = ScriptedHTTPClient(
            steps: [
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: fixture.body
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = Feed(url: fixture.feedURL.absoluteString, title: "Large Feed")
        try harness.feedRepository.insert(feed)
        let feedRepository = CountingFeedRepository(backing: harness.feedRepository)
        let articleRepository = CountingArticleRepository(backing: harness.articleRepository)
        let service = FeedRefreshService(
            logger: TestLogger(),
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: feedRepository,
            articleRepository: articleRepository
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = await service.refresh(feedID: feed.id)

        let elapsed = startedAt.duration(to: clock.now)
        #expect(result.status == .fetched)
        #expect(
            result.processedEntryCount
                == fixture.expectedAcceptedEntryCount + fixture.expectedRejectedEntryCount
        )
        #expect(result.upsertedEntryCount == fixture.expectedAcceptedEntryCount)
        #expect(result.rejectedEntryCount == fixture.expectedRejectedEntryCount)
        #expect(elapsed < LargeFeedPipelineTestContract.maximumRefreshDuration)

        #expect(feedRepository.fetchRequestCount == 4)
        #expect(feedRepository.updateMetadataCallCount == 4)
        #expect(feedRepository.saveAfterUpdateRequestCount == 1)
        #expect(feedRepository.explicitSaveRequestCount == 1)
        #expect(feedRepository.saveRequestCount == 2)
        #expect(articleRepository.feedScopedFetchRequestCount == 1)
        #expect(articleRepository.identityFetchRequestCount == 0)
        #expect(articleRepository.reconcileFeedSnapshotCallCount == 1)
        #expect(articleRepository.saveRequestCount == 0)

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(persistedArticles.count == fixture.expectedAcceptedEntryCount)
    }
}

private final class LargeFeedParsingProbe: @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false
    private var finished = false
    private var ranOnMainThread = true
    private var heartbeatCount = 0

    var didRunOffMainThread: Bool {
        condition.withLock { started && ranOnMainThread == false }
    }

    var mainActorHeartbeatCount: Int {
        condition.withLock { heartbeatCount }
    }

    func parse(_ response: FeedResponse) throws -> FeedParsePipelineResult {
        condition.lock()
        started = true
        ranOnMainThread = Thread.isMainThread
        let heartbeatDeadline = Date(
            timeIntervalSinceNow: LargeFeedPipelineTestContract.maximumMainActorHeartbeatWait
        )
        while heartbeatCount == 0, condition.wait(until: heartbeatDeadline) {
            continue
        }
        condition.unlock()

        defer {
            condition.withLock {
                finished = true
            }
        }

        return try FeedParserService.parsePipelineResult(response)
    }

    func recordMainActorHeartbeatIfParsing() {
        condition.withLock {
            guard started, finished == false else { return }
            heartbeatCount += 1
            condition.signal()
        }
    }
}
