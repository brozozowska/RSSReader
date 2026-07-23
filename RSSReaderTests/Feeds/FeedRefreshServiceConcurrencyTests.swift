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

    @Test
    func cancellingCallerCancelsInFlightRefreshCleansRegistryAndAllowsRetry() async throws {
        let feedURL = "https://example.com/cancelled-in-flight-feed.xml"
        let responseBody = makeValidRSSFeedXML(
            channelTitle: "Retryable Feed",
            channelLink: "https://example.com/retryable/",
            language: "en",
            itemTitle: "Retryable Article",
            itemLink: "https://example.com/retryable/articles/1",
            itemGUID: "retryable-article-1",
            itemDescription: "Readable retry summary",
            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
        )
        let client = ScriptedHTTPClient(
            steps: [
                .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: responseBody,
                    delayNanoseconds: 5_000_000_000
                ),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: responseBody
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        let refreshTask = Task { @MainActor in
            await harness.service.refresh(feedID: feed.id)
        }

        while await client.recordedRequests().isEmpty {
            await Task.yield()
        }
        refreshTask.cancel()

        let cancelledResult = await refreshTask.value

        #expect(cancelledResult.status == .cancelled)
        #expect(harness.service.inFlightRefreshTasks[feed.id] == nil)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)

        let retryResult = await harness.service.refresh(feedID: feed.id)

        #expect(retryResult.status == .fetched)
        #expect(harness.service.inFlightRefreshTasks[feed.id] == nil)
        #expect(await client.recordedRequests().count == 2)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).count == 1)
    }
}
