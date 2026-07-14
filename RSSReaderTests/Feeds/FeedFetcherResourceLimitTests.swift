import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Fetcher Resource Limits")
@MainActor
struct FeedFetcherResourceLimitTests {
    @Test
    func rejectsOversizedXMLReturnedByNonBoundedHTTPClientWithoutRetry() async throws {
        let maximumBytes = AppResourceBudgetContract.current.feedXML.body.maximumCompressedBodyBytes
        let client = ScriptedHTTPClient(
            steps: [
                .dataResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml"],
                    body: Data(repeating: 0x20, count: Int(maximumBytes + 1))
                )
            ]
        )
        let fetcher = FeedFetcher(
            httpClient: client,
            retryPolicy: FeedRetryPolicy(maxAttempts: 3, baseDelayNanoseconds: 0)
        )

        do {
            _ = try await fetcher.fetch(
                FeedRequest(
                    feedID: UUID(),
                    url: URL(string: "https://example.com/oversized.xml")!
                )
            )
            Issue.record("Expected oversized feed failure")
        } catch let error as FeedFetchError {
            #expect(
                error == .transport(
                    .responseBodyTooLarge(
                        maximumBytes: maximumBytes,
                        actualBytes: maximumBytes + 1
                    )
                )
            )
        } catch {
            Issue.record("Expected FeedFetchError, got \(error)")
        }

        #expect(await client.recordedRequests().count == 1)
    }

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
