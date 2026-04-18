import Foundation
import SwiftUI
import SwiftData
import Testing
@testable import RSSReader

@MainActor
struct RSSReaderTests {
    @Test
    func singleFeedRefreshFetchedPersistsArticlesMetadataAndFetchState() async throws {
        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8",
                            "ETag": "\"etag-new\"",
                            "Last-Modified": "Tue, 02 Jan 2024 12:00:00 GMT"
                        ],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Updated Feed Title",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Article One",
                            itemLink: "https://example.com/articles/1",
                            itemGUID: "article-1",
                            itemDescription: "Readable summary",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )

        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Old Feed Title",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"etag-old\"",
            lastModifiedHeader: "Mon, 01 Jan 2024 12:00:00 GMT",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        #expect(result.processedEntryCount == 1)
        #expect(result.upsertedEntryCount == 1)
        #expect(result.rejectedEntryCount == 0)
        #expect(result.errorDescription == nil)

        let fetchedFeed = try harness.fetchFeed(id: feed.id)
        let refreshedFeed = try #require(fetchedFeed)
        #expect(refreshedFeed.title == "Updated Feed Title")
        #expect(refreshedFeed.siteURL == "https://example.com/")
        #expect(refreshedFeed.language == "en")
        #expect(refreshedFeed.kind == .rss)
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != oldSuccessAt)
        #expect(refreshedFeed.lastETag == "\"etag-new\"")
        #expect(refreshedFeed.lastModifiedHeader == "Tue, 02 Jan 2024 12:00:00 GMT")
        #expect(refreshedFeed.lastSyncError == nil)

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Article One")
        #expect(articles.first?.isDeletedAtSource == false)

        let fetchedLog = try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id)
        let latestLog = try #require(fetchedLog)
        #expect(latestLog.status == "fetched")
        #expect(latestLog.httpCode == 200)

        let requests = await harness.httpClient.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.headers["If-None-Match"] == "\"etag-old\"")
        #expect(requests.first?.headers["If-Modified-Since"] == "Mon, 01 Jan 2024 12:00:00 GMT")
    }

    @Test
    func singleFeedRefreshNotModifiedUpdatesFetchStateWithoutParsingPipeline() async throws {
        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .response(
                        statusCode: 304,
                        headers: [
                            "ETag": "\"etag-304\"",
                            "Last-Modified": "Wed, 03 Jan 2024 12:00:00 GMT"
                        ],
                        body: ""
                    )
                ]
            )
        )

        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Stable Feed Title",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"etag-old\"",
            lastModifiedHeader: "Mon, 01 Jan 2024 12:00:00 GMT",
            lastSyncError: "Transient error"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .notModified)
        #expect(result.processedEntryCount == 0)
        #expect(result.upsertedEntryCount == 0)
        #expect(result.rejectedEntryCount == 0)
        #expect(result.errorDescription == nil)

        let fetchedFeed = try harness.fetchFeed(id: feed.id)
        let refreshedFeed = try #require(fetchedFeed)
        #expect(refreshedFeed.title == "Stable Feed Title")
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(refreshedFeed.lastETag == "\"etag-304\"")
        #expect(refreshedFeed.lastModifiedHeader == "Wed, 03 Jan 2024 12:00:00 GMT")
        #expect(refreshedFeed.lastSyncError == nil)

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.isEmpty)

        let fetchedLog = try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id)
        let latestLog = try #require(fetchedLog)
        #expect(latestLog.status == "not_modified")
        #expect(latestLog.httpCode == 304)

        let requests = await harness.httpClient.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.headers["If-None-Match"] == "\"etag-old\"")
        #expect(requests.first?.headers["If-Modified-Since"] == "Mon, 01 Jan 2024 12:00:00 GMT")
    }

    @Test
    func singleFeedRefreshFailedPersistsErrorWithoutWritingArticles() async throws {
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .response(
                        statusCode: 500,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: ""
                    )
                ]
            )
        )

        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Failing Feed",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"etag-old\"",
            lastModifiedHeader: "Mon, 01 Jan 2024 12:00:00 GMT"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .failed)
        #expect(result.processedEntryCount == 0)
        #expect(result.upsertedEntryCount == 0)
        #expect(result.rejectedEntryCount == 0)
        #expect(result.errorDescription?.contains("invalidStatusCode") == true)

        let fetchedFeed = try harness.fetchFeed(id: feed.id)
        let refreshedFeed = try #require(fetchedFeed)
        #expect(refreshedFeed.title == "Failing Feed")
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(refreshedFeed.lastSyncError?.contains("invalidStatusCode") == true)
        #expect(refreshedFeed.lastETag == "\"etag-old\"")
        #expect(refreshedFeed.lastModifiedHeader == "Mon, 01 Jan 2024 12:00:00 GMT")

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.isEmpty)

        let fetchedLog = try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id)
        let latestLog = try #require(fetchedLog)
        #expect(latestLog.status == "failed")
        #expect(latestLog.httpCode == 500)
        #expect(latestLog.message?.contains("invalidStatusCode") == true)
    }

    @Test
    func singleFeedRefreshCancelledReturnsCancelledWithoutPersistingFailureState() async throws {
        let oldSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .cancelled
                ]
            )
        )

        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Cancellable Feed",
            lastSuccessfulFetchAt: oldSuccessAt,
            lastETag: "\"etag-old\"",
            lastModifiedHeader: "Mon, 01 Jan 2024 12:00:00 GMT",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .cancelled)
        #expect(result.processedEntryCount == 0)
        #expect(result.upsertedEntryCount == 0)
        #expect(result.rejectedEntryCount == 0)
        #expect(result.errorDescription == "Refresh cancelled")

        let fetchedFeed = try harness.fetchFeed(id: feed.id)
        let refreshedFeed = try #require(fetchedFeed)
        #expect(refreshedFeed.title == "Cancellable Feed")
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt == oldSuccessAt)
        #expect(refreshedFeed.lastSyncError == "Previous error")
        #expect(refreshedFeed.lastETag == "\"etag-old\"")
        #expect(refreshedFeed.lastModifiedHeader == "Mon, 01 Jan 2024 12:00:00 GMT")

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.isEmpty)

        let fetchedLog = try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id)
        let latestLog = try #require(fetchedLog)
        #expect(latestLog.status == "cancelled")
        #expect(latestLog.httpCode == nil)
        #expect(latestLog.message?.contains("Refresh cancelled") == true)
    }

    @Test
    func batchRefreshAggregatesPartialSuccessAndIndividualFailures() async throws {
        let feed1URL = "https://example.com/feed-1.xml"
        let feed2URL = "https://example.com/feed-2.xml"
        let feed3URL = "https://example.com/feed-3.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feed1URL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8",
                            "ETag": "\"etag-feed-1\""
                        ],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Feed One",
                            channelLink: "https://example.com/one/",
                            language: "en",
                            itemTitle: "Batch Article One",
                            itemLink: "https://example.com/one/articles/1",
                            itemGUID: "batch-article-1",
                            itemDescription: "Readable summary one",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    ),
                    feed2URL: .response(
                        statusCode: 304,
                        headers: [
                            "ETag": "\"etag-feed-2\"",
                            "Last-Modified": "Wed, 03 Jan 2024 12:00:00 GMT"
                        ],
                        body: ""
                    ),
                    feed3URL: .response(
                        statusCode: 500,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: ""
                    )
                ]
            )
        )

        let feeds = try harness.insertFeeds(urls: [feed1URL, feed2URL, feed3URL])

        let result = await harness.service.refreshFeeds(feeds.map(\.id))

        #expect(result.summary.totalFeedCount == 3)
        #expect(result.summary.fetchedCount == 1)
        #expect(result.summary.notModifiedCount == 1)
        #expect(result.summary.failedCount == 1)
        #expect(result.summary.cancelledCount == 0)
        #expect(result.errors.count == 1)
        #expect(result.failedResults.count == 1)
        #expect(result.results.map(\.status) == [.fetched, .notModified, .failed])
        #expect(result.errors.first?.feedID == feeds[2].id)
        #expect(result.errors.first?.message.contains("invalidStatusCode") == true)

        let feed1Articles = try harness.articleRepository.fetchArticles(feedID: feeds[0].id)
        #expect(feed1Articles.count == 1)

        let fetchedFeed2 = try harness.fetchFeed(id: feeds[1].id)
        let feed2State = try #require(fetchedFeed2)
        #expect(feed2State.lastETag == "\"etag-feed-2\"")

        let fetchedFeed3 = try harness.fetchFeed(id: feeds[2].id)
        let feed3State = try #require(fetchedFeed3)
        #expect(feed3State.lastSyncError?.contains("invalidStatusCode") == true)
    }

    @Test
    func batchRefreshRespectsDefaultConcurrencyLimit() async throws {
        let urls = (1...4).map { "https://example.com/concurrency-\($0).xml" }
        let responses = Dictionary(uniqueKeysWithValues: urls.enumerated().map { index, url in
            (
                url,
                ScriptedHTTPClient.Step.delayedResponse(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: Self.validRSSFeedXML(
                        channelTitle: "Concurrency Feed \(index + 1)",
                        channelLink: "https://example.com/\(index + 1)/",
                        language: "en",
                        itemTitle: "Concurrency Article \(index + 1)",
                        itemLink: "https://example.com/\(index + 1)/articles/1",
                        itemGUID: "concurrency-\(index + 1)",
                        itemDescription: "Readable summary \(index + 1)",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    ),
                    delayNanoseconds: 200_000_000
                )
            )
        })

        let client = ScriptedHTTPClient(responsesByURL: responses)
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)

        let result = await harness.service.refreshFeeds(feeds.map(\.id))

        #expect(result.summary.totalFeedCount == 4)
        #expect(result.summary.fetchedCount == 4)
        #expect(result.summary.failedCount == 0)
        #expect(result.summary.cancelledCount == 0)

        let maxConcurrentExecutions = await client.maxConcurrentExecutions()
        #expect(maxConcurrentExecutions <= 3)

        let requests = await client.recordedRequests()
        #expect(requests.count == 4)
    }

    @Test
    func batchRefreshCancellationReturnsPartialCancelledResults() async throws {
        let urls = (1...4).map { "https://example.com/cancel-\($0).xml" }
        let responses = Dictionary(uniqueKeysWithValues: urls.enumerated().map { index, url in
            (
                url,
                ScriptedHTTPClient.Step.delayedResponse(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: Self.validRSSFeedXML(
                        channelTitle: "Cancel Feed \(index + 1)",
                        channelLink: "https://example.com/cancel/\(index + 1)/",
                        language: "en",
                        itemTitle: "Cancel Article \(index + 1)",
                        itemLink: "https://example.com/cancel/\(index + 1)/articles/1",
                        itemGUID: "cancel-\(index + 1)",
                        itemDescription: "Readable summary \(index + 1)",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    ),
                    delayNanoseconds: 500_000_000
                )
            )
        })

        let client = ScriptedHTTPClient(responsesByURL: responses)
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)

        let task = Task { @MainActor in
            await harness.service.refreshFeeds(feeds.map(\.id))
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let result = await task.value

        #expect(result.summary.totalFeedCount > 0)
        #expect(result.summary.totalFeedCount < 4)
        #expect(result.summary.fetchedCount + result.summary.cancelledCount == result.summary.totalFeedCount)
        #expect(result.summary.failedCount == 0)
        #expect(result.summary.notModifiedCount == 0)

        let requests = await client.recordedRequests()
        #expect(requests.count <= 3)
    }

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
                    body: Self.validRSSFeedXML(
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
    func refreshUpdatesFeedMetadataAndMarksMissingArticlesAsDeletedAtSource() async throws {
        let feedURL = "https://example.com/reconcile-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Reconciled Feed Title",
                            channelLink: "https://example.com/reconciled/",
                            language: "fr",
                            itemTitle: "Current Article",
                            itemLink: "https://example.com/reconciled/articles/current",
                            itemGUID: "current-article",
                            itemDescription: "Current article summary",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )

        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        feed.title = "Stale Feed Title"
        feed.siteURL = "https://example.com/old/"
        feed.language = "en"
        feed.kind = .unknown
        try harness.saveModelContext()

        _ = try harness.insertArticle(
            feed: feed,
            externalID: "obsolete-article",
            guid: "obsolete-article",
            url: "https://example.com/reconciled/articles/obsolete",
            title: "Obsolete Article"
        )

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        #expect(result.upsertedEntryCount == 1)

        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.title == "Reconciled Feed Title")
        #expect(refreshedFeed.siteURL == "https://example.com/reconciled/")
        #expect(refreshedFeed.language == "fr")
        #expect(refreshedFeed.kind == .rss)

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.count == 2)

        let obsoleteArticle = try #require(articles.first { $0.externalID == "obsolete-article" })
        #expect(obsoleteArticle.isDeletedAtSource == true)

        let currentArticle = try #require(articles.first { $0.guid == "current-article" })
        #expect(currentArticle.isDeletedAtSource == false)
        #expect(currentArticle.title == "Current Article")
    }

    @Test
    func refreshReactivatesArticleWhenItReappearsInFeedPayload() async throws {
        let feedURL = "https://example.com/reappearing-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Reappearing Feed",
                            channelLink: "https://example.com/reappearing/",
                            language: "en",
                            itemTitle: "Revived Article",
                            itemLink: "https://example.com/reappearing/articles/revived",
                            itemGUID: "revived-article",
                            itemDescription: "Revived article summary",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )

        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        let refreshedEntryExternalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: feedURL,
                guid: "revived-article",
                articleURL: "https://example.com/reappearing/articles/revived",
                title: "Revived Article",
                publishedAt: FeedDateParsingService.parse("Tue, 02 Jan 2024 10:00:00 GMT")
            )
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: refreshedEntryExternalID,
            guid: "revived-article",
            url: "https://example.com/reappearing/articles/revived",
            title: "Stale Revived Article",
            isDeletedAtSource: true
        )

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        #expect(result.upsertedEntryCount == 1)

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.count == 1)

        let revivedArticle = try #require(articles.first)
        #expect(revivedArticle.externalID == refreshedEntryExternalID)
        #expect(revivedArticle.isDeletedAtSource == false)
        #expect(revivedArticle.title == "Revived Article")
    }

    @Test
    func articleStateReadUnreadTransitionUpdatesStateAndInteractionTimestamps() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-read.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "state-read-article",
            url: "https://example.com/state-read/articles/1",
            title: "State Read Article"
        )
        let baseTime = Date().addingTimeInterval(60)
        let readAt = baseTime
        let unreadAt = baseTime.addingTimeInterval(600)

        let readSnapshot = try harness.articleStateService.markAsRead(article: article, at: readAt)
        let unreadSnapshot = try harness.articleStateService.markAsUnread(article: article, at: unreadAt)

        #expect(readSnapshot.isRead == true)
        #expect(readSnapshot.readAt == readAt)
        #expect(readSnapshot.lastInteractionAt == readAt)
        #expect(readSnapshot.updatedAt == readAt)

        #expect(unreadSnapshot.isRead == false)
        #expect(unreadSnapshot.readAt == nil)
        #expect(unreadSnapshot.lastInteractionAt == unreadAt)
        #expect(unreadSnapshot.updatedAt == unreadAt)

        let persistedSnapshot = try harness.articleStateService.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        let state = try #require(persistedSnapshot)
        #expect(state.isRead == false)
        #expect(state.readAt == nil)
        #expect(state.lastInteractionAt == unreadAt)
        #expect(state.updatedAt == unreadAt)
    }

    @Test
    func articleStateToggleStarredTransitionsOnAndOffWithFreshTimestamps() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-star.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "state-star-article",
            url: "https://example.com/state-star/articles/1",
            title: "State Star Article"
        )
        let baseTime = Date().addingTimeInterval(60)
        let starredAt = baseTime
        let unstarredAt = baseTime.addingTimeInterval(300)

        let starredSnapshot = try harness.articleStateService.toggleStarred(article: article, at: starredAt)
        let unstarredSnapshot = try harness.articleStateService.toggleStarred(article: article, at: unstarredAt)

        #expect(starredSnapshot.isStarred == true)
        #expect(starredSnapshot.starredAt == starredAt)
        #expect(starredSnapshot.lastInteractionAt == starredAt)
        #expect(starredSnapshot.updatedAt == starredAt)

        #expect(unstarredSnapshot.isStarred == false)
        #expect(unstarredSnapshot.starredAt == nil)
        #expect(unstarredSnapshot.lastInteractionAt == unstarredAt)
        #expect(unstarredSnapshot.updatedAt == unstarredAt)
    }

    @Test
    func articleStateBulkMarkAllVisibleAsReadMarksArticlesAcrossFeeds() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/state-bulk-1.xml",
                "https://example.com/state-bulk-2.xml"
            ]
        )
        let firstArticle = try harness.insertArticle(
            feed: feeds[0],
            externalID: "bulk-article-1",
            url: "https://example.com/state-bulk-1/articles/1",
            title: "Bulk Article One"
        )
        let secondArticle = try harness.insertArticle(
            feed: feeds[0],
            externalID: "bulk-article-2",
            url: "https://example.com/state-bulk-1/articles/2",
            title: "Bulk Article Two"
        )
        let thirdArticle = try harness.insertArticle(
            feed: feeds[1],
            externalID: "bulk-article-3",
            url: "https://example.com/state-bulk-2/articles/1",
            title: "Bulk Article Three"
        )
        let actionAt = Date().addingTimeInterval(60)

        let snapshots = try harness.articleStateService.markAllVisibleAsRead(
            [firstArticle, secondArticle, thirdArticle],
            at: actionAt
        )

        #expect(snapshots.count == 3)
        #expect(snapshots.allSatisfy { $0.isRead })
        #expect(snapshots.allSatisfy { $0.readAt == actionAt })
        #expect(snapshots.allSatisfy { $0.lastInteractionAt == actionAt })
        #expect(snapshots.allSatisfy { $0.updatedAt == actionAt })

        let persistedSnapshots = try harness.articleStateService.fetchStateSnapshots(
            for: [firstArticle, secondArticle, thirdArticle]
        )
        #expect(persistedSnapshots.count == 3)
        #expect(Array(persistedSnapshots.values).allSatisfy { $0.isRead })
        #expect(persistedSnapshots.values.allSatisfy { $0.readAt == actionAt })
    }

    @Test
    func articleStateRejectsStaleTransitionWhenUpdatedAtIsOlderThanCurrentState() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-lww.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "state-lww-article",
            url: "https://example.com/state-lww/articles/1",
            title: "State LWW Article"
        )
        let newerTimestamp = Date().addingTimeInterval(120)
        let olderTimestamp = Date().addingTimeInterval(60)

        _ = try harness.articleStateService.markAsRead(article: article, at: newerTimestamp)
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: article.externalID,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                lastInteractionAt: olderTimestamp,
                updatedAt: olderTimestamp
            )
        )

        let persistedSnapshot = try harness.articleStateService.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        let state = try #require(persistedSnapshot)
        #expect(state.isRead == true)
        #expect(state.readAt == newerTimestamp)
        #expect(state.lastInteractionAt == newerTimestamp)
        #expect(state.updatedAt == newerTimestamp)
    }

    @Test
    func sourcesSidebarQuerySnapshotAggregatesUnreadAndStarredStateForFeeds() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/sidebar-feed-one.xml",
                "https://example.com/sidebar-feed-two.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)

        let unreadArticle = try harness.insertArticle(
            feed: firstFeed,
            externalID: "sidebar-unread",
            url: "https://example.com/articles/unread",
            title: "Unread Article"
        )
        let starredArticle = try harness.insertArticle(
            feed: secondFeed,
            externalID: "sidebar-starred",
            url: "https://example.com/articles/starred",
            title: "Starred Article"
        )
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "sidebar-read",
            url: "https://example.com/articles/read",
            title: "Read Article"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(feedID: secondFeed.id, articleExternalID: "sidebar-read", at: .now)
        _ = unreadArticle

        let snapshot = try harness.dependencies.sourcesSidebarQueryService?.fetchSnapshot()
        let resolvedSnapshot = try #require(snapshot)

        #expect(resolvedSnapshot.feeds.map(\.id) == feeds.map(\.id))
        #expect(resolvedSnapshot.feeds.map(\.unreadCount) == [1, 1])
        #expect(resolvedSnapshot.feeds.map(\.starredCount) == [0, 1])
        #expect(resolvedSnapshot.unreadSmartCount == 2)
        #expect(resolvedSnapshot.starredSmartCount == 1)
        #expect(resolvedSnapshot.starredFeedIDs == [secondFeed.id])
    }

    @Test
    func sidebarCountPresentationUsesUnreadCountersForAllItemsAndUnreadFilters() {
        let feed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Feed"),
            unreadCount: 3,
            starredCount: 2
        )
        let folder = FolderSidebarGroup(name: "Tech", feeds: [feed])

        #expect(
            SidebarCountPresentation.smartCount(
                for: .allItems,
                unreadSmartCount: 5,
                starredSmartCount: 2
            ) == 5
        )
        #expect(
            SidebarCountPresentation.smartCount(
                for: .unread,
                unreadSmartCount: 5,
                starredSmartCount: 2
            ) == 5
        )
        #expect(SidebarCountPresentation.feedCount(for: feed, filter: .allItems) == 3)
        #expect(SidebarCountPresentation.feedCount(for: feed, filter: .unread) == 3)
        #expect(SidebarCountPresentation.folderCount(for: folder, filter: .allItems) == 3)
        #expect(SidebarCountPresentation.folderCount(for: folder, filter: .unread) == 3)
    }

    @Test
    func sidebarCountPresentationUsesStarredCountersForStarredFilter() {
        let firstFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed-one.xml", title: "Feed One"),
            unreadCount: 4,
            starredCount: 1
        )
        let secondFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed-two.xml", title: "Feed Two"),
            unreadCount: 2,
            starredCount: 3
        )
        let folder = FolderSidebarGroup(name: "Tech", feeds: [firstFeed, secondFeed])

        #expect(
            SidebarCountPresentation.smartCount(
                for: .starred,
                unreadSmartCount: 6,
                starredSmartCount: 4
            ) == 4
        )
        #expect(SidebarCountPresentation.feedCount(for: firstFeed, filter: .starred) == 1)
        #expect(SidebarCountPresentation.feedCount(for: secondFeed, filter: .starred) == 3)
        #expect(SidebarCountPresentation.folderCount(for: folder, filter: .starred) == 4)
    }

    @Test
    func sidebarSubtitleFormatterReturnsSyncingTitleForSyncingState() {
        let formatter = SidebarSubtitleFormatter()

        #expect(formatter.text(for: .syncing) == "Syncing...")
    }

    @Test
    func sidebarSubtitleFormatterReturnsPlaceholderWhenNoRefreshDateIsAvailable() {
        let formatter = SidebarSubtitleFormatter()

        #expect(formatter.text(for: .idle(lastUpdatedAt: nil)) == "Not updated yet")
    }

    @Test
    func sidebarSubtitleFormatterFormatsTodayRefreshDate() {
        let formatter = SidebarSubtitleFormatter()
        let calendar = Calendar.current
        let now = Date()
        let refreshDate = calendar.date(
            bySettingHour: 9,
            minute: 41,
            second: 0,
            of: now
        ) ?? now

        let expectedText = "Today at \(refreshDate.formatted(date: .omitted, time: .shortened))"

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == expectedText)
    }

    @Test
    func sidebarSubtitleFormatterFormatsYesterdayRefreshDate() {
        let formatter = SidebarSubtitleFormatter()
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let refreshDate = calendar.date(
            bySettingHour: 21,
            minute: 15,
            second: 0,
            of: yesterday
        ) ?? yesterday

        let expectedText = "Yesterday at \(refreshDate.formatted(date: .omitted, time: .shortened))"

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == expectedText)
    }

    @Test
    func sidebarSubtitleFormatterFormatsOlderRefreshDateWithAbbreviatedDate() {
        let formatter = SidebarSubtitleFormatter()
        let refreshDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast

        let expectedText = refreshDate.formatted(date: .abbreviated, time: .shortened)

        #expect(formatter.text(for: .idle(lastUpdatedAt: refreshDate)) == expectedText)
    }

    @Test
    func sidebarToolbarStateMarksSyncingStateAndUsesSyncingSubtitle() {
        let state = SidebarToolbarState(refreshStatus: .syncing)

        #expect(state.subtitle == "Syncing...")
        #expect(state.isSyncing)
    }

    @Test
    func sidebarToolbarStateMarksIdleStateAndUsesFormattedSubtitle() {
        let refreshDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        let formatter = SidebarSubtitleFormatter()
        let expectedSubtitle = formatter.text(for: .idle(lastUpdatedAt: refreshDate))
        let state = SidebarToolbarState(refreshStatus: .idle(lastUpdatedAt: refreshDate))

        #expect(state.subtitle == expectedSubtitle)
        #expect(state.isSyncing == false)
    }

    @Test
    func sidebarScreenStateExposesPrimaryLoadingStateThroughDerivedViewState() {
        let state = SidebarScreenState()

        let viewState = state.derivedViewState(
            filter: .allItems,
            expandedFolderNames: []
        )

        #expect(state.phase == .loading)
        #expect(viewState.primaryLoadingState?.title == "Loading Sources")
        #expect(viewState.placeholder == nil)
        #expect(viewState.shouldDisableScrolling)
        #expect(viewState.smartRows.isEmpty)
    }

    @Test
    func sidebarScreenStateBuildsLoadedDerivedViewStateFromSnapshot() {
        let feed = Feed(
            id: UUID(),
            url: "https://www.theverge.com/rss/index.xml",
            title: "The Verge",
            folder: Folder(name: "Tech")
        )
        let feedSidebarItem = FeedSidebarItem(
            feed: feed,
            unreadCount: 2,
            starredCount: 1
        )
        let snapshot = SourcesSidebarSnapshotDTO(
            feeds: [feedSidebarItem],
            unreadSmartCount: 2,
            starredSmartCount: 1,
            starredFeedIDs: [feed.id]
        )
        let state = SidebarScreenState.previewLoaded(snapshot: snapshot)

        let viewState = state.derivedViewState(
            filter: .allItems,
            expandedFolderNames: ["Tech"]
        )

        #expect(state.phase == .loaded)
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.smartRows.map(\.item) == [.allItems])
        #expect(viewState.smartRows.first?.count == 2)
        #expect(viewState.folderRows.count == 2)
        #expect(viewState.ungroupedFeedRows.isEmpty)
        #expect(viewState.shouldDisableScrolling == false)

        guard case .folder(let folderRow)? = viewState.folderRows.first else {
            Issue.record("Expected first folder row in SidebarScreenDerivedViewState")
            return
        }
        #expect(folderRow.name == "Tech")
        #expect(folderRow.isExpanded)

        guard case .feed(let feedRow)? = viewState.folderRows.last else {
            Issue.record("Expected nested feed row in SidebarScreenDerivedViewState")
            return
        }
        #expect(feedRow.title == "The Verge")
        #expect(feedRow.isIndented)
    }

    @Test
    func articleScreenStateStartsWithNoSelectionPlaceholder() {
        let state = ArticleScreenState()
        let viewState = state.derivedViewState()

        #expect(state.phase == .noSelection)
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder?.title == "No Article Selected")
        #expect(viewState.toolbarActions.showsShareAction == false)
        #expect(viewState.toolbarActions.showsBottomActions == false)
    }

    @Test
    func articleScreenStateExposesPrimaryLoadingStateThroughDerivedViewState() {
        var state = ArticleScreenState()

        state.beginLoading(articleID: UUID())

        let viewState = state.derivedViewState()

        #expect(state.phase == .loading)
        #expect(viewState.primaryLoadingState?.title == "Loading Article")
        #expect(viewState.content == nil)
        #expect(viewState.placeholder == nil)
    }

    @Test
    func articleScreenStateBuildsLoadedContentAndToolbarActions() {
        var state = ArticleScreenState()
        let article = makeReaderArticleDTO(
            summary: nil,
            contentText: "Rendered body text",
            isRead: true,
            isStarred: true
        )

        state.applyLoadedArticle(article)
        let viewState = state.derivedViewState()

        #expect(state.phase == .loaded)
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.content?.header.title == article.title)
        #expect(viewState.content?.header.feedTitle == article.feedTitle)
        #expect(viewState.content?.header.author == article.author)
        #expect(viewState.content?.body.blocks == [.paragraph("Rendered body text")])
        #expect(viewState.content?.body.source == .contentText)
        #expect(viewState.content?.body.readerMode == .embedded)
        #expect(viewState.toolbarActions.showsShareAction)
        #expect(viewState.toolbarActions.isShareEnabled)
        #expect(viewState.toolbarActions.showsBottomActions)
        #expect(viewState.toolbarActions.bottomActions?.readToggleTitle == "Mark Unread")
        #expect(viewState.toolbarActions.bottomActions?.readToggleSystemImage == "circle.slash")
        #expect(viewState.toolbarActions.bottomActions?.starTitle == "Unstar")
        #expect(viewState.toolbarActions.bottomActions?.starSystemImage == "star.slash")
    }

    @Test
    func articleScreenContentHeaderFormatsFieldsInPublishedTitleAuthorFeedOrder() {
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                feedTitle: "THECODE.MEDIA",
                author: "Юлия Зубарева",
                publishedAt: publishedAt
            )
        )

        #expect(content.header.publishedAtText == ArticleScreenDateFormatter.string(from: publishedAt))
        #expect(content.header.title == "Article")
        #expect(content.header.author == "Юлия Зубарева")
        #expect(content.header.feedTitle == "THECODE.MEDIA")
    }

    @Test
    func articleScreenContentHeaderHidesBlankMetadataAndFallsBackForBlankTitle() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                feedTitle: "   ",
                title: "   ",
                author: " \n ",
                publishedAt: nil
            )
        )

        #expect(content.header.publishedAtText == nil)
        #expect(content.header.title == "Untitled Article")
        #expect(content.header.author == nil)
        #expect(content.header.feedTitle == nil)
    }

    @Test
    func articleScreenStateUsesExistingRenderingPriorityForBodyContent() {
        var state = ArticleScreenState()
        let article = makeReaderArticleDTO(
            summary: "Summary copy",
            contentHTML: "<p>HTML body</p>",
            contentText: "Longer content text"
        )

        state.applyLoadedArticle(article)

        #expect(state.derivedViewState().content?.body.blocks == [.paragraph("HTML body")])
        #expect(state.derivedViewState().content?.body.source == .contentHTML)
    }

    @Test
    func articleScreenContentRendererParsesHTMLParagraphsAndInlineImagesInOrder() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                summary: "Short summary",
                contentHTML: """
                <p>First paragraph.</p>
                <img src="https://example.com/images/inline.png">
                <p>Second <strong>paragraph</strong>.</p>
                """,
                contentText: "Plain text fallback"
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph("First paragraph."),
                .image(URL(string: "https://example.com/images/inline.png")!),
                .paragraph("Second paragraph.")
            ]
        )
        #expect(content.body.source == .contentHTML)
    }

    @Test
    func articleScreenContentRendererUsesSummaryWithFallbackNoticeWhenFullBodyIsUnavailable() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                summary: """
                Short summary paragraph.

                Another summary paragraph.
                """,
                contentHTML: nil,
                contentText: nil
            )
        )

        #expect(
            content.body.blocks == [
                .paragraph("Short summary paragraph."),
                .paragraph("Another summary paragraph."),
                .fallbackNotice("This source only provides a summary, not the full article body.")
            ]
        )
        #expect(content.body.source == .summary)
    }

    @Test
    func articleScreenContentRendererBuildsGracefulFallbackWhenFeedHasNoBodyContent() {
        let content = ArticleScreenContentState(
            article: makeReaderArticleDTO(
                summary: nil,
                contentHTML: nil,
                contentText: nil
            )
        )

        #expect(
            content.body.blocks == [
                .fallbackNotice("Full article content is unavailable in this feed.")
            ]
        )
        #expect(content.body.source == .empty)
        #expect(content.body.readerMode == .embedded)
    }

    @Test
    func articleScreenBodyContentStateDefinesFutureFullTextExtensionPoint() {
        let extractedContent = ArticleScreenBodyContentState.extractedFullText(
            blocks: [
                .paragraph("Extracted full text paragraph.")
            ]
        )

        #expect(extractedContent.source == .fullTextExtracted)
        #expect(extractedContent.readerMode == .fullText)
        #expect(extractedContent.blocks == [.paragraph("Extracted full text paragraph.")])
    }

    @Test
    func articleScreenToolbarActionsExposeShareURLOnlyWhenArticleHasValidURL() {
        var loadedState = ArticleScreenState()
        loadedState.applyLoadedArticle(
            makeReaderArticleDTO(
                canonicalURL: "https://example.com/articles/shared"
            )
        )
        let loadedToolbarActions = loadedState.derivedViewState().toolbarActions
        #expect(loadedToolbarActions.isShareEnabled)
        #expect(loadedToolbarActions.shareURL?.absoluteString == "https://example.com/articles/shared")

        var invalidURLState = ArticleScreenState()
        invalidURLState.applyLoadedArticle(
            makeReaderArticleDTO(
                articleURL: "not a valid url",
                canonicalURL: nil
            )
        )
        let invalidToolbarActions = invalidURLState.derivedViewState().toolbarActions
        #expect(invalidToolbarActions.isShareEnabled == false)
        #expect(invalidToolbarActions.shareURL == nil)
    }

    @Test
    func articleScreenBottomActionsEnableAppBrowserOnlyWhenArticleHasValidExternalURL() {
        var loadedState = ArticleScreenState()
        loadedState.applyLoadedArticle(
            makeReaderArticleDTO(
                canonicalURL: "https://example.com/articles/openable"
            )
        )

        let loadedBottomActions = loadedState.derivedViewState().toolbarActions.bottomActions
        #expect(loadedBottomActions?.openInAppBrowserTitle == "Open in App-Browser")
        #expect(loadedBottomActions?.openInAppBrowserSystemImage == "safari")
        #expect(loadedBottomActions?.canOpenInAppBrowser == true)

        var invalidURLState = ArticleScreenState()
        invalidURLState.applyLoadedArticle(
            makeReaderArticleDTO(
                articleURL: "invalid-url",
                canonicalURL: nil
            )
        )

        let invalidBottomActions = invalidURLState.derivedViewState().toolbarActions.bottomActions
        #expect(invalidBottomActions?.canOpenInAppBrowser == false)
    }

    @Test
    func articleScreenControllerLoadsReaderArticleForCurrentSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-load.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-load",
            url: "https://example.com/articles/article-screen-load",
            title: "Article Screen Load"
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.derivedViewState().content?.header.title == "Article Screen Load")
        #expect(controller.screenState.toolbarActions.showsBottomActions)
    }

    @Test
    func articleScreenControllerMarksArticleAsReadOnOpenWhenSettingIsEnabled() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                markAsReadOnOpen: true,
                updatedAt: .distantPast
            )
        )
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-mark-on-open.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-mark-on-open",
            url: "https://example.com/articles/article-screen-mark-on-open",
            title: "Article Screen Mark On Open"
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)

        let loadedArticle = try #require(controller.screenState.article)
        #expect(loadedArticle.isRead == true)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == "Mark Unread")
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle.slash")

        let persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articleScreenControllerKeepsArticleUnreadOnOpenWhenSettingIsDisabled() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                markAsReadOnOpen: false,
                updatedAt: .distantPast
            )
        )
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-keep-unread-on-open.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-keep-unread-on-open",
            url: "https://example.com/articles/article-screen-keep-unread-on-open",
            title: "Article Screen Keep Unread On Open"
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)

        let loadedArticle = try #require(controller.screenState.article)
        #expect(loadedArticle.isRead == false)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == "Mark Read")
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle")

        let persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState == nil)
    }

    @Test
    func articleScreenControllerBuildsNotFoundPlaceholderWhenArticleDoesNotExist() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = ArticleScreenController()

        await controller.load(articleID: UUID(), dependencies: harness.dependencies)

        #expect(controller.screenState.phase == .notFound)
        #expect(controller.screenState.placeholder?.title == "Article Not Found")
    }

    @Test
    func articleScreenControllerBuildsFailedPlaceholderWhenArticleQueryServiceIsUnavailable() async {
        let dependencies = AppDependencies(logger: TestLogger())
        let controller = ArticleScreenController()

        await controller.load(articleID: UUID(), dependencies: dependencies)

        #expect(controller.screenState.phase == .failed("Article query service is unavailable."))
        #expect(controller.screenState.placeholder?.title == "Failed to Load Article")
        #expect(
            controller.screenState.placeholder?.description
                == "Article query service is unavailable."
        )
    }

    @Test
    func articleScreenControllerTogglesArticleReadStatusWithoutReloadingScreen() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-mark-unread.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-mark-unread",
            url: "https://example.com/articles/article-screen-mark-unread",
            title: "Article Screen Mark Unread"
        )
        _ = try harness.articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)
        controller.toggleArticleReadStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        var updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isRead == false)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == "Mark Read")
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle")

        var persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isRead == false)

        controller.toggleArticleReadStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isRead == true)
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleTitle == "Mark Unread")
        #expect(controller.screenState.toolbarActions.bottomActions?.readToggleSystemImage == "circle.slash")

        persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articleScreenControllerTogglesArticleStarredStatusWithoutReloadingScreen() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-toggle-star.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-toggle-star",
            url: "https://example.com/articles/article-screen-toggle-star",
            title: "Article Screen Toggle Star"
        )
        let controller = ArticleScreenController()

        await controller.load(articleID: article.id, dependencies: harness.dependencies)
        controller.toggleArticleStarredStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        var updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isStarred == true)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.toolbarActions.bottomActions?.starTitle == "Unstar")
        #expect(controller.screenState.toolbarActions.bottomActions?.starSystemImage == "star.slash")

        var persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isStarred == true)

        controller.toggleArticleStarredStatus(
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        updatedArticle = try #require(controller.screenState.article)
        #expect(updatedArticle.isStarred == false)
        #expect(controller.screenState.toolbarActions.bottomActions?.starTitle == "Star")
        #expect(controller.screenState.toolbarActions.bottomActions?.starSystemImage == "star")

        persistedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        #expect(persistedState?.isStarred == false)
    }

    @Test
    func articleScreenControllerOpensCurrentArticleInAppLevelWebViewRoute() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/article-screen-open-web.xml"]).first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "article-screen-open-web",
            url: "https://example.com/articles/article-screen-open-web",
            title: "Article Screen Open Web"
        )
        articleModel.canonicalURL = "https://example.com/articles/article-screen-open-web/canonical"
        try harness.saveModelContext()
        let controller = ArticleScreenController()

        await controller.load(articleID: articleModel.id, dependencies: harness.dependencies)
        controller.openArticleInAppBrowser(
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(
            appState.selectedDetailRoute == .webView(
                ArticleWebViewRoute(
                    articleID: articleModel.id,
                    url: URL(string: "https://example.com/articles/article-screen-open-web/canonical")!
                )
            )
        )
        #expect(
            appState.presentedWebViewRoute == ArticleWebViewRoute(
                articleID: articleModel.id,
                url: URL(string: "https://example.com/articles/article-screen-open-web/canonical")!
            )
        )
    }

    @Test
    func articleScreenNavigationStateShowsBackButtonOnlyForCompactArticleContext() {
        #expect(
            ArticleScreenNavigationState.showsBackButton(
                horizontalSizeClass: .compact,
                articleSelection: UUID()
            )
        )
        #expect(
            ArticleScreenNavigationState.showsBackButton(
                horizontalSizeClass: .regular,
                articleSelection: UUID()
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.showsBackButton(
                horizontalSizeClass: .compact,
                articleSelection: nil
            ) == false
        )
    }

    @Test
    func articleScreenNavigationStateRecognizesLeadingEdgeBackSwipe() {
        #expect(
            ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 8)
            )
        )
        #expect(
            ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                startLocationX: 80,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
        #expect(
            ArticleScreenNavigationState.shouldNavigateBackOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 40, height: 8)
            ) == false
        )
    }

    @Test
    func readingShellNavigationStateBuildsDetailDestinationsForNoneAndArticleRoutes() {
        let articleID = UUID()

        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .none,
                selectedArticleID: nil
            ) == .none
        )
        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .none,
                selectedArticleID: articleID
            ) == .article(articleID)
        )
        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .article(articleID),
                selectedArticleID: nil
            ) == .article(articleID)
        )
    }

    @Test
    func readingShellNavigationStateBuildsWebViewDestinationForWebViewRoute() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/web-shell-destination")!
        )

        #expect(
            ReadingShellDetailNavigationState.detailDestination(
                route: .webView(route),
                selectedArticleID: route.articleID
            ) == .webView(route)
        )
    }

    @Test
    func webViewScreenNavigationStateClosesOnLeftEdgeHorizontalDrag() {
        #expect(
            WebViewScreenNavigationState.shouldCloseOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 10)
            )
        )
    }

    @Test
    func webViewScreenNavigationStateIgnoresDragsAwayFromLeftEdge() {
        #expect(
            WebViewScreenNavigationState.shouldCloseOnDrag(
                startLocationX: 48,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
    }

    @Test
    func webViewScreenNavigationStateIgnoresMostlyVerticalDrags() {
        #expect(
            WebViewScreenNavigationState.shouldCloseOnDrag(
                startLocationX: 10,
                translation: CGSize(width: 96, height: 64)
            ) == false
        )
    }

    @Test
    func webViewScreenStateBuildsInitialDerivedStateFromRoute() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/webview-state")!
        )
        let state = WebViewScreenState(route: route)
        let viewState = state.derivedViewState()

        #expect(viewState.initialURL == route.url)
        #expect(viewState.navigationTitle == "example.com")
        #expect(viewState.primaryLoadingState?.title == "Loading Page")
        #expect(viewState.placeholder == nil)
        #expect(viewState.loadingProgress == 0)
        #expect(viewState.reloadRevision == 0)
        #expect(viewState.showsWebViewContent)
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)
        #expect(viewState.toolbar.shareURL == route.url)
        #expect(viewState.toolbar.isShareEnabled)
        #expect(viewState.bottomActions.isRefreshEnabled)
        #expect(viewState.bottomActions.openExternalBrowserURL == route.url)
        #expect(viewState.bottomActions.isOpenExternalBrowserEnabled)
    }

    @Test
    func webViewScreenStateTracksTitleLoadingProgressAndFailureIndependentlyFromView() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/webview-state-progress")!
        )
        var state = WebViewScreenState(route: route)

        state.applyNavigationStart()
        state.applyLoadingProgress(0.42)
        state.applyPageTitle("Loaded Article")

        var viewState = state.derivedViewState()
        #expect(viewState.primaryLoadingState?.title == "Loading Page")
        #expect(viewState.placeholder == nil)
        #expect(viewState.loadingProgress == 0.42)
        #expect(viewState.navigationTitle == "Loaded Article")
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)

        state.applyNavigationFinished()
        viewState = state.derivedViewState()
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.loadingProgress == 1)
        #expect(viewState.showsShareAction)
        #expect(viewState.showsBottomActions)

        state.applyNavigationFailure("The page could not be loaded.")
        viewState = state.derivedViewState()
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder?.title == "Failed to Load Page")
        #expect(viewState.placeholder?.description == "The page could not be loaded.")
        #expect(viewState.showsWebViewContent == false)
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)
    }

    @Test
    func webViewScreenStateSwitchesShareAndBrowserActionsToCurrentPageURL() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/original")!
        )
        var state = WebViewScreenState(route: route)

        state.applyCurrentPageURL(URL(string: "https://example.com/articles/redirected")!)

        var viewState = state.derivedViewState()
        #expect(viewState.toolbar.shareURL?.absoluteString == "https://example.com/articles/redirected")
        #expect(
            viewState.bottomActions.openExternalBrowserURL?.absoluteString
                == "https://example.com/articles/redirected"
        )

        state.applyCurrentPageURL(URL(string: "mailto:hello@example.com")!)

        viewState = state.derivedViewState()
        #expect(viewState.toolbar.shareURL == nil)
        #expect(viewState.toolbar.isShareEnabled == false)
        #expect(viewState.bottomActions.openExternalBrowserURL == nil)
        #expect(viewState.bottomActions.isOpenExternalBrowserEnabled == false)
    }

    @Test
    func webViewScreenStateIncrementsReloadRevisionOnlyForSupportedURLs() {
        let supportedRoute = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/webview-reload")!
        )
        var supportedState = WebViewScreenState(route: supportedRoute)

        supportedState.requestReload()

        #expect(supportedState.derivedViewState().reloadRevision == 1)

        let unsupportedRoute = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "mailto:hello@example.com")!
        )
        var unsupportedState = WebViewScreenState(route: unsupportedRoute)

        unsupportedState.requestReload()

        #expect(unsupportedState.derivedViewState().reloadRevision == 0)
    }

    @Test
    func webViewScreenStateStartsInFailurePhaseForUnsupportedInitialURL() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "mailto:hello@example.com")!
        )
        let state = WebViewScreenState(route: route)
        let viewState = state.derivedViewState()

        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder?.title == "Failed to Load Page")
        #expect(
            viewState.placeholder?.description
                == "This article link can't be opened in the in-app browser."
        )
        #expect(viewState.navigationTitle == "Article")
        #expect(viewState.showsWebViewContent == false)
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)
        #expect(viewState.toolbar.shareURL == nil)
        #expect(viewState.toolbar.isShareEnabled == false)
        #expect(viewState.bottomActions.isRefreshEnabled == false)
        #expect(viewState.bottomActions.openExternalBrowserURL == nil)
        #expect(viewState.bottomActions.isOpenExternalBrowserEnabled == false)
    }

    @Test
    func articlesScreenStateStartsWithoutSelectionPlaceholder() {
        let state = ArticlesScreenState()

        #expect(state.phase == .noSelection)
        #expect(state.navigationTitle == "Articles")
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.placeholder?.title == "No Source Selected")
        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateBeginsPrimaryLoadingWhenSelectionChanges() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "3 Unread Items",
            resetsContent: true
        )

        #expect(state.phase == .loading)
        #expect(state.navigationTitle == "Unread")
        #expect(state.navigationSubtitle == "3 Unread Items")
        #expect(state.showsPrimaryLoadingIndicator)
        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateBuildsEmptyPlaceholderForCurrentSelection() {
        var state = ArticlesScreenState()

        state.applyLoadedArticles(
            [],
            selection: .starred,
            navigationTitle: "Starred",
            navigationSubtitle: "0 Starred Items"
        )

        #expect(state.phase == .empty)
        #expect(state.navigationTitle == "Starred")
        #expect(state.navigationSubtitle == "0 Starred Items")
        #expect(state.placeholder?.title == "No Articles")
        #expect(state.placeholder?.description == "You have not starred any articles yet.")
    }

    @Test
    func articlesScreenStateBuildsPrimaryFailureForInitialLoad() {
        var state = ArticlesScreenState()

        state.applyLoadingFailure(
            "Article query service is unavailable.",
            selection: .inbox,
            navigationTitle: "All Items",
            navigationSubtitle: "0 Unread Items",
            retainsContent: false
        )

        #expect(state.phase == .failed("Article query service is unavailable."))
        #expect(state.primaryFailureMessage == "Article query service is unavailable.")
        #expect(state.refreshFeedback == nil)
    }

    @Test
    func articlesScreenStateKeepsVisibleArticlesWhenRefreshFails() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.beginLoading(
            for: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            resetsContent: false
        )
        state.applyLoadingFailure(
            "Refresh failed",
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            retainsContent: true
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationTitle == "Feed")
        #expect(state.navigationSubtitle == "1 Unread Item")
        #expect(state.articles.map(\.id) == [unreadItem.id])
        #expect(state.refreshState == .idle)
        #expect(state.refreshFeedback == ArticlesScreenRefreshFeedback(message: "Refresh failed"))
        #expect(state.toolbarActions.isMarkAllAsReadEnabled)
    }

    @Test
    func articlesScreenStateClearsRefreshFeedbackWhenPrimaryReloadStarts() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentRefreshFailure("Refresh failed")

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item",
            resetsContent: true
        )

        #expect(state.phase == .loading)
        #expect(state.refreshFeedback == nil)
    }

    @Test
    func articlesScreenStateBuildsDerivedToolbarActionsAndSearchPlaceholderForFilteredResults() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(
            title: "SwiftUI Weekly",
            isRead: false,
            isStarred: false
        )
        let readItem = makeArticleListItemDTO(
            title: "Architecture Digest",
            isRead: true,
            isStarred: false
        )

        state.applyLoadedArticles(
            [unreadItem, readItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )

        let loadedViewState = state.derivedViewState(searchText: "swift")
        let emptySearchViewState = state.derivedViewState(searchText: "kotlin")

        #expect(loadedViewState.visibleArticles.map(\.id) == [unreadItem.id])
        #expect(loadedViewState.toolbarActions.isMarkAllAsReadEnabled)
        #expect(emptySearchViewState.visibleArticles.isEmpty)
        #expect(emptySearchViewState.toolbarActions.isMarkAllAsReadEnabled == false)
        #expect(emptySearchViewState.searchPlaceholder?.title == "No Search Results")
        #expect(emptySearchViewState.searchPlaceholder?.description == "No visible articles match \"kotlin\".")
    }

    @Test
    func articlesScreenStateBuildsRefreshBannerForVisibleRefreshFailure() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentRefreshFailure("Refresh failed")

        let derivedViewState = state.derivedViewState(searchText: "")

        #expect(derivedViewState.refreshBanner?.style == .failed)
        #expect(derivedViewState.refreshBanner?.title == "Refresh Failed")
        #expect(derivedViewState.refreshBanner?.message == "Refresh failed")
        #expect(derivedViewState.refreshBanner?.showsRetryAction == true)
    }

    @Test
    func articlesScreenStateBuildsPrimaryLoadingCopyFromSelection() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .folder("Apple"),
            navigationTitle: "Apple",
            navigationSubtitle: "0 Unread Items",
            resetsContent: true
        )

        let derivedViewState = state.derivedViewState(searchText: "")

        #expect(derivedViewState.primaryLoadingState?.title == "Loading Articles")
    }

    @Test
    func articlesScreenControllerLoadsFeedArticlesForCurrentSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-load.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-load-article",
            url: "https://example.com/articles/controller-load",
            title: "Controller Load"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.navigationTitle == "controller-load.xml")
        #expect(controller.screenState.articles.count == 1)
        #expect(controller.screenState.articles.first?.title == "Controller Load")
    }

    func articlesScreenControllerPresentsRefreshFailureFromBatchRefreshResult() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/controller-refresh.xml": .response(
                    statusCode: 500,
                    headers: [:],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-refresh.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-refresh-article",
            url: "https://example.com/articles/controller-refresh",
            title: "Controller Refresh"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )
        harness.dependencies.showFeed(id: feed.id, using: appState)

        await controller.refreshCurrentSelection(
            selection: .feed(feed.id),
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.refreshFeedback?.message.contains("invalidStatusCode") == true)
    }

    @Test
    func articlesScreenControllerClearsPreviousRefreshErrorAfterSuccessfulRefresh() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/controller-refresh-success.xml": .response(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: Self.validRSSFeedXML(
                        channelTitle: "Refresh Success Feed",
                        channelLink: "https://example.com/refresh-success/",
                        language: "en",
                        itemTitle: "Refreshed Article",
                        itemLink: "https://example.com/articles/refreshed",
                        itemGUID: "refreshed-article",
                        itemDescription: "Readable summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-refresh-success.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-refresh-success-article",
            url: "https://example.com/articles/controller-refresh-success",
            title: "Controller Refresh Success"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )
        controller.screenState.presentRefreshFailure("Previous refresh failed")
        harness.dependencies.showFeed(id: feed.id, using: appState)

        await controller.refreshCurrentSelection(
            selection: .feed(feed.id),
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func articlesScreenControllerClearsStaleRefreshErrorWhenSelectionChanges() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-selection-a.xml"]).first)
        let secondFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-selection-b.xml"]).first)

        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "controller-selection-a-article",
            url: "https://example.com/articles/controller-selection-a",
            title: "First Selection"
        )
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "controller-selection-b-article",
            url: "https://example.com/articles/controller-selection-b",
            title: "Second Selection"
        )

        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(firstFeed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )
        controller.screenState.presentRefreshFailure("Refresh failed for first feed")

        await controller.load(
            selection: .feed(secondFeed.id),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articles.first?.title == "Second Selection")
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func articlesScreenMutationReducerRemovesVisibleArticlesAfterMarkAllAsReadInUnreadFilter() {
        let firstUnread = makeArticleListItemDTO(isRead: false, isStarred: false)
        let secondUnread = makeArticleListItemDTO(isRead: false, isStarred: false)
        let remainingRead = makeArticleListItemDTO(isRead: true, isStarred: false)

        let updatedArticles = ArticlesScreenMutationReducer.reduceAfterMarkAllAsRead(
            visibleArticles: [firstUnread, secondUnread],
            allArticles: [firstUnread, secondUnread, remainingRead],
            filter: ArticleListFilter.unread
        )

        #expect(updatedArticles.map { $0.id } == [remainingRead.id])
    }

    @Test
    func articlesScreenMutationReducerProducesRemoveMutationWhenReadToggleHappensInUnreadFilter() {
        let unreadArticle = makeArticleListItemDTO(isRead: false, isStarred: false)

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleReadStatus(
            article: unreadArticle,
            filter: ArticleListFilter.unread
        )

        #expect(mutation == .remove)
    }

    @Test
    func articlesScreenMutationReducerProducesUnreadUpdateWhenReadArticleIsToggledBack() {
        let readArticle = makeArticleListItemDTO(isRead: true, isStarred: false)

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleReadStatus(
            article: readArticle,
            filter: ArticleListFilter.all
        )

        let updatedArticle: ArticleListItemDTO?
        if case .update(let article) = mutation {
            updatedArticle = article
        } else {
            updatedArticle = nil
        }

        #expect(updatedArticle?.isRead == false)
        #expect(updatedArticle?.isStarred == false)
    }

    @Test
    func articlesScreenMutationReducerProducesRemoveMutationWhenUnstarringInsideStarredFilter() {
        let starredArticle = makeArticleListItemDTO(isRead: true, isStarred: true)

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleStarred(
            article: starredArticle,
            filter: ArticleListFilter.starred
        )

        #expect(mutation == .remove)
    }

    @Test
    func articlesScreenStatePresentsConfirmationOnlyWhenUnreadArticlesAreVisible() {
        var state = ArticlesScreenState()
        let readItem = makeArticleListItemDTO(isRead: true, isStarred: false)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [readItem],
            selection: .feed(readItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "0 Unread Items"
        )
        state.presentMarkAllAsReadConfirmation()
        #expect(state.pendingConfirmation == nil)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentMarkAllAsReadConfirmation()
        #expect(state.pendingConfirmation == .markAllAsRead)
    }

    @Test
    func articlesScreenControllerPresentsConfirmationWhenAskBeforeMarkingAllAsReadIsEnabled() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let controller = ArticlesScreenController(
            previewScreenState: .previewLoaded(
                selection: .feed(unreadItem.feedID),
                navigationTitle: "Feed",
                navigationSubtitle: "1 Unread Item",
                articles: [unreadItem]
            )
        )

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: true,
                updatedAt: .distantPast
            )
        )

        controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.pendingConfirmation == .markAllAsRead)
        #expect(controller.screenState.articles.first?.isRead == false)
    }

    @Test
    func articlesScreenControllerMarksAllAsReadImmediatelyWhenAskBeforeMarkingAllAsReadIsDisabled() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let articleStateRepository = try #require(harness.dependencies.articleStateRepository)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let controller = ArticlesScreenController(
            previewScreenState: .previewLoaded(
                selection: .feed(unreadItem.feedID),
                navigationTitle: "Feed",
                navigationSubtitle: "1 Unread Item",
                articles: [unreadItem]
            )
        )

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: false,
                updatedAt: .distantPast
            )
        )

        controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sourcesFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try articleStateRepository.fetchStateSnapshot(
            feedID: unreadItem.feedID,
            articleExternalID: unreadItem.articleExternalID
        )

        #expect(controller.screenState.pendingConfirmation == nil)
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.navigationSubtitle == "0 Unread Items")
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articlesScreenToolbarActionsAreHiddenDuringPrimaryLoading() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            resetsContent: true
        )

        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenToolbarActionsAreHiddenAfterPrimaryFailure() {
        var state = ArticlesScreenState()

        state.applyLoadingFailure(
            "Unable to load the current selection.",
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            retainsContent: false
        )

        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateAppliesMarkAllAsReadAndRefreshesToolbarState() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: true)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentMarkAllAsReadConfirmation()
        state.applyMarkAllAsRead(
            [
                makeArticleListItemDTO(
                    id: unreadItem.id,
                    feedID: unreadItem.feedID,
                    articleExternalID: unreadItem.articleExternalID,
                    isRead: true,
                    isStarred: true
                )
            ],
            navigationSubtitle: "0 Unread Items"
        )

        #expect(state.pendingConfirmation == nil)
        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.count == 1)
        #expect(state.articles.first?.isRead == true)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenStateAppliesMarkAllAsReadToUnreadFilterAndTransitionsToEmpty() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentMarkAllAsReadConfirmation()
        state.applyMarkAllAsRead([], navigationSubtitle: "0 Unread Items")

        #expect(state.pendingConfirmation == nil)
        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.isEmpty)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenStateAppliesArticleRowUpdateForReadAction() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let updatedItem = makeArticleListItemDTO(
            id: unreadItem.id,
            feedID: unreadItem.feedID,
            articleExternalID: unreadItem.articleExternalID,
            isRead: true,
            isStarred: false
        )

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .update(updatedItem),
            navigationSubtitle: "0 Unread Items"
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.count == 1)
        #expect(state.articles.first?.isRead == true)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenStateRemovesArticleRowForReadActionInUnreadSelection() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item"
        )
        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .remove,
            navigationSubtitle: "0 Unread Items"
        )

        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.isEmpty)
    }

    @Test
    func articlesScreenStateAppliesArticleRowUpdateForStarActionOutsideStarredSelection() {
        var state = ArticlesScreenState()
        let item = makeArticleListItemDTO(isRead: false, isStarred: false)
        let updatedItem = makeArticleListItemDTO(
            id: item.id,
            feedID: item.feedID,
            articleExternalID: item.articleExternalID,
            isRead: false,
            isStarred: true
        )

        state.applyLoadedArticles(
            [item],
            selection: .feed(item.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.applyArticleRowMutation(
            articleID: item.id,
            mutation: .update(updatedItem),
            navigationSubtitle: "1 Unread Item"
        )

        #expect(state.phase == .loaded)
        #expect(state.articles.first?.isStarred == true)
        #expect(state.navigationSubtitle == "1 Unread Item")
    }

    @Test
    func articlesScreenStateRemovesArticleRowWhenUnstarredInsideStarredSelection() {
        var state = ArticlesScreenState()
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)

        state.applyLoadedArticles(
            [starredItem],
            selection: .starred,
            navigationTitle: "Starred",
            navigationSubtitle: "1 Starred Item"
        )
        state.applyArticleRowMutation(
            articleID: starredItem.id,
            mutation: .remove,
            navigationSubtitle: "0 Starred Items"
        )

        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == "0 Starred Items")
        #expect(state.articles.isEmpty)
    }

    @Test
    func articleRowSwipeActionsStateReflectsReadAndStarredStatus() {
        let unreadUnstarred = ArticleRowSwipeActionsState(
            article: makeArticleListItemDTO(isRead: false, isStarred: false)
        )
        let readStarred = ArticleRowSwipeActionsState(
            article: makeArticleListItemDTO(isRead: true, isStarred: true)
        )

        #expect(unreadUnstarred.readActionTitle == "Read")
        #expect(unreadUnstarred.readActionSystemImage == "circle")
        #expect(unreadUnstarred.starActionTitle == "Star")
        #expect(unreadUnstarred.starActionSystemImage == "star")

        #expect(readStarred.readActionTitle == "Unread")
        #expect(readStarred.readActionSystemImage == "circle.slash")
        #expect(readStarred.starActionTitle == "Unstar")
        #expect(readStarred.starActionSystemImage == "star.slash")
    }

    @Test
    func articlesScreenNavigationTitleResolverBuildsTitlesFromSidebarSelection() {
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: nil) == "Articles")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .inbox) == "All Items")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .unread) == "Unread")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .starred) == "Starred")
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .folder("Tech")) == "Tech")
        #expect(
            ArticlesScreenNavigationTitleResolver.resolve(
                selection: .feed(UUID()),
                selectedFeedTitle: "The Verge"
            ) == "The Verge"
        )
        #expect(ArticlesScreenNavigationTitleResolver.resolve(selection: .feed(UUID())) == "Source")
    }

    @Test
    func articlesScreenSubtitleResolverBuildsSubtitleFromSourcesFilter() {
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)
        let unreadStarredItem = makeArticleListItemDTO(isRead: false, isStarred: true)
        let articles = [unreadItem, starredItem, unreadStarredItem]

        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sourcesFilter: .allItems
            ) == "2 Unread Items"
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sourcesFilter: .unread
            ) == "2 Unread Items"
        )
        #expect(
            ArticlesScreenSubtitleResolver.resolve(
                articles: articles,
                sourcesFilter: .starred
            ) == "2 Starred Items"
        )
    }

    @Test
    func articlesDaySectionsBuilderGroupsArticlesByDayAndPreservesVisibleOrder() {
        let calendar = Calendar.current
        let now = Date()
        let todayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let todayEarlier = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let yesterdayBase = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayArticleDate = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: yesterdayBase) ?? yesterdayBase

        let firstToday = makeArticleListItemDTO(title: "Today One", publishedAt: todayMorning)
        let secondToday = makeArticleListItemDTO(title: "Today Two", publishedAt: todayEarlier)
        let yesterdayArticle = makeArticleListItemDTO(title: "Yesterday", publishedAt: yesterdayArticleDate)

        let sections = ArticlesDaySectionsBuilder.build(
            from: [firstToday, secondToday, yesterdayArticle],
            calendar: calendar
        )

        #expect(sections.count == 2)
        #expect(sections[0].articles.map(\.title) == ["Today One", "Today Two"])
        #expect(sections[1].articles.map(\.title) == ["Yesterday"])
    }

    @Test
    func articlesDaySectionsBuilderBuildsTodayYesterdayAndDateHeaders() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let older = calendar.date(byAdding: .day, value: -2, to: today) ?? today

        #expect(ArticlesDaySectionsBuilder.title(for: today, calendar: calendar) == "Today")
        #expect(ArticlesDaySectionsBuilder.title(for: yesterday, calendar: calendar) == "Yesterday")
        #expect(
            ArticlesDaySectionsBuilder.title(for: older, calendar: calendar)
            == older.formatted(
                .dateTime
                    .weekday(.wide)
                    .day()
                    .month(.wide)
                    .year()
            )
        )
    }

    @Test
    func readingShellCompactNavigationStateSelectsPreferredCompactColumnForCurrentContext() {
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sourceSelection: nil,
                articleSelection: nil
            ) == .sidebar
        )
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sourceSelection: .unread,
                articleSelection: nil
            ) == .content
        )
        #expect(
            ReadingShellCompactNavigationState.preferredCompactColumn(
                sourceSelection: .feed(UUID()),
                articleSelection: UUID()
            ) == .detail
        )
    }

    @Test
    func readingShellCompactNavigationStateShowsArticlesBackButtonOnlyInCompactSourceContext() {
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .compact,
                sourceSelection: .starred
            )
        )
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .regular,
                sourceSelection: .starred
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.showsArticlesBackButton(
                horizontalSizeClass: .compact,
                sourceSelection: nil
            ) == false
        )
    }

    @Test
    func readingShellCompactNavigationStateRecognizesLeadingEdgeBackSwipeToSources() {
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 8)
            )
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 64,
                translation: CGSize(width: 96, height: 8)
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 40, height: 8)
            ) == false
        )
        #expect(
            ReadingShellCompactNavigationState.shouldNavigateBackToSourcesOnDrag(
                startLocationX: 12,
                translation: CGSize(width: 96, height: 72)
            ) == false
        )
    }

    @Test
    func sourcesFilterPersistencePolicyRestoresPersistedFilterFromSettingsRawValue() {
        let settings = AppSettings(selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue)

        let restoredFilter = SourcesFilterPersistencePolicy.restoredFilter(
            from: settings.selectedSourcesFilterRawValue
        )

        #expect(restoredFilter == .starred)
    }

    @Test
    func sourcesFilterPersistencePolicyFallsBackToAllItemsWhenRawValueIsMissing() {
        let settings = AppSettings(selectedSourcesFilterRawValue: nil)

        #expect(
            SourcesFilterPersistencePolicy.restoredFilter(
                from: settings.selectedSourcesFilterRawValue
            ) == .allItems
        )
    }

    @Test
    func sourcesFilterPersistencePolicyBuildsSettingsPatchForSelectedFilter() {
        let starredUpdate = SourcesFilterPersistencePolicy.makeSettingsPatch(
            for: .starred,
            updatedAt: .distantPast
        )
        let unreadUpdate = SourcesFilterPersistencePolicy.makeSettingsPatch(
            for: .unread,
            updatedAt: .distantPast
        )

        #expect(starredUpdate.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
        #expect(unreadUpdate.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
    }

    @Test
    func appSettingsDefaultsUseSelectedSourcesFilterRawValueAsPrimarySourceFilterState() {
        let settings = AppSettings()

        #expect(settings.selectedSourcesFilterRawValue == SourcesFilter.allItems.rawValue)
        #expect(settings.askBeforeMarkingAllAsRead)
    }

    @Test
    func appSettingsRepositoryPersistsSelectedSourcesFilterRawValue() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
    }

    @Test
    func appSettingsRepositoryPersistsAskBeforeMarkingAllAsRead() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: false,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.askBeforeMarkingAllAsRead == false)
    }

    @Test
    func appSettingsServiceFetchesSnapshotFromRepository() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)

        _ = try repository.update(
            AppSettingsUpdate(
                defaultReaderMode: .browser,
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                refreshIntervalPreference: .hourly,
                useiCloudSync: true,
                markAsReadOnOpen: false,
                askBeforeMarkingAllAsRead: false,
                sortMode: .publishedAtAscending,
                updatedAt: .distantPast
            )
        )

        let snapshot = try service.fetchSettings()

        #expect(
            snapshot == AppSettingsSnapshot(
                defaultReaderMode: .browser,
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                refreshIntervalPreference: .hourly,
                useiCloudSync: true,
                markAsReadOnOpen: false,
                askBeforeMarkingAllAsRead: false,
                sortMode: .publishedAtAscending
            )
        )
    }

    @Test
    func appSettingsServiceSavesEditedSnapshot() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)
        let editedSettings = AppSettingsSnapshot(
            defaultReaderMode: .reader,
            selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
            refreshIntervalPreference: .every6Hours,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            sortMode: .publishedAtDescending
        )

        let savedSnapshot = try service.saveSettings(
            editedSettings,
            updatedAt: .distantPast
        )
        let persistedSettings = try repository.fetchOrCreate()

        #expect(savedSnapshot == editedSettings)
        #expect(persistedSettings.defaultReaderMode == .reader)
        #expect(persistedSettings.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
        #expect(persistedSettings.refreshIntervalPreference == .every6Hours)
        #expect(persistedSettings.useiCloudSync)
        #expect(persistedSettings.markAsReadOnOpen == false)
        #expect(persistedSettings.askBeforeMarkingAllAsRead == false)
        #expect(persistedSettings.sortMode == .publishedAtDescending)
    }

    @Test
    func appSettingsServiceUpdatesSelectedSourcesFilterRawValueThroughPatch() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)

        let updatedSnapshot = try service.updateSettings(
            AppSettingsPatch(
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                updatedAt: .distantPast
            )
        )
        let persistedSettings = try repository.fetchOrCreate()

        #expect(updatedSnapshot.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
        #expect(persistedSettings.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
    }

    @Test
    func settingsScreenPresentationBuilderBuildsSectionedContractFromSettingsSnapshot() {
        let snapshot = AppSettingsSnapshot(
            defaultReaderMode: .browser,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .daily,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            sortMode: .publishedAtDescending
        )

        let sections = SettingsScreenPresentationBuilder.buildSections(from: snapshot)

        #expect(sections.map(\.id) == [.reading, .articleList, .refresh, .sync, .advanced])

        let readingItems = sections[0].items
        let articleListItems = sections[1].items
        let refreshItems = sections[2].items
        let syncItems = sections[3].items
        let advancedItems = sections[4].items

        #expect(
            readingItems[0] == .picker(
                SettingsPickerItemPresentation(
                    id: .defaultReaderMode,
                    title: "Default Reader",
                    subtitle: "Choose how articles open by default.",
                    selectedValueTitle: "In-App Browser",
                    options: [
                        SettingsPickerOptionPresentation(id: "embedded", title: "Embedded Reader", isSelected: false),
                        SettingsPickerOptionPresentation(id: "reader", title: "Reader Mode", isSelected: false),
                        SettingsPickerOptionPresentation(id: "browser", title: "In-App Browser", isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[1] == .toggle(
                SettingsToggleItemPresentation(
                    id: .markAsReadOnOpen,
                    title: "Mark Read on Open",
                    subtitle: "Automatically mark an article as read when it is opened.",
                    isOn: false
                )
            )
        )
        #expect(
            articleListItems == [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleSortMode,
                        title: "Sort Articles",
                        subtitle: "Choose how unread and article lists are ordered.",
                        selectedValueTitle: "Newest First",
                        options: [
                            SettingsPickerOptionPresentation(id: "newestFirst", title: "Newest First", isSelected: true),
                            SettingsPickerOptionPresentation(id: "oldestFirst", title: "Oldest First", isSelected: false)
                        ]
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .askBeforeMarkingAllAsRead,
                        title: "Ask Before Marking All Read",
                        subtitle: "Show a confirmation before marking all visible articles as read.",
                        isOn: false
                    )
                )
            ]
        )
        #expect(
            refreshItems.contains(
                .picker(
                    SettingsPickerItemPresentation(
                        id: .refreshInterval,
                        title: "Background Refresh",
                        subtitle: "Choose how often feeds should refresh when background refresh is available.",
                        selectedValueTitle: "Daily",
                        options: [
                            SettingsPickerOptionPresentation(id: "manual", title: "Manual", isSelected: false),
                            SettingsPickerOptionPresentation(id: "every15Minutes", title: "Every 15 Minutes", isSelected: false),
                            SettingsPickerOptionPresentation(id: "hourly", title: "Hourly", isSelected: false),
                            SettingsPickerOptionPresentation(id: "every6Hours", title: "Every 6 Hours", isSelected: false),
                            SettingsPickerOptionPresentation(id: "daily", title: "Daily", isSelected: true)
                        ]
                    )
                )
            )
        )
        #expect(
            syncItems == [
                .statusRow(
                    SettingsStatusRowItemPresentation(
                        id: .iCloudSyncStatus,
                        title: "iCloud Sync",
                        subtitle: "Sync is enabled in settings, but CloudKit status is not implemented yet.",
                        valueTitle: "Enabled"
                    )
                )
            ]
        )
        #expect(advancedItems.count == 2)
    }

    @Test
    func settingsScreenPresentationBuilderIncludesAllSupportedItemTypes() {
        let sections = SettingsScreenPresentationBuilder.buildSections(from: AppSettingsSnapshot())
        let items = sections.flatMap(\.items)

        #expect(items.contains { item in
            if case .toggle = item { return true }
            return false
        })
        #expect(items.contains { item in
            if case .picker = item { return true }
            return false
        })
        #expect(items.contains { item in
            if case .navigationLink = item { return true }
            return false
        })
        #expect(items.contains { item in
            if case .statusRow = item { return true }
            return false
        })
    }

    @Test
    func settingsScreenStateBuildsLoadedViewStateFromSnapshot() {
        let snapshot = AppSettingsSnapshot(
            defaultReaderMode: .browser,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .hourly,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            sortMode: .publishedAtAscending
        )
        var state = SettingsScreenState()

        state.applyLoadedSnapshot(snapshot)
        let viewState = state.derivedViewState()

        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.sections.map(\.id) == [.reading, .articleList, .refresh, .sync, .advanced])
    }

    @Test
    func settingsScreenStatePresentsDefaultReaderModePickerFromLoadedSections() {
        var state = SettingsScreenState.previewLoaded(
            snapshot: AppSettingsSnapshot(defaultReaderMode: .reader)
        )

        state.presentPicker(for: .defaultReaderMode)

        let presentedPicker = state.derivedViewState().presentedPicker
        #expect(presentedPicker?.id == .defaultReaderMode)
        #expect(presentedPicker?.selectedValueTitle == "Reader Mode")
        #expect(presentedPicker?.options.count == ReaderMode.allCases.count)
    }

    @Test
    func settingsScreenControllerLoadsSettingsSnapshotFromService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.appSettingsService)
        _ = try service.saveSettings(
            AppSettingsSnapshot(
                defaultReaderMode: .reader,
                selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
                refreshIntervalPreference: .every15Minutes,
                useiCloudSync: false,
                markAsReadOnOpen: true,
                askBeforeMarkingAllAsRead: false,
                sortMode: .publishedAtDescending
            ),
            updatedAt: .distantPast
        )
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)

        let viewState = controller.viewState()
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.sections.isEmpty == false)
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .reader)
        #expect(controller.screenState.settingsSnapshot.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedDefaultReaderModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.defaultReaderMode, dependencies: harness.dependencies)

        #expect(controller.viewState().presentedPicker?.id == .defaultReaderMode)

        controller.handlePickerOptionSelection(
            itemID: .defaultReaderMode,
            optionID: ReaderMode.browser.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .browser)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.defaultReaderMode == .browser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleSortModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.articleSortMode, dependencies: harness.dependencies)

        #expect(controller.viewState().presentedPicker?.id == .articleSortMode)

        controller.handlePickerOptionSelection(
            itemID: .articleSortMode,
            optionID: ArticleListSortOrder.oldestFirst.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.sortMode == .publishedAtAscending)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.sortMode == .publishedAtAscending)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedMarkAsReadOnOpenThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        #expect(controller.screenState.settingsSnapshot.markAsReadOnOpen)

        controller.handleToggleValueChange(
            itemID: .markAsReadOnOpen,
            isOn: false,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.markAsReadOnOpen == false)
        #expect(persistedSettings.markAsReadOnOpen == false)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedAskBeforeMarkingAllAsReadThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead)

        controller.handleToggleValueChange(
            itemID: .askBeforeMarkingAllAsRead,
            isOn: false,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
        #expect(persistedSettings.askBeforeMarkingAllAsRead == false)
    }

    @Test
    func settingsScreenControllerBuildsFailureStateWhenSettingsServiceIsUnavailable() {
        let controller = SettingsScreenController()
        let dependencies = AppDependencies.makeDefault()

        controller.loadSettings(dependencies: dependencies)

        #expect(controller.viewState().sections.isEmpty)
        #expect(
            controller.viewState().placeholder == SettingsScreenPlaceholderState(
                title: "Unable to Load Settings",
                systemImage: "exclamationmark.triangle",
                description: "Settings are unavailable in the current app environment.",
                actionTitle: "Retry"
            )
        )
    }

    @Test
    func readingShellSourceSwitchResetsArticleDetailSelectionAndTriggersReload() {
        let appState = AppState()
        let initialReloadID = appState.articleListReloadID
        let feedID = UUID()
        let articleID = UUID()

        appState.selectReadingSource(.feed(feedID))
        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: URL(string: "https://example.com/article")!)

        let reloadIDBeforeSwitch = appState.articleListReloadID

        appState.selectReadingSource(.inbox)

        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedWebViewRoute == nil)
        #expect(reloadIDBeforeSwitch != initialReloadID)
        #expect(appState.articleListReloadID != reloadIDBeforeSwitch)
    }

    @Test
    func readingShellSelectingSameSourceDoesNotResetSelectionOrTriggerReload() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectReadingSource(.feed(feedID))
        appState.selectedArticleID = articleID

        let reloadIDBeforeReselect = appState.articleListReloadID

        appState.selectReadingSource(.feed(feedID))

        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.articleListReloadID == reloadIDBeforeReselect)
    }

    @Test
    func readingShellSourcesFilterSwitchUpdatesActiveFilterWithoutBreakingNavigationContext() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectReadingSource(.feed(feedID))
        appState.selectedArticleID = articleID
        let reloadIDBeforeFilterSwitch = appState.articleListReloadID

        appState.selectSourcesFilter(.starred)

        #expect(appState.selectedSourcesFilter == .starred)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedWebViewRoute == nil)
        #expect(appState.articleListReloadID == reloadIDBeforeFilterSwitch)
    }

    @Test
    func readingShellReapplyingSameSourcesFilterKeepsShellStateStable() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/sources-filter-article")!

        appState.selectSourcesFilter(.unread)
        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: webURL)

        let reloadIDBeforeReapplyingFilter = appState.articleListReloadID

        appState.selectSourcesFilter(.unread)

        #expect(appState.selectedSourcesFilter == .unread)
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: articleID, url: webURL)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: articleID, url: webURL))
        #expect(appState.articleListReloadID == reloadIDBeforeReapplyingFilter)
    }

    @Test
    func folderSelectionInheritsActiveSourcesFilterForSelectedFolder() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/news-feed.xml",
                "https://example.com/tech-feed.xml"
            ]
        )
        let newsFeed = try #require(feeds.first)
        let techFeed = try #require(feeds.last)
        let newsFolder = Folder(name: "News")
        newsFeed.folder = newsFolder
        try harness.saveModelContext()

        let unreadNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-unread",
            url: "https://example.com/news/unread",
            title: "Unread News"
        )
        let starredNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-starred",
            url: "https://example.com/news/starred",
            title: "Starred News"
        )
        let readNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-read",
            url: "https://example.com/news/read",
            title: "Read News"
        )
        let starredTechArticle = try harness.insertArticle(
            feed: techFeed,
            externalID: "tech-starred",
            url: "https://example.com/tech/starred",
            title: "Starred Tech"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredNewsArticle, at: .now)
        _ = try stateService.markAsRead(article: starredNewsArticle, at: .now)
        _ = try stateService.markAsRead(article: readNewsArticle, at: .now)
        _ = try stateService.toggleStarred(article: starredTechArticle, at: .now)

        let unreadItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .unread
        )
        let resolvedUnreadItems = try #require(unreadItems)

        let starredItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .starred
        )
        let resolvedStarredItems = try #require(starredItems)

        let allItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .all
        )
        let resolvedAllItems = try #require(allItems)

        #expect(resolvedUnreadItems.map(\.id) == [unreadNewsArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredNewsArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [readNewsArticle.id, starredNewsArticle.id, unreadNewsArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == newsFeed.id })
    }

    @Test
    func feedSelectionInheritsActiveSourcesFilterForSelectedSource() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/source-feed.xml"]).first)

        let unreadArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-unread",
            url: "https://example.com/source/unread",
            title: "Unread Source"
        )
        let starredArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-starred",
            url: "https://example.com/source/starred",
            title: "Starred Source"
        )
        let readArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-read",
            url: "https://example.com/source/read",
            title: "Read Source"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(article: readArticle, at: .now)

        let unreadItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .unread
        )
        let resolvedUnreadItems = try #require(unreadItems)

        let starredItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .starred
        )
        let resolvedStarredItems = try #require(starredItems)

        let allItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .all
        )
        let resolvedAllItems = try #require(allItems)

        #expect(resolvedUnreadItems.map(\.id) == [unreadArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [readArticle.id, starredArticle.id, unreadArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == feed.id })
    }

    @Test
    func sourcesFilterArticleListFilterResolverMapsSourcesFilterToExpectedArticleFilter() {
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .allItems) == .all)
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .unread) == .unread)
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .starred) == .starred)
    }

    @Test
    func sourcesSmartViewsShowOnlyActiveFilterRow() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: true) == [.allItems])
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: true) == [.unread])
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: true) == [.starred])
    }

    @Test
    func sourcesSmartViewsAreHiddenWhenThereAreNoFeeds() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: false).isEmpty)
    }

    @Test
    func sourcesSelectionBehaviorKeepsCurrentFeedSelectionWhenItRemainsVisible() {
        let visibleFeedID = UUID()

        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .feed(visibleFeedID),
            filter: .starred,
            visibleFeedIDs: [visibleFeedID],
            visibleFolderNames: []
        )

        #expect(selection == .feed(visibleFeedID))
    }

    @Test
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFeedBecomesHidden() {
        let hiddenFeedID = UUID()

        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .feed(hiddenFeedID),
            filter: .unread,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .unread)
    }

    @Test
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentSmartSelectionDoesNotMatchFilter() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .inbox,
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    @Test
    func sourcesSelectionBehaviorKeepsNoSelectionWhenThereIsNoCurrentSelection() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: nil,
            filter: .allItems,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == nil)
    }

    @Test
    func sourcesSelectionBehaviorKeepsCurrentFolderSelectionWhenItRemainsVisible() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .unread,
            visibleFeedIDs: [],
            visibleFolderNames: ["News"]
        )

        #expect(selection == .folder("News"))
    }

    @Test
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFolderBecomesHidden() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    @Test
    func sourcesSidebarShowsOnlyFeedsWithStarredArticlesWhenStarredFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .starred,
            starredFeedIDs: [feedTwoID]
        )

        #expect(filteredFeeds.map(\.id) == [feedTwoID])
    }

    @Test
    func sourcesSidebarKeepsAllFeedsVisibleForAllItemsFilter() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let allItemsFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .allItems,
            starredFeedIDs: [feedTwoID]
        )

        #expect(allItemsFeeds.map(\.id) == feeds.map(\.id))
        #expect(allItemsFeeds.map(\.unreadCount) == feeds.map(\.unreadCount))
    }

    @Test
    func sourcesSidebarShowsOnlyFeedsWithUnreadArticlesWhenUnreadFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .unread,
            starredFeedIDs: []
        )

        #expect(filteredFeeds.map(\.id) == [feedOneID])
    }

    @Test
    func sourcesSidebarHidesFoldersSectionWhenFilteredFeedsDoNotContainFolders() {
        let ungroupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Ungrouped Feed"),
            unreadCount: 1
        )

        let groups = FolderSidebarGroup.groups(from: [ungroupedFeed])

        #expect(groups.isEmpty)
    }

    @Test
    func sourcesSidebarHidesUngroupedSectionWhenFilteredFeedsDoNotContainUngroupedSources() {
        let folder = Folder(name: "News")
        let groupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Grouped Feed", folder: folder),
            unreadCount: 1
        )

        let ungroupedFeeds = SidebarUngroupedFeeds.visibleFeeds(from: [groupedFeed])

        #expect(ungroupedFeeds.isEmpty)
    }

    @Test
    func readingShellOpenArticleWebViewSetsPresentedRouteAndPreservesArticleContext() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/webview-article")!

        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: webURL)

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: articleID, url: webURL)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: articleID, url: webURL))
    }

    @Test
    func readingShellClosingArticleWebViewRestoresArticleDetailRoute() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/webview-close")!

        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: webURL)

        appState.dismissPresentedWebView()

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedWebViewRoute == nil)
    }

    @Test
    func shellActionEntryPointsUpdateSelectionAndFilterInAppState() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)
        harness.dependencies.applySourcesFilter(.unread, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.selectedSourcesFilter == .unread)

        harness.dependencies.showInbox(using: appState)

        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)

        harness.dependencies.showFolder(named: "News", using: appState)

        #expect(appState.selectedSidebarSelection == .folder("News"))
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)

        harness.dependencies.showUnread(using: appState)
        #expect(appState.selectedSidebarSelection == .unread)

        harness.dependencies.showStarred(using: appState)
        #expect(appState.selectedSidebarSelection == .starred)
    }

    @Test
    func settingsPresentationStateLivesInAppStateAndDoesNotResetReadingShellContext() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)

        harness.dependencies.showSettings(using: appState)

        #expect(appState.isPresentingSettingsScreen)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))

        harness.dependencies.dismissSettings(using: appState)

        #expect(appState.isPresentingSettingsScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
    }

    @Test
    func shellActionEntryPointsOpenAndCloseArticleWebViewViaDependencies() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/shell-web.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "shell-web-article",
            url: "https://example.com/articles/1",
            title: "Shell Web Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/1/canonical"
        try harness.saveModelContext()
        let readerArticle = try harness.dependencies.articleQueryService?.fetchReaderArticle(id: articleModel.id)
        let article = try #require(readerArticle)

        harness.dependencies.selectArticle(id: article.id, using: appState)
        harness.dependencies.openArticleInWebView(article, using: appState)

        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!))

        harness.dependencies.closePresentedArticleWebView(using: appState)

        #expect(appState.selectedDetailRoute == .article(article.id))
        #expect(appState.presentedWebViewRoute == nil)
    }

    @Test
    func shellActionEntryPointsSelectArticleOpensWebViewWhenDefaultReaderModeIsBrowser() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/default-reader-mode.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "default-browser-article",
            url: "https://example.com/articles/browser-mode",
            title: "Default Browser Mode Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/browser-mode/canonical"
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(defaultReaderMode: .browser)
        )
        try harness.saveModelContext()

        harness.dependencies.selectArticle(id: articleModel.id, using: appState)

        #expect(appState.selectedArticleID == articleModel.id)
        #expect(
            appState.selectedDetailRoute == .webView(
                ArticleWebViewRoute(
                    articleID: articleModel.id,
                    url: URL(string: "https://example.com/articles/browser-mode/canonical")!
                )
            )
        )
        #expect(
            appState.presentedWebViewRoute == ArticleWebViewRoute(
                articleID: articleModel.id,
                url: URL(string: "https://example.com/articles/browser-mode/canonical")!
            )
        )
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSourceTriggersReloadAfterFeedRefresh() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/shell-refresh-current.xml": .response(
                    statusCode: 304,
                    headers: ["ETag": "\"etag-shell-current\""],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/shell-refresh-current.xml"]).first)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let reloadIDAfterSourceSelection = appState.articleListReloadID

        let result = await harness.dependencies.refreshCurrentSource(using: appState)

        #expect(result?.status == .notModified)
        #expect(appState.articleListReloadID != reloadIDAfterSourceSelection)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshVisibleSourcesTriggersReloadAfterBatchRefresh() async throws {
        let urls = [
            "https://example.com/shell-refresh-all-1.xml",
            "https://example.com/shell-refresh-all-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        let result = await harness.dependencies.refreshVisibleSources(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesOnlyFolderFeeds() async throws {
        let urls = [
            "https://example.com/folder-refresh-1.xml",
            "https://example.com/folder-refresh-2.xml",
            "https://example.com/folder-refresh-3.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-2\""],
                body: ""
            ),
            urls[2]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-3\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: urls)
        let techFolder = Folder(name: "Tech")
        feeds[0].folder = techFolder
        feeds[1].folder = techFolder
        try harness.saveModelContext()
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID

        harness.dependencies.showFolder(named: "Tech", using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesAllFeedsForInbox() async throws {
        let urls = [
            "https://example.com/inbox-refresh-1.xml",
            "https://example.com/inbox-refresh-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)

        harness.dependencies.showInbox(using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
    }

    @Test
    func feedNormalizationKeepsFaviconLikeIconURLAndNormalizesIt() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com",
                iconURL: "HTTPS://CDN.EXAMPLE.COM/Favicon-32x32.png?cache=1#fragment"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/")
        #expect(normalized.metadata.iconURL == "https://cdn.example.com/Favicon-32x32.png?cache=1")
    }

    @Test
    func feedNormalizationRewritesLogoAssetToSiteFaviconWhenSiteURLIsKnown() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "https://example.com/news/",
                iconURL: "https://cdn.example.com/assets/header-logo.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func feedNormalizationKeepsOriginalIconURLWhenItCannotBuildSiteFaviconFallback() {
        let feed = ParsedFeedDTO(
            kind: .atom,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                iconURL: "https://cdn.example.com/assets/banner-logo.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://cdn.example.com/assets/banner-logo.png")
    }

    @Test
    func feedNormalizationUsesSiteFaviconWhenFeedDidNotProvideIconURL() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com/news"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/news")
        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func sourceIconCacheReturnsCachedDataWithoutSecondNetworkRequest() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary"
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient)

        let firstLoad = try await service.imageData(for: iconURL)
        let secondLoad = try await service.imageData(for: iconURL)

        #expect(firstLoad == Data("icon-binary".utf8))
        #expect(secondLoad == firstLoad)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test
    func sourceIconCacheSharesInFlightRequestBetweenConcurrentConsumers() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary",
                    delayNanoseconds: 50_000_000
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient)

        async let firstLoad = service.imageData(for: iconURL)
        async let secondLoad = service.imageData(for: iconURL)
        let (firstResult, secondResult) = try await (firstLoad, secondLoad)

        #expect(firstResult == secondResult)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
        #expect(await httpClient.maxConcurrentExecutions() == 1)
    }
}

private func makeArticleListItemDTO(
    id: UUID = UUID(),
    feedID: UUID = UUID(),
    feedTitle: String = "Feed",
    articleExternalID: String = "article",
    title: String = "Article",
    summary: String? = "Summary",
    publishedAt: Date? = nil,
    isRead: Bool = false,
    isStarred: Bool = false
) -> ArticleListItemDTO {
    ArticleListItemDTO(
        id: id,
        feedID: feedID,
        feedTitle: feedTitle,
        articleExternalID: articleExternalID,
        title: title,
        summary: summary,
        author: nil,
        publishedAt: publishedAt,
        fetchedAt: .now,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: false
    )
}

@MainActor
private func makeReaderArticleDTO(
    id: UUID = UUID(),
    feedID: UUID = UUID(),
    feedTitle: String = "Feed",
    feedSiteURL: String? = "https://example.com",
    articleExternalID: String = "article",
    title: String = "Article",
    summary: String? = "Summary",
    contentHTML: String? = nil,
    contentText: String? = nil,
    author: String? = "Author",
    publishedAt: Date? = nil,
    articleURL: String = "https://example.com/articles/1",
    canonicalURL: String? = "https://example.com/articles/1/canonical",
    imageURL: String? = nil,
    isRead: Bool = false,
    isStarred: Bool = false,
    isHidden: Bool = false
) -> ReaderArticleDTO {
    ReaderArticleDTO(
        id: id,
        feedID: feedID,
        feedTitle: feedTitle,
        feedSiteURL: feedSiteURL,
        articleExternalID: articleExternalID,
        title: title,
        summary: summary,
        contentHTML: contentHTML,
        contentText: contentText,
        author: author,
        publishedAt: publishedAt,
        updatedAtSource: nil,
        articleURL: articleURL,
        canonicalURL: canonicalURL,
        imageURL: imageURL,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: isHidden
    )
}

private extension RSSReaderTests {
    static func validRSSFeedXML(
        channelTitle: String,
        channelLink: String,
        language: String,
        itemTitle: String,
        itemLink: String,
        itemGUID: String,
        itemDescription: String,
        pubDate: String
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>\(channelTitle)</title>
            <link>\(channelLink)</link>
            <description>Integration test feed</description>
            <language>\(language)</language>
            <item>
              <title>\(itemTitle)</title>
              <link>\(itemLink)</link>
              <guid isPermaLink="false">\(itemGUID)</guid>
              <description>\(itemDescription)</description>
              <pubDate>\(pubDate)</pubDate>
            </item>
          </channel>
        </rss>
        """
    }
}

private struct TestHarness {
    let dependencies: AppDependencies
    let modelContainer: ModelContainer
    let feedRepository: SwiftDataFeedRepository
    let articleRepository: SwiftDataArticleRepository
    let articleStateRepository: SwiftDataArticleStateRepository
    let articleStateService: ArticleStateService
    let feedFetchLogRepository: SwiftDataFeedFetchLogRepository
    let service: FeedRefreshService
    let httpClient: ScriptedHTTPClient

    @MainActor
    static func make(httpClient: ScriptedHTTPClient) throws -> TestHarness {
        let schema = Schema([
            AppSettings.self,
            Article.self,
            ArticleState.self,
            Feed.self,
            FeedFetchLog.self,
            Folder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = modelContainer.mainContext
        let feedFetcher = FeedFetcher(
            httpClient: httpClient,
            retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
        )
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: httpClient,
            feedFetcher: feedFetcher,
            modelContainer: modelContainer
        )

        let feedRepository = SwiftDataFeedRepository(modelContext: modelContext)
        let articleRepository = SwiftDataArticleRepository(modelContext: modelContext)
        let articleStateRepository = SwiftDataArticleStateRepository(modelContext: modelContext)
        let articleStateService = ArticleStateService(
            logger: TestLogger(),
            articleStateRepository: articleStateRepository
        )
        let feedFetchLogRepository = SwiftDataFeedFetchLogRepository(modelContext: modelContext)
        let service = FeedRefreshService(
            logger: TestLogger(),
            feedFetcher: FeedFetcher(
                httpClient: httpClient,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: feedRepository,
            articleRepository: articleRepository,
            feedFetchLogRepository: feedFetchLogRepository
        )

        return TestHarness(
            dependencies: dependencies,
            modelContainer: modelContainer,
            feedRepository: feedRepository,
            articleRepository: articleRepository,
            articleStateRepository: articleStateRepository,
            articleStateService: articleStateService,
            feedFetchLogRepository: feedFetchLogRepository,
            service: service,
            httpClient: httpClient
        )
    }

    @MainActor
    func fetchFeed(id: UUID) throws -> Feed? {
        try feedRepository.fetchFeed(id: id)
    }

    @MainActor
    func insertFeeds(urls: [String]) throws -> [Feed] {
        try urls.map { url in
            let title = URL(string: url)?.lastPathComponent ?? url
            let feed = Feed(
                url: url,
                title: title,
                lastETag: "\"etag-old\"",
                lastModifiedHeader: "Mon, 01 Jan 2024 12:00:00 GMT"
            )
            return try feedRepository.insert(feed)
        }
    }

    @MainActor
    func insertArticle(
        feed: Feed,
        externalID: String,
        guid: String? = nil,
        url: String,
        title: String,
        isDeletedAtSource: Bool = false
    ) throws -> Article {
        let article = Article(
            feed: feed,
            externalID: externalID,
            guid: guid,
            url: url,
            title: title,
            isDeletedAtSource: isDeletedAtSource
        )
        modelContainer.mainContext.insert(article)
        try modelContainer.mainContext.save()
        return article
    }

    @MainActor
    func saveModelContext() throws {
        try modelContainer.mainContext.save()
    }
}

private struct TestLogger: Logging {
    func debug(_ message: @autoclosure () -> String) {}
    func info(_ message: @autoclosure () -> String) {}
    func error(_ message: @autoclosure () -> String) {}
}

private actor ScriptedHTTPClient: HTTPClient {
    enum Step: Sendable {
        case response(statusCode: Int, headers: [String: String], body: String)
        case delayedResponse(statusCode: Int, headers: [String: String], body: String, delayNanoseconds: UInt64)
        case invalidResponse
        case urlError(URLError.Code)
        case cancelled
    }

    private var steps: [Step]
    private var responsesByURL: [String: Step]
    private var requests: [HTTPRequest] = []
    private var inFlightExecutions = 0
    private var maxConcurrentExecutionCount = 0

    init(
        steps: [Step] = [],
        responsesByURL: [String: Step] = [:]
    ) {
        self.steps = steps
        self.responsesByURL = responsesByURL
    }

    private func beginExecution() {
        inFlightExecutions += 1
        maxConcurrentExecutionCount = max(maxConcurrentExecutionCount, inFlightExecutions)
    }

    private func endExecution() {
        inFlightExecutions = max(0, inFlightExecutions - 1)
    }

    private func makeResponse(
        request: HTTPRequest,
        statusCode: Int,
        headers: [String: String],
        body: String
    ) async -> HTTPResponse {
        await MainActor.run {
            HTTPResponse(
                url: request.url,
                statusCode: statusCode,
                headers: headers,
                body: Data(body.utf8)
            )
        }
    }

    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        beginExecution()
        defer { endExecution() }

        let requestURLString = await MainActor.run {
            request.url.absoluteString
        }

        let step: Step
        if let routedStep = responsesByURL.removeValue(forKey: requestURLString) {
            step = routedStep
        } else if steps.isEmpty == false {
            step = steps.removeFirst()
        } else {
            throw URLError(.badServerResponse)
        }

        switch step {
        case .response(let statusCode, let headers, let body):
            return await makeResponse(
                request: request,
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        case .delayedResponse(let statusCode, let headers, let body, let delayNanoseconds):
            try await Task.sleep(nanoseconds: delayNanoseconds)
            return await makeResponse(
                request: request,
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        case .invalidResponse:
            throw HTTPClientError.invalidResponse
        case .urlError(let code):
            throw URLError(code)
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedRequests() -> [HTTPRequest] {
        requests
    }

    func maxConcurrentExecutions() -> Int {
        maxConcurrentExecutionCount
    }
}
