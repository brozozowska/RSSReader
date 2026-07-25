import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Large Feed Pipeline")
@MainActor
struct FeedRefreshServiceLargeFeedTests {
    @Test
    func largeFeedParsingAndPayloadPreparationKeepMainActorResponsiveWithinDeterministicMemoryBudget() async throws {
        let fixture = LargeFeedPipelineFixture.make()
        let repeatedFixture = LargeFeedPipelineFixture.make()
        let probe = LargeFeedParsingProbe()
        let worker = FeedParsingWorker(
            pipeline: { response in
                try probe.parse(response)
            },
            payloadPreparation: { entries, fetchedAt in
                try probe.preparePayloads(entries, fetchedAt: fetchedAt)
            }
        )
        let heartbeat = Task { @MainActor in
            while Task.isCancelled == false {
                probe.recordMainActorHeartbeatIfWorking()
                await Task.yield()
            }
        }

        let result: FeedParsingWorkerResult
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
        #expect(probe.didRunParsingOffMainThread)
        #expect(probe.didRunPayloadPreparationOffMainThread)
        #expect(probe.parsingHeartbeatCount > 0)
        #expect(probe.payloadPreparationHeartbeatCount > 0)
        #expect(result.feed.kind == .rss)
        #expect(result.feed.entries.count == fixture.expectedAcceptedEntryCount)
        #expect(result.articlePayloads.count == fixture.expectedAcceptedEntryCount)
        #expect(result.diagnostics.rejectedEntries.count == fixture.expectedRejectedEntryCount)
    }

    @Test
    func largeFeedRefreshKeepsActualSwiftDataOperationsWithinUpperBounds() async throws {
        let fixture = LargeFeedPipelineFixture.make()
        let feedOperations = SwiftDataRepositoryOperationCounter()
        let articleOperations = SwiftDataRepositoryOperationCounter()
        let client = ScriptedHTTPClient(
            steps: [
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: fixture.body
                )
            ]
        )
        let harness = try TestHarness.make(
            httpClient: client,
            feedRepositoryOperationRecorder: feedOperations.record,
            articleRepositoryOperationRecorder: articleOperations.record
        )
        let feed = Feed(url: fixture.feedURL.absoluteString, title: "Large Feed")
        try harness.feedRepository.insert(feed)
        feedOperations.reset()
        articleOperations.reset()
        let service = FeedRefreshService(
            logger: TestLogger(),
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: harness.feedRepository,
            articleRepository: harness.articleRepository
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

        #expect(feedOperations.fetchCount > 0)
        #expect(
            feedOperations.fetchCount
                <= LargeFeedPipelineTestContract.maximumFeedFetchOperationCount
        )
        #expect(
            feedOperations.saveCount
                <= LargeFeedPipelineTestContract.maximumFeedSaveOperationCount
        )
        #expect(articleOperations.fetchCount > 0)
        #expect(
            articleOperations.fetchCount
                <= LargeFeedPipelineTestContract.maximumArticleFetchOperationCount
        )
        #expect(
            articleOperations.saveCount
                <= LargeFeedPipelineTestContract.maximumArticleSaveOperationCount
        )

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(persistedArticles.count == fixture.expectedAcceptedEntryCount)
    }
}

private final class LargeFeedParsingProbe: @unchecked Sendable {
    private let condition = NSCondition()
    private var parsingStarted = false
    private var parsingFinished = false
    private var parsingRanOnMainThread = true
    private var payloadPreparationStarted = false
    private var payloadPreparationFinished = false
    private var payloadPreparationRanOnMainThread = true
    private var parsingHeartbeats = 0
    private var payloadPreparationHeartbeats = 0

    var didRunParsingOffMainThread: Bool {
        condition.withLock { parsingStarted && parsingRanOnMainThread == false }
    }

    var didRunPayloadPreparationOffMainThread: Bool {
        condition.withLock {
            payloadPreparationStarted && payloadPreparationRanOnMainThread == false
        }
    }

    var parsingHeartbeatCount: Int {
        condition.withLock { parsingHeartbeats }
    }

    var payloadPreparationHeartbeatCount: Int {
        condition.withLock { payloadPreparationHeartbeats }
    }

    func parse(_ response: FeedResponse) throws -> FeedParsePipelineResult {
        condition.lock()
        parsingStarted = true
        parsingRanOnMainThread = Thread.isMainThread
        let heartbeatDeadline = Date(
            timeIntervalSinceNow: LargeFeedPipelineTestContract.maximumMainActorHeartbeatWait
        )
        while parsingHeartbeats == 0, condition.wait(until: heartbeatDeadline) {
            continue
        }
        condition.unlock()

        defer {
            condition.withLock {
                parsingFinished = true
            }
        }

        return try FeedParserService.parsePipelineResult(response)
    }

    func preparePayloads(
        _ entries: [ParsedFeedEntryDTO],
        fetchedAt: Date
    ) throws -> [ArticleUpsertPayload] {
        condition.lock()
        payloadPreparationStarted = true
        payloadPreparationRanOnMainThread = Thread.isMainThread
        let heartbeatDeadline = Date(
            timeIntervalSinceNow: LargeFeedPipelineTestContract.maximumMainActorHeartbeatWait
        )
        while payloadPreparationHeartbeats == 0, condition.wait(until: heartbeatDeadline) {
            continue
        }
        condition.unlock()

        defer {
            condition.withLock {
                payloadPreparationFinished = true
            }
        }

        return try ArticleUpsertPayload.makeAllPrepared(entries: entries, fetchedAt: fetchedAt)
    }

    func recordMainActorHeartbeatIfWorking() {
        condition.withLock {
            if parsingStarted, parsingFinished == false {
                parsingHeartbeats += 1
            }
            if payloadPreparationStarted, payloadPreparationFinished == false {
                payloadPreparationHeartbeats += 1
            }
            condition.broadcast()
        }
    }
}
