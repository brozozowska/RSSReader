import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Concurrency")
@MainActor
struct FeedRefreshServiceConcurrencyTests {
    @Test
    func concurrentRefreshOfSameFeedSharesInFlightTaskAndAvoidsDuplicateSideEffects() async throws {
        let feedURL = "https://example.com/concurrent-feed.xml"
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .delayedResponse(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8",
                        "ETag": "\"etag-concurrent\""
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Concurrent Feed",
                        channelLink: "https://example.com/concurrent/",
                        language: "en",
                        itemTitle: "Concurrent Article",
                        itemLink: "https://example.com/concurrent/articles/1",
                        itemGUID: "concurrent-article-1",
                        itemDescription: "Readable concurrent summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    ),
                    delayNanoseconds: 200_000_000
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = try harness.insertFeeds(urls: [feedURL]).first
        let requiredFeed = try #require(feed)

        let firstTask = Task { @MainActor in
            await harness.service.refresh(feedID: requiredFeed.id)
        }
        let secondTask = Task { @MainActor in
            await harness.service.refresh(feedID: requiredFeed.id)
        }

        let firstResult = await firstTask.value
        let secondResult = await secondTask.value

        #expect(firstResult.status == .fetched)
        #expect(secondResult.status == .fetched)
        #expect(firstResult.upsertedEntryCount == 1)
        #expect(secondResult.upsertedEntryCount == 1)
        #expect(firstResult.finishedAt == secondResult.finishedAt)

        let requests = await client.recordedRequests()
        #expect(requests.count == 1)

        let articles = try harness.articleRepository.fetchArticles(feedID: requiredFeed.id)
        #expect(articles.count == 1)

        let logs = try harness.feedFetchLogRepository.fetchLogs(feedID: requiredFeed.id, limit: nil)
        #expect(logs.count == 1)
        #expect(logs.first?.status == "fetched")
    }
}
