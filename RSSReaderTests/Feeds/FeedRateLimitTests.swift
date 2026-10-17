import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Rate Limit")
@MainActor
struct FeedRateLimitTests {
    private let now = Date(timeIntervalSince1970: 1_791_712_800)

    @Test
    func retryHintsAreValidatedAndPreferRetryAfter() {
        let cases: [([String: String], TimeInterval?)] = [
            (["Retry-After": "60", "x-ratelimit-reset": "5"], 60),
            (["retry-after": "0"], 0),
            (["x-ratelimit-reset": " 12.5 "], 12.5),
            ([:], nil), (["Retry-After": "invalid", "x-ratelimit-reset": "5"], nil),
            (["Retry-After": "-1"], nil), (["Retry-After": "NaN"], nil),
            (["Retry-After": "1e9"], nil), (["Retry-After": "999999999999999999999999"], nil),
            (["x-ratelimit-reset": "infinity"], nil), (["x-ratelimit-reset": "-5"], nil),
            (["x-ratelimit-reset": "604801"], nil)
        ]
        for (headers, delay) in cases {
            let response = HTTPResponse(url: URL(string: "https://www.reddit.com/r/apple/.rss")!, statusCode: 429, headers: headers, body: Data())
            #expect(FeedHTTPResponseDiagnostics.retryAt(for: response, now: now) == delay.map { now.addingTimeInterval($0) })
        }
        let generic = HTTPResponse(url: URL(string: "https://example.com/feed")!, statusCode: 429, headers: ["x-ratelimit-reset": "10"], body: Data())
        #expect(FeedHTTPResponseDiagnostics.retryAt(for: generic, now: now) == nil)
    }

    @Test
    func retryAfterAcceptsHTTPDateAndClampsPastDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        for delay: TimeInterval in [-30, 45] {
            let response = HTTPResponse(url: URL(string: "https://example.com/feed")!, statusCode: 429, headers: ["Retry-After": formatter.string(from: now.addingTimeInterval(delay))], body: Data())
            #expect(FeedHTTPResponseDiagnostics.retryAt(for: response, now: now) == now.addingTimeInterval(max(0, delay)))
        }
    }

    @Test
    func fetcherDoesNotAutomaticallyRetry429AndKeepsHTTPCodeInLog() async throws {
        let client = ScriptedHTTPClient(steps: [.response(statusCode: 429, headers: [:], body: "")])
        let logs = RateLimitLogRecorder()
        let fetcher = FeedFetcher(httpClient: client, retryPolicy: FeedRetryPolicy(maxAttempts: 3, baseDelayNanoseconds: 0), logSink: { await logs.append($0) })
        do {
            _ = try await fetcher.fetch(FeedRequest(feedID: UUID(), url: URL(string: "https://www.reddit.com/r/apple/.rss?token=secret")!))
            Issue.record("Expected 429")
        } catch let error as FeedFetchError {
            #expect(error == .rateLimited(retryAt: nil, responseURL: "https://www.reddit.com/r/apple/.rss"))
        }
        #expect(await client.recordedRequests().count == 1)
        let entries = await logs.entries
        #expect(entries.count == 1)
        #expect(entries.first?.httpCode == 429)
        #expect(entries.first?.message?.contains("secret") == false)
    }
}

private actor RateLimitLogRecorder {
    var entries: [FeedFetchLogEntry] = []
    func append(_ entry: FeedFetchLogEntry) { entries.append(entry) }
}
