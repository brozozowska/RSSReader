import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Parsing Worker")
@MainActor
struct FeedParsingWorkerTests {
    @Test
    func workerRunsCompletePipelineAndPayloadPreparationOffMainActor() async throws {
        let probe = FeedParsingExecutionProbe()
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let worker = FeedParsingWorker(
            pipeline: { response in
                probe.recordPipelineStart()
                return try FeedParserService.parsePipelineResult(response)
            },
            payloadPreparation: { entries, fetchedAt in
                probe.recordPayloadPreparationStart()
                return try ArticleUpsertPayload.makeAllPrepared(entries: entries, fetchedAt: fetchedAt)
            }
        )

        let result = try await worker.parseRefresh(makeResponse(), fetchedAt: fetchedAt)

        #expect(probe.didRunPipelineOffMainThread)
        #expect(probe.didRunPayloadPreparationOffMainThread)
        #expect(result.kind == .rss)
        #expect(result.metadata.title == "Worker & Feed")
        #expect(result.acceptedEntryCount == 1)
        #expect(result.diagnostics.rejectedEntries.count == 1)
        let payload = try #require(result.articlePayloads.first)
        #expect(result.articlePayloads.count == result.acceptedEntryCount)
        #expect(payload.title == "Richer duplicate title")
        #expect(payload.searchableText.contains("Richer duplicate title"))
        #expect(payload.publishedAt == FeedDateParsingService.parse("Tue, 02 Jan 2024 10:15:30 +0000"))
        #expect(payload.fetchedAt == fetchedAt)
    }

    @Test
    func workerPayloadPreparationReusesNormalizedDatesWithoutParsingRawValuesAgain() async throws {
        let normalizedPublishedAt = Date(timeIntervalSince1970: 1_704_198_530)
        let pipelineResult = FeedParsePipelineResult(
            feed: ParsedFeedDTO(
                kind: .rss,
                metadata: ParsedFeedMetadataDTO(title: "Prepared dates"),
                entries: [
                    ParsedFeedEntryDTO(
                        externalID: "prepared-date-entry",
                        url: "https://example.com/articles/prepared-date",
                        title: "Prepared date",
                        publishedAtRaw: "raw value must not be reparsed",
                        publishedAt: normalizedPublishedAt
                    )
                ]
            ),
            diagnostics: FeedParsePipelineDiagnostics(
                parserAnomalies: [],
                rejectedEntries: []
            )
        )
        let worker = FeedParsingWorker(pipeline: { _ in pipelineResult })

        let result = try await worker.parseRefresh(
            makeResponse(),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let payload = try #require(result.articlePayloads.first)
        #expect(payload.publishedAt == normalizedPublishedAt)
    }

    @Test
    func previewReturnsPipelineResultWithoutPreparingArticlePayloads() async throws {
        let probe = FeedParsingExecutionProbe()
        let worker = FeedParsingWorker(
            payloadPreparation: { _, _ in
                probe.recordPayloadPreparationStart()
                return []
            }
        )

        let result = try await worker.parsePreview(makeResponse())

        #expect(result.feed.kind == .rss)
        #expect(result.feed.metadata.title == "Worker & Feed")
        #expect(result.feed.entries.count == 1)
        #expect(result.feed.entries.first?.title == "Richer duplicate title")
        #expect(result.diagnostics.rejectedEntries.count == 1)
        #expect(probe.didStartPayloadPreparation == false)
    }

    @Test
    func previewPropagatesCancellationFromActualXMLCallbackWithoutPreparingPayloads() async {
        let probe = FeedParsingExecutionProbe()
        let worker = FeedParsingWorker(
            pipeline: { response in
                try FeedParserService.parsePipelineResult(
                    response,
                    xmlCancellationProbe: probe.cancelFromXMLCallback
                )
            },
            payloadPreparation: { _, _ in
                probe.recordPayloadPreparationStart()
                return []
            }
        )

        await #expect(throws: CancellationError.self) {
            try await worker.parsePreview(makeResponse())
        }
        #expect(probe.didCancelFromXMLCallbackOffMainThread)
        #expect(probe.didStartPayloadPreparation == false)
    }

    @Test(arguments: WorkerEntryCancellationStage.previewStages)
    func cancellingPreviewDuringActualEntryProcessingReturnsCancellationError(
        stage: WorkerEntryCancellationStage
    ) async throws {
        let gate = WorkerEntryCancellationGate(target: stage)
        let worker = FeedParsingWorker(
            pipeline: { response in
                try FeedParserService.parsePipelineResult(
                    response,
                    entryProgressProbe: gate.recordEntryProgress
                )
            }
        )
        let task = Task {
            try await worker.parsePreview(makeCancellationResponse())
        }

        try await gate.waitUntilStarted()
        task.cancel()
        gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(gate.didRunActualWorkOffMainThread)
        #expect(gate.maximumProcessedEntryCount > 0)
        #expect(
            gate.maximumProcessedEntryCount
                <= FeedParsingCancellationPolicy.entryCheckpointInterval
        )
    }

    @Test(arguments: WorkerEntryCancellationStage.allCases)
    func cancellingRefreshDuringActualEntryProcessingReturnsCancellationError(
        stage: WorkerEntryCancellationStage
    ) async throws {
        let gate = WorkerEntryCancellationGate(target: stage)
        let worker = FeedParsingWorker(
            pipeline: { response in
                try FeedParserService.parsePipelineResult(
                    response,
                    entryProgressProbe: gate.recordEntryProgress
                )
            },
            payloadPreparation: { entries, fetchedAt in
                try ArticleUpsertPayload.makeAllPrepared(
                    entries: entries,
                    fetchedAt: fetchedAt,
                    materializationProbe: gate.recordPayloadMaterialization
                )
            }
        )
        let task = Task {
            try await worker.parseRefresh(makeCancellationResponse())
        }

        try await gate.waitUntilStarted()
        task.cancel()
        gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(gate.didRunActualWorkOffMainThread)
        #expect(gate.maximumProcessedEntryCount > 0)
        #expect(
            gate.maximumProcessedEntryCount
                <= FeedParsingCancellationPolicy.entryCheckpointInterval
        )
    }

    private func makeResponse() -> FeedResponse {
        let url = URL(string: "https://example.com/worker.xml")!
        return FeedResponse(
            request: FeedRequest(feedID: UUID(), url: url),
            sourceURL: url,
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml"],
            body: Data(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <rss version="2.0">
                  <channel>
                    <title>  Worker &amp; Feed  </title>
                    <link>https://example.com/</link>
                    <item>
                      <title>Duplicate</title>
                      <link>https://example.com/articles/1</link>
                      <guid>duplicate-guid</guid>
                      <description>Summary</description>
                    </item>
                    <item>
                      <title>Richer duplicate title</title>
                      <link>https://example.com/articles/1</link>
                      <guid>duplicate-guid</guid>
                      <description>Longer duplicate summary</description>
                      <pubDate>Tue, 02 Jan 2024 10:15:30 +0000</pubDate>
                    </item>
                    <item></item>
                  </channel>
                </rss>
                """.utf8
            )
        )
    }

    private func makeCancellationResponse() -> FeedResponse {
        let url = URL(string: "https://example.com/worker-cancellation.xml")!
        let itemXML = (0..<65).map { index in
            """
            <item>
              <title>Cancellation entry \(index)</title>
              <link>https://example.com/articles/cancellation-\(index)</link>
              <guid>cancellation-\(index)</guid>
              <description>Cancellation summary \(index)</description>
            </item>
            """
        }
        .joined(separator: "\n")
        return FeedResponse(
            request: FeedRequest(feedID: UUID(), url: url),
            sourceURL: url,
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml"],
            body: Data(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <rss version="2.0">
                  <channel>
                    <title>Cancellation Feed</title>
                    <link>https://example.com/</link>
                    \(itemXML)
                  </channel>
                </rss>
                """.utf8
            )
        )
    }
}

private final class FeedParsingExecutionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var pipelineRanOnMainThread = true
    private var payloadPreparationStarted = false
    private var payloadPreparationRanOnMainThread = true
    private var xmlCancellationCallbackInvoked = false
    private var xmlCancellationCallbackRanOnMainThread = true

    var didRunPipelineOffMainThread: Bool {
        lock.withLock { started && pipelineRanOnMainThread == false }
    }

    var didRunPayloadPreparationOffMainThread: Bool {
        lock.withLock {
            payloadPreparationStarted && payloadPreparationRanOnMainThread == false
        }
    }

    var didStartPayloadPreparation: Bool {
        lock.withLock { payloadPreparationStarted }
    }

    var didCancelFromXMLCallbackOffMainThread: Bool {
        lock.withLock {
            xmlCancellationCallbackInvoked && xmlCancellationCallbackRanOnMainThread == false
        }
    }

    func recordPipelineStart() {
        lock.withLock {
            started = true
            pipelineRanOnMainThread = Thread.isMainThread
        }
    }

    func recordPayloadPreparationStart() {
        lock.withLock {
            payloadPreparationStarted = true
            payloadPreparationRanOnMainThread = Thread.isMainThread
        }
    }

    func cancelFromXMLCallback() -> Bool {
        lock.withLock {
            xmlCancellationCallbackInvoked = true
            xmlCancellationCallbackRanOnMainThread = Thread.isMainThread
        }
        return true
    }
}

enum WorkerEntryCancellationStage: CaseIterable, Sendable {
    case normalization
    case diagnostics
    case deduplication
    case filtering
    case payloadMaterialization

    static let previewStages: [Self] = [
        .normalization,
        .diagnostics,
        .deduplication,
        .filtering
    ]

    var entryStage: FeedParsingEntryStage? {
        switch self {
        case .normalization:
            .normalization
        case .diagnostics:
            .diagnostics
        case .deduplication:
            .deduplication
        case .filtering:
            .filtering
        case .payloadMaterialization:
            nil
        }
    }
}

private final class WorkerEntryCancellationGate: @unchecked Sendable {
    private enum WaitError: Error {
        case timedOut
    }

    private let condition = NSCondition()
    private let target: WorkerEntryCancellationStage
    private var started = false
    private var released = false
    private var ranOnMainThread = true
    private var maximumProcessedCount = 0

    init(target: WorkerEntryCancellationStage) {
        self.target = target
    }

    var didRunActualWorkOffMainThread: Bool {
        condition.withLock { started && ranOnMainThread == false }
    }

    var maximumProcessedEntryCount: Int {
        condition.withLock { maximumProcessedCount }
    }

    func recordEntryProgress(
        _ stage: FeedParsingEntryStage,
        _ processedEntryCount: Int
    ) {
        guard stage == target.entryStage,
              processedEntryCount > 0 else {
            return
        }
        waitForRelease(processedEntryCount: processedEntryCount)
    }

    func recordPayloadMaterialization(
        _ materializedPayloadCount: Int,
        _: ArticleUpsertPayload
    ) {
        guard target == .payloadMaterialization,
              materializedPayloadCount > 0 else {
            return
        }
        waitForRelease(processedEntryCount: materializedPayloadCount)
    }

    func waitUntilStarted() async throws {
        for _ in 0..<1_000 {
            if condition.withLock({ started }) {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw WaitError.timedOut
    }

    func release() {
        condition.withLock {
            released = true
            condition.broadcast()
        }
    }

    private func waitForRelease(processedEntryCount: Int) {
        condition.lock()
        maximumProcessedCount = max(maximumProcessedCount, processedEntryCount)
        guard started == false else {
            condition.unlock()
            return
        }
        started = true
        ranOnMainThread = Thread.isMainThread
        condition.broadcast()
        while released == false {
            condition.wait()
        }
        condition.unlock()
    }
}
