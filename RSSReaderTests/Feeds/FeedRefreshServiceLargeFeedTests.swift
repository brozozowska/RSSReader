import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Large Feed Pipeline")
@MainActor
struct FeedRefreshServiceLargeFeedTests {
    @Test
    func actualXMLAndPayloadMaterializationKeepMainActorResponsiveWithinStructuralBounds() async throws {
        let fixture = LargeFeedPipelineFixture.make()
        let repeatedFixture = LargeFeedPipelineFixture.make()
        let probe = LargeFeedParsingProbe()
        let worker = FeedParsingWorker(
            pipeline: { response in
                defer { probe.finishXMLPipeline() }
                return try FeedParserService.parsePipelineResult(
                    response,
                    xmlProgressProbe: probe.recordXMLProgress,
                    entryProgressProbe: probe.recordEntryProgress
                )
            },
            payloadPreparation: { entries, fetchedAt in
                defer { probe.finishPayloadPreparation() }
                return try ArticleUpsertPayload.makeAllPrepared(
                    entries: entries,
                    fetchedAt: fetchedAt,
                    materializationProbe: probe.recordPayloadMaterialization
                )
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
            probe.maximumObservedElementCount
                == fixture.expectedXMLElementCount
        )
        #expect(
            probe.maximumObservedElementCount
                <= AppResourceBudgetContract.current.feedXML.maximumElementCount
        )
        #expect(
            probe.maximumObservedDepth
                == fixture.expectedXMLMaximumDepth
        )
        #expect(
            probe.maximumObservedDepth
                <= AppResourceBudgetContract.current.feedXML.maximumDepth
        )
        #expect(
            probe.maximumObservedMaterializedEntryCount
                == fixture.rawEntryCount
        )
        #expect(
            probe.maximumObservedMaterializedEntryCount
                <= AppResourceBudgetContract.current.feedXML.maximumEntryCount
        )
        #expect(probe.didRunXMLPipelineOffMainThread)
        #expect(probe.didRunEntryProcessingOffMainThread)
        #expect(probe.didRunPayloadPreparationOffMainThread)
        #expect(probe.xmlPipelineHeartbeatCount > 0)
        #expect(probe.entryProcessingHeartbeatCount > 0)
        #expect(probe.payloadPreparationHeartbeatCount > 0)
        #expect(probe.observedEntryStages == Set(FeedParsingEntryStage.allCases))
        #expect(probe.materializedPayloadCount == fixture.expectedAcceptedEntryCount)
        #expect(probe.materializedPayloadTextByteCount > 0)
        #expect(probe.materializedPayloadTextByteCount <= fixture.bodyByteCount)
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
    private var xmlPipelineStarted = false
    private var xmlPipelineFinished = false
    private var xmlPipelineRanOnMainThread = true
    private var entryProcessingStarted = false
    private var entryProcessingFinished = false
    private var entryProcessingRanOnMainThread = true
    private var payloadPreparationStarted = false
    private var payloadPreparationFinished = false
    private var payloadPreparationRanOnMainThread = true
    private var xmlPipelineHeartbeats = 0
    private var entryProcessingHeartbeats = 0
    private var payloadPreparationHeartbeats = 0
    private var observedStages: Set<FeedParsingEntryStage> = []
    private var observedElementCount = 0
    private var observedMaximumDepth = 0
    private var observedMaterializedEntryCount = 0
    private var observedMaterializedPayloadCount = 0
    private var observedMaterializedPayloadTextByteCount = 0

    var didRunXMLPipelineOffMainThread: Bool {
        condition.withLock { xmlPipelineStarted && xmlPipelineRanOnMainThread == false }
    }

    var didRunPayloadPreparationOffMainThread: Bool {
        condition.withLock {
            payloadPreparationStarted && payloadPreparationRanOnMainThread == false
        }
    }

    var didRunEntryProcessingOffMainThread: Bool {
        condition.withLock {
            entryProcessingStarted && entryProcessingRanOnMainThread == false
        }
    }

    var xmlPipelineHeartbeatCount: Int {
        condition.withLock { xmlPipelineHeartbeats }
    }

    var payloadPreparationHeartbeatCount: Int {
        condition.withLock { payloadPreparationHeartbeats }
    }

    var entryProcessingHeartbeatCount: Int {
        condition.withLock { entryProcessingHeartbeats }
    }

    var observedEntryStages: Set<FeedParsingEntryStage> {
        condition.withLock { observedStages }
    }

    var maximumObservedElementCount: Int {
        condition.withLock { observedElementCount }
    }

    var maximumObservedDepth: Int {
        condition.withLock { observedMaximumDepth }
    }

    var maximumObservedMaterializedEntryCount: Int {
        condition.withLock { observedMaterializedEntryCount }
    }

    var materializedPayloadCount: Int {
        condition.withLock { observedMaterializedPayloadCount }
    }

    var materializedPayloadTextByteCount: Int {
        condition.withLock { observedMaterializedPayloadTextByteCount }
    }

    func recordXMLProgress(_ progress: FeedXMLParserProgress) {
        condition.lock()
        if xmlPipelineStarted == false {
            xmlPipelineStarted = true
            xmlPipelineRanOnMainThread = Thread.isMainThread
        }
        observedElementCount = max(observedElementCount, progress.elementCount)
        observedMaximumDepth = max(observedMaximumDepth, progress.currentDepth)
        observedMaterializedEntryCount = max(
            observedMaterializedEntryCount,
            progress.materializedEntryCount
        )
        waitForHeartbeatIfNeeded(currentHeartbeatCount: { xmlPipelineHeartbeats })
        condition.unlock()
    }

    func finishXMLPipeline() {
        condition.withLock {
            xmlPipelineFinished = true
            entryProcessingFinished = true
            condition.broadcast()
        }
    }

    func recordEntryProgress(
        _ stage: FeedParsingEntryStage,
        _ processedEntryCount: Int
    ) {
        condition.lock()
        if entryProcessingStarted == false {
            entryProcessingStarted = true
            entryProcessingRanOnMainThread = Thread.isMainThread
        }
        if processedEntryCount > 0 {
            observedStages.insert(stage)
        }
        waitForHeartbeatIfNeeded(currentHeartbeatCount: { entryProcessingHeartbeats })
        condition.unlock()
    }

    func recordPayloadMaterialization(
        _ materializedPayloadCount: Int,
        _ payload: ArticleUpsertPayload
    ) {
        condition.lock()
        if payloadPreparationStarted == false {
            payloadPreparationStarted = true
            payloadPreparationRanOnMainThread = Thread.isMainThread
        }
        observedMaterializedPayloadCount = materializedPayloadCount
        observedMaterializedPayloadTextByteCount += payloadTextByteCount(payload)
        waitForHeartbeatIfNeeded(currentHeartbeatCount: { payloadPreparationHeartbeats })
        condition.unlock()
    }

    func finishPayloadPreparation() {
        condition.withLock {
            payloadPreparationFinished = true
            condition.broadcast()
        }
    }

    func recordMainActorHeartbeatIfWorking() {
        condition.withLock {
            if xmlPipelineStarted, xmlPipelineFinished == false {
                xmlPipelineHeartbeats += 1
            }
            if entryProcessingStarted, entryProcessingFinished == false {
                entryProcessingHeartbeats += 1
            }
            if payloadPreparationStarted, payloadPreparationFinished == false {
                payloadPreparationHeartbeats += 1
            }
            condition.broadcast()
        }
    }

    private func waitForHeartbeatIfNeeded(currentHeartbeatCount: () -> Int) {
        let heartbeatDeadline = Date(
            timeIntervalSinceNow: LargeFeedPipelineTestContract.maximumMainActorHeartbeatWait
        )
        while currentHeartbeatCount() == 0, condition.wait(until: heartbeatDeadline) {
            continue
        }
    }

    private func payloadTextByteCount(_ payload: ArticleUpsertPayload) -> Int {
        [
            payload.externalID,
            payload.guid,
            payload.url,
            payload.canonicalURL,
            payload.title,
            payload.summary,
            payload.contentHTML,
            payload.contentText,
            payload.author,
            payload.imageURL
        ]
        .compactMap { $0 }
        .reduce(into: 0) { byteCount, value in
            byteCount += value.utf8.count
        }
    }
}
