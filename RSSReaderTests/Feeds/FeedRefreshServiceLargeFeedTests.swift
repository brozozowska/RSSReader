import Foundation
import SwiftData
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

        let result: FeedRefreshParsingResult
        do {
            result = try await worker.parseRefresh(fixture.makeResponse())
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
        #expect(result.kind == .rss)
        #expect(result.metadata.title == "Large Deterministic Feed")
        #expect(result.acceptedEntryCount == fixture.expectedAcceptedEntryCount)
        #expect(result.articlePayloads.count == fixture.expectedAcceptedEntryCount)
        #expect(result.diagnostics.rejectedEntries.count == fixture.expectedRejectedEntryCount)
    }

    @Test
    func largeFeedPreviewKeepsPipelineOffMainActorWithoutMaterializingArticlePayloads() async throws {
        let fixture = LargeFeedPipelineFixture.make()
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
        let client = ScriptedHTTPClient(
            responsesByURL: [
                fixture.feedURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: fixture.body
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let service = DefaultFeedManagementService(
            logger: TestLogger(),
            httpClient: client,
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedParsingWorker: worker,
            feedRepository: harness.feedRepository,
            folderRepository: harness.folderRepository,
            articleRepository: harness.articleRepository
        )
        let heartbeat = Task { @MainActor in
            while Task.isCancelled == false {
                probe.recordMainActorHeartbeatIfWorking()
                await Task.yield()
            }
        }

        let preview: FeedManagementFeedPreview
        do {
            preview = try await service.previewFeed(urlString: fixture.feedURL.absoluteString)
        } catch {
            heartbeat.cancel()
            await heartbeat.value
            throw error
        }
        heartbeat.cancel()
        await heartbeat.value

        #expect(
            Int64(fixture.bodyByteCount)
                <= AppResourceBudgetContract.current.feedXML.body.maximumCompressedBodyBytes
        )
        #expect(probe.maximumObservedElementCount == fixture.expectedXMLElementCount)
        #expect(
            probe.maximumObservedElementCount
                <= AppResourceBudgetContract.current.feedXML.maximumElementCount
        )
        #expect(probe.maximumObservedDepth == fixture.expectedXMLMaximumDepth)
        #expect(
            probe.maximumObservedDepth
                <= AppResourceBudgetContract.current.feedXML.maximumDepth
        )
        #expect(probe.maximumObservedMaterializedEntryCount == fixture.rawEntryCount)
        #expect(
            probe.maximumObservedMaterializedEntryCount
                <= AppResourceBudgetContract.current.feedXML.maximumEntryCount
        )
        #expect(probe.didRunXMLPipelineOffMainThread)
        #expect(probe.didRunEntryProcessingOffMainThread)
        #expect(probe.xmlPipelineHeartbeatCount > 0)
        #expect(probe.entryProcessingHeartbeatCount > 0)
        #expect(probe.observedEntryStages == Set(FeedParsingEntryStage.allCases))
        #expect(probe.didStartPayloadPreparation == false)
        #expect(probe.payloadPreparationHeartbeatCount == 0)
        #expect(probe.materializedPayloadCount == 0)
        #expect(probe.materializedPayloadTextByteCount == 0)
        #expect(preview.title == "Large Deterministic Feed")
        #expect(preview.siteURL == "https://example.com/large/")
        #expect(preview.language == "en")
        #expect(preview.kind == .rss)
        #expect(preview.parserAnomalyCount == fixture.expectedRejectedEntryCount * 3)
        #expect(preview.rejectedEntryCount == fixture.expectedRejectedEntryCount)
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

    @Test
    func largeFeedReconciliationMeasuresSynchronousMainActorStagesWithinStructuralBounds() async throws {
        let fixture = LargeFeedPipelineFixture.make()
        let reconciliationProbe = LargeFeedReconciliationProbe()
        let client = ScriptedHTTPClient(
            steps: [
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: fixture.body
                ),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: fixture.body
                )
            ]
        )
        let harness = try TestHarness.make(
            httpClient: client,
            articleReconciliationProgressProbe: reconciliationProbe.record
        )
        let feed = Feed(url: fixture.feedURL.absoluteString, title: "Large Feed")
        try harness.feedRepository.insert(feed)
        let seedResult = await harness.service.refresh(feedID: feed.id)
        #expect(seedResult.status == .fetched)
        reconciliationProbe.reset()

        let heartbeat = Task { @MainActor in
            while Task.isCancelled == false {
                reconciliationProbe.recordMainActorHeartbeat()
                await Task.yield()
            }
        }
        let refreshResult = await harness.service.refresh(feedID: feed.id)
        heartbeat.cancel()
        await heartbeat.value

        #expect(refreshResult.status == .fetched)
        #expect(reconciliationProbe.mainActorHeartbeatCount > 0)
        #expect(reconciliationProbe.didRunEveryObservedStageOnMainActor)
        #expect(
            reconciliationProbe.maximumProcessedItemCount(for: .snapshotCanonicalization)
                == fixture.expectedAcceptedEntryCount
        )
        #expect(
            reconciliationProbe.maximumProcessedItemCount(for: .projectionAndArchive)
                == fixture.expectedAcceptedEntryCount
        )
        #expect(
            reconciliationProbe.maximumProcessedItemCount(for: .payloadApply)
                == fixture.expectedAcceptedEntryCount
        )
        #expect(
            reconciliationProbe.maximumTotalItemCount
                <= AppResourceBudgetContract.current.feedXML.maximumEntryCount
        )
        #expect(
            reconciliationProbe.activeStageHeartbeatCounts.values.allSatisfy { $0 == 0 }
        )
        #expect(
            ArticleFeedSnapshotReconciliationPolicy.cancellationCheckpointInterval
                <= LargeFeedPipelineTestContract.maximumReconciliationItemsBetweenCancellationChecks
        )
    }

    @Test
    func largeFeedReconciliationCancellationStopsWithinBoundAndRollsBackMutations() async throws {
        let fixture = LargeFeedPipelineFixture.make()
        let reconciliationProbe = LargeFeedReconciliationProbe()
        let cancellationProbe = LargeFeedReconciliationCancellationProbe(
            progressProbe: reconciliationProbe,
            targetStage: .projectionAndArchive
        )
        let client = ScriptedHTTPClient(
            steps: [
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: fixture.body
                ),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: makeEmptyLargeFeedXML()
                )
            ]
        )
        let harness = try TestHarness.make(
            httpClient: client,
            articleReconciliationCancellationCheckpoint: cancellationProbe.check,
            articleReconciliationProgressProbe: reconciliationProbe.record
        )
        let feed = Feed(url: fixture.feedURL.absoluteString, title: "Large Feed")
        try harness.feedRepository.insert(feed)
        let seedResult = await harness.service.refresh(feedID: feed.id)
        #expect(seedResult.status == .fetched)
        let seededArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(seededArticles.count == fixture.expectedAcceptedEntryCount)
        #expect(seededArticles.allSatisfy { $0.archivedAt == nil })

        reconciliationProbe.reset()
        cancellationProbe.arm()
        let cancelledResult = await harness.service.refresh(feedID: feed.id)

        #expect(cancelledResult.status == .cancelled)
        #expect(cancellationProbe.didInject)
        #expect(cancellationProbe.processedItemCountAtCancellation > 0)
        #expect(
            cancellationProbe.processedItemCountAtCancellation
                <= LargeFeedPipelineTestContract.maximumReconciliationItemsBetweenCancellationChecks
        )
        #expect(harness.service.inFlightRefreshTasks[feed.id] == nil)
        let rolledBackArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(rolledBackArticles.count == fixture.expectedAcceptedEntryCount)
        #expect(rolledBackArticles.allSatisfy { $0.archivedAt == nil })
        let logs = try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil)
        #expect(logs.count == 2)
        #expect(Set(logs.map(\.status)) == Set(["cancelled", "fetched"]))
    }

    @Test(arguments: [
        ArticleFeedSnapshotReconciliationStage.articleStateMaterialization,
        .articleStateCanonicalization,
        .articleStateDuplicateDeletion
    ])
    func largeArticleStateRepairCancellationIsBoundedAndRollsBackBeforeSuccessfulRetry(
        targetStage: ArticleFeedSnapshotReconciliationStage
    ) async throws {
        let feedURL = "https://example.com/large-state-repair.xml"
        let rawGUID = "large-state-repair"
        let identity = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: feedURL,
                guid: rawGUID,
                title: "Large State Repair Article"
            )
        )
        let stateCount = LargeFeedPipelineTestContract.uniqueEntryCount
        let responseBody = makeValidRSSFeedXML(
            channelTitle: "Large State Repair Feed",
            channelLink: "https://example.com/state-repair/",
            language: "en",
            itemTitle: "Large State Repair Article",
            itemLink: "https://example.com/state-repair/article",
            itemGUID: rawGUID,
            itemDescription: "Large state repair summary",
            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
        )
        let responseStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: responseBody
        )
        let client = ScriptedHTTPClient(steps: [responseStep, responseStep])
        let articleOperations = SwiftDataRepositoryOperationCounter()
        let reconciliationProbe = LargeFeedReconciliationProbe()
        let cancellationProbe = LargeFeedReconciliationCancellationProbe(
            progressProbe: reconciliationProbe,
            targetStage: targetStage
        )
        let harness = try TestHarness.make(
            httpClient: client,
            articleRepositoryOperationRecorder: articleOperations.record,
            articleReconciliationCancellationCheckpoint: cancellationProbe.check,
            articleReconciliationProgressProbe: reconciliationProbe.record
        )
        let feed = Feed(
            url: feedURL,
            title: "Original State Repair Feed"
        )
        try harness.feedRepository.insert(feed)
        let modelContext = harness.modelContainer.mainContext
        let olderUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let newerUpdatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        modelContext.insert(
            Article(
                feedID: feed.id,
                feedTitle: feed.displayTitle,
                externalID: identity,
                url: "https://example.com/state-repair/older",
                title: "Older State Repair Article",
                updatedAt: olderUpdatedAt
            )
        )
        modelContext.insert(
            Article(
                feedID: feed.id,
                feedTitle: feed.displayTitle,
                externalID: " \(identity) ",
                url: "https://example.com/state-repair/canonical",
                title: "Canonical State Repair Article",
                updatedAt: newerUpdatedAt
            )
        )

        var canonicalStateID = UUID()
        for index in 0..<stateCount {
            let stateID = UUID()
            if index == stateCount - 1 {
                canonicalStateID = stateID
            }
            let stateUpdatedAt = Date(
                timeIntervalSince1970: newerUpdatedAt.timeIntervalSince1970 + Double(index)
            )
            modelContext.insert(
                ArticleState(
                    id: stateID,
                    articleExternalID: index.isMultiple(of: 2) ? identity : " \(identity) ",
                    feedID: feed.id,
                    isRead: index == stateCount - 1,
                    readAt: index == stateCount - 1 ? stateUpdatedAt : nil,
                    isStarred: index == stateCount - 1,
                    starredAt: index == stateCount - 1 ? stateUpdatedAt : nil,
                    isHidden: index == stateCount - 1,
                    hiddenAt: index == stateCount - 1 ? stateUpdatedAt : nil,
                    lastInteractionAt: stateUpdatedAt,
                    updatedAt: stateUpdatedAt
                )
            )
        }
        try modelContext.save()
        articleOperations.reset()
        reconciliationProbe.reset()
        cancellationProbe.arm()

        let cancelledResult = await harness.service.refresh(feedID: feed.id)

        #expect(cancelledResult.status == .cancelled)
        #expect(cancellationProbe.didInject)
        #expect(cancellationProbe.processedItemCountAtCancellation > 0)
        #expect(
            cancellationProbe.processedItemCountAtCancellation
                <= LargeFeedPipelineTestContract.maximumReconciliationItemsBetweenCancellationChecks
        )
        #expect(harness.service.inFlightRefreshTasks[feed.id] == nil)
        #expect(articleOperations.fetchCount > 0)
        #expect(
            articleOperations.fetchCount
                <= LargeFeedPipelineTestContract.maximumArticleFetchOperationCountWithStateRepair
        )
        #expect(articleOperations.saveCount == LargeFeedPipelineTestContract.maximumArticleSaveOperationCount)
        let rolledBackArticles = try modelContext.fetch(FetchDescriptor<Article>())
        let rolledBackStates = try modelContext.fetch(FetchDescriptor<ArticleState>())
        #expect(rolledBackArticles.count == 2)
        #expect(Set(rolledBackArticles.map(\.externalID)) == [identity, " \(identity) "])
        #expect(rolledBackStates.count == stateCount)
        #expect(rolledBackStates.contains { $0.id == canonicalStateID })
        let attemptedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(attemptedFeed.lastFetchedAt != nil)
        let cancelledLog = try #require(
            try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id)
        )
        #expect(cancelledLog.status == "cancelled")

        articleOperations.reset()
        reconciliationProbe.reset()
        cancellationProbe.disarm()
        let retryResult = await harness.service.refresh(feedID: feed.id)

        #expect(retryResult.status == .fetched)
        #expect(harness.service.inFlightRefreshTasks[feed.id] == nil)
        #expect(await client.recordedRequests().count == 2)
        #expect(articleOperations.fetchCount > 0)
        #expect(
            articleOperations.fetchCount
                <= LargeFeedPipelineTestContract.maximumArticleFetchOperationCountWithStateRepair
        )
        #expect(articleOperations.saveCount == LargeFeedPipelineTestContract.maximumArticleSaveOperationCount)
        #expect(
            reconciliationProbe.maximumProcessedItemCount(for: .articleStateMaterialization)
                == stateCount
        )
        #expect(
            reconciliationProbe.maximumProcessedItemCount(for: .articleStateCanonicalization)
                == stateCount + 1
        )
        #expect(
            reconciliationProbe.maximumProcessedItemCount(for: .articleStateDuplicateDeletion)
                == stateCount - 1
        )
        let verificationContext = ModelContext(harness.modelContainer)
        let repairedArticles = try verificationContext.fetch(FetchDescriptor<Article>())
        let repairedStates = try verificationContext.fetch(FetchDescriptor<ArticleState>())
        let repairedState = try #require(repairedStates.first)
        #expect(repairedArticles.count == 1)
        #expect(repairedArticles.first?.externalID == identity)
        #expect(repairedStates.count == 1)
        #expect(repairedState.id == canonicalStateID)
        #expect(repairedState.articleExternalID == identity)
        #expect(repairedState.isRead)
        #expect(repairedState.isStarred)
        #expect(repairedState.isHidden)
        let logs = try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil)
        #expect(logs.count == 2)
        #expect(Set(logs.map(\.status)) == Set(["cancelled", "fetched"]))
    }

    private func makeEmptyLargeFeedXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Large Deterministic Feed</title>
            <link>https://example.com/large/</link>
            <description>Empty reconciliation payload</description>
          </channel>
        </rss>
        """
    }
}

@MainActor
private final class LargeFeedReconciliationProbe {
    private var observedMainActorValues: [Bool] = []
    private var maximumProcessedItemCounts: [ArticleFeedSnapshotReconciliationStage: Int] = [:]
    private var maximumTotalItemCounts: [ArticleFeedSnapshotReconciliationStage: Int] = [:]
    private var activeStages: Set<ArticleFeedSnapshotReconciliationStage> = []
    private(set) var activeStageHeartbeatCounts: [ArticleFeedSnapshotReconciliationStage: Int] = [:]
    private(set) var mainActorHeartbeatCount = 0

    var didRunEveryObservedStageOnMainActor: Bool {
        observedMainActorValues.isEmpty == false && observedMainActorValues.allSatisfy { $0 }
    }

    var maximumTotalItemCount: Int {
        maximumTotalItemCounts.values.max() ?? 0
    }

    func record(_ progress: ArticleFeedSnapshotReconciliationProgress) {
        observedMainActorValues.append(Thread.isMainThread)
        maximumProcessedItemCounts[progress.stage] = max(
            maximumProcessedItemCounts[progress.stage] ?? 0,
            progress.processedItemCount
        )
        maximumTotalItemCounts[progress.stage] = max(
            maximumTotalItemCounts[progress.stage] ?? 0,
            progress.totalItemCount
        )

        if progress.totalItemCount > 0, progress.processedItemCount == 0 {
            activeStages.insert(progress.stage)
            activeStageHeartbeatCounts[progress.stage] = 0
        }
        if progress.processedItemCount == progress.totalItemCount {
            activeStages.remove(progress.stage)
        }
    }

    func recordMainActorHeartbeat() {
        mainActorHeartbeatCount += 1
        for stage in activeStages {
            activeStageHeartbeatCounts[stage, default: 0] += 1
        }
    }

    func maximumProcessedItemCount(
        for stage: ArticleFeedSnapshotReconciliationStage
    ) -> Int {
        maximumProcessedItemCounts[stage] ?? 0
    }

    func reset() {
        observedMainActorValues.removeAll()
        maximumProcessedItemCounts.removeAll()
        maximumTotalItemCounts.removeAll()
        activeStages.removeAll()
        activeStageHeartbeatCounts.removeAll()
        mainActorHeartbeatCount = 0
    }
}

@MainActor
private final class LargeFeedReconciliationCancellationProbe {
    private let progressProbe: LargeFeedReconciliationProbe
    private let targetStage: ArticleFeedSnapshotReconciliationStage
    private var isArmed = false
    private(set) var didInject = false
    private(set) var processedItemCountAtCancellation = 0

    init(
        progressProbe: LargeFeedReconciliationProbe,
        targetStage: ArticleFeedSnapshotReconciliationStage
    ) {
        self.progressProbe = progressProbe
        self.targetStage = targetStage
    }

    func arm() {
        isArmed = true
        didInject = false
        processedItemCountAtCancellation = 0
    }

    func disarm() {
        isArmed = false
    }

    func check(_ checkpoint: ArticleFeedSnapshotCancellationCheckpoint) throws {
        try Task.checkCancellation()
        guard isArmed,
              checkpoint == .during(targetStage),
              didInject == false else {
            return
        }

        let processedItemCount = progressProbe.maximumProcessedItemCount(for: targetStage)
        guard processedItemCount > 0 else { return }
        didInject = true
        processedItemCountAtCancellation = processedItemCount
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        try Task.checkCancellation()
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

    var didStartPayloadPreparation: Bool {
        condition.withLock { payloadPreparationStarted }
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
