import Foundation
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
        #expect(resolvedSnapshot.unreadSmartCount == 2)
        #expect(resolvedSnapshot.starredSmartCount == 1)
        #expect(resolvedSnapshot.starredFeedIDs == [secondFeed.id])
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
    func readingShellFilterSwitchUpdatesActiveFilterWithoutBreakingSelectionConsistency() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectReadingSource(.feed(feedID))
        appState.selectedArticleID = articleID
        let reloadIDBeforeFilterSwitch = appState.articleListReloadID

        appState.selectArticleListFilter(.starred)

        #expect(appState.selectedArticleListFilter == .starred)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedWebViewRoute == nil)
        #expect(appState.articleListReloadID == reloadIDBeforeFilterSwitch)
    }

    @Test
    func readingShellApplyingSameFilterKeepsShellStateStable() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/filter-article")!

        appState.selectArticleListFilter(.unread)
        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: webURL)

        let reloadIDBeforeReapplyingFilter = appState.articleListReloadID

        appState.selectArticleListFilter(.unread)

        #expect(appState.selectedArticleListFilter == .unread)
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: articleID, url: webURL)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: articleID, url: webURL))
        #expect(appState.articleListReloadID == reloadIDBeforeReapplyingFilter)
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
    func folderSelectionUsesUnreadOnlyArticlesForSelectedFolder() throws {
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
        _ = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-read",
            url: "https://example.com/news/read",
            title: "Read News"
        )
        _ = try harness.insertArticle(
            feed: techFeed,
            externalID: "tech-unread",
            url: "https://example.com/tech/unread",
            title: "Unread Tech"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.markAsRead(feedID: newsFeed.id, articleExternalID: "news-read", at: .now)

        let items = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .unread
        )
        let resolvedItems = try #require(items)

        #expect(resolvedItems.map(\.id) == [unreadNewsArticle.id])
        #expect(resolvedItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedItems.allSatisfy { $0.isRead == false })
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
    func sourcesSelectionBehaviorUsesActiveSmartRowWhenThereIsNoCurrentSelection() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: nil,
            filter: .allItems,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .inbox)
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
        harness.dependencies.applyArticleListFilter(.starred, using: appState)
        harness.dependencies.applySourcesFilter(.unread, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.selectedArticleListFilter == .starred)
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
