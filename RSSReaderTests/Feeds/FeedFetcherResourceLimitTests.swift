import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Fetcher Resource Limits")
@MainActor
struct FeedFetcherResourceLimitTests {
    @Test
    func mapsHTTPBodyLimitToTypedNonTransientFeedTransportError() async throws {
        let maximumBytes = AppResourceBudgetContract.current.feedXML.body.maximumCompressedBodyBytes
        let actualBytes = maximumBytes + 1
        let client = ScriptedHTTPClient(
            steps: [
                .responseBodyTooLarge(
                    maximumBytes: maximumBytes,
                    actualBytes: actualBytes
                )
            ]
        )
        let fetcher = FeedFetcher(
            httpClient: client,
            retryPolicy: FeedRetryPolicy(
                maxAttempts: 3,
                baseDelayNanoseconds: 0
            )
        )
        let request = FeedRequest(
            feedID: UUID(),
            url: URL(string: "https://example.com/feed.xml")!
        )

        do {
            _ = try await fetcher.fetch(request)
            Issue.record("Expected resource limit failure")
        } catch let error as FeedFetchError {
            #expect(
                error == .transport(
                    .responseBodyTooLarge(
                        maximumBytes: maximumBytes,
                        actualBytes: actualBytes
                    )
                )
            )
        } catch {
            Issue.record("Expected FeedFetchError, got \(error)")
        }

        let recordedRequests = await client.recordedRequests()
        #expect(recordedRequests.count == 1)
        #expect(recordedRequests.first?.maximumResponseBodyBytes == maximumBytes)
    }
}
