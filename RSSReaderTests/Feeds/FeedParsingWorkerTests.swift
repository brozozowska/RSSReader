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

        let result = try await worker.parse(makeResponse(), fetchedAt: fetchedAt)

        #expect(probe.didRunPipelineOffMainThread)
        #expect(probe.didRunPayloadPreparationOffMainThread)
        #expect(result.feed.kind == .rss)
        #expect(result.feed.metadata.title == "Worker & Feed")
        #expect(result.feed.entries.count == 1)
        #expect(result.feed.entries.first?.title == "Richer duplicate title")
        #expect(result.diagnostics.rejectedEntries.count == 1)
        let payload = try #require(result.articlePayloads.first)
        #expect(result.articlePayloads.count == result.feed.entries.count)
        #expect(payload.title == "Richer duplicate title")
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

        let result = try await worker.parse(
            makeResponse(),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let payload = try #require(result.articlePayloads.first)
        #expect(payload.publishedAt == normalizedPublishedAt)
    }

    @Test
    func cancellingCallerCancelsDetachedParsingTaskAndReturnsCancellationError() async throws {
        let probe = FeedParsingExecutionProbe()
        let worker = FeedParsingWorker(
            pipeline: { _ in
                probe.recordPipelineStart()
                while Task.isCancelled == false {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                probe.recordCancellation()
                throw CancellationError()
            }
        )
        let task = Task {
            try await worker.parse(makeResponse())
        }

        try await probe.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(probe.didRunPipelineOffMainThread)
        #expect(probe.didObserveCancellation)
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
}

private final class FeedParsingExecutionProbe: @unchecked Sendable {
    private enum WaitError: Error {
        case timedOut
    }

    private let lock = NSLock()
    private var started = false
    private var pipelineRanOnMainThread = true
    private var payloadPreparationStarted = false
    private var payloadPreparationRanOnMainThread = true
    private var observedCancellation = false

    var didRunPipelineOffMainThread: Bool {
        lock.withLock { started && pipelineRanOnMainThread == false }
    }

    var didRunPayloadPreparationOffMainThread: Bool {
        lock.withLock {
            payloadPreparationStarted && payloadPreparationRanOnMainThread == false
        }
    }

    var didObserveCancellation: Bool {
        lock.withLock { observedCancellation }
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

    func recordCancellation() {
        lock.withLock {
            observedCancellation = true
        }
    }

    func waitUntilStarted() async throws {
        for _ in 0..<1_000 {
            if lock.withLock({ started }) {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }

        throw WaitError.timedOut
    }
}
