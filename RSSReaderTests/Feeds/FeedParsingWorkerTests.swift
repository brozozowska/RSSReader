import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Parsing Worker")
@MainActor
struct FeedParsingWorkerTests {
    @Test
    func workerRunsCompletePipelineOffMainActorAndReturnsSendableResult() async throws {
        let probe = FeedParsingExecutionProbe()
        let worker = FeedParsingWorker { response in
            probe.recordStart()
            return try FeedParserService.parsePipelineResult(response)
        }

        let result = try await worker.parse(makeResponse())

        #expect(probe.didRunOffMainThread)
        #expect(result.feed.kind == .rss)
        #expect(result.feed.metadata.title == "Worker & Feed")
        #expect(result.feed.entries.count == 1)
        #expect(result.feed.entries.first?.title == "Richer duplicate title")
        #expect(result.diagnostics.rejectedEntries.count == 1)
    }

    @Test
    func cancellingCallerCancelsDetachedParsingTaskAndReturnsCancellationError() async throws {
        let probe = FeedParsingExecutionProbe()
        let worker = FeedParsingWorker { _ in
            probe.recordStart()
            while Task.isCancelled == false {
                Thread.sleep(forTimeInterval: 0.001)
            }
            probe.recordCancellation()
            throw CancellationError()
        }
        let task = Task {
            try await worker.parse(makeResponse())
        }

        try await probe.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(probe.didRunOffMainThread)
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
    private var ranOnMainThread = true
    private var observedCancellation = false

    var didRunOffMainThread: Bool {
        lock.withLock { started && ranOnMainThread == false }
    }

    var didObserveCancellation: Bool {
        lock.withLock { observedCancellation }
    }

    func recordStart() {
        lock.withLock {
            started = true
            ranOnMainThread = Thread.isMainThread
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
