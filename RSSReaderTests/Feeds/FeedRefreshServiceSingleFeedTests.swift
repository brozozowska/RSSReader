import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Single Feed")
@MainActor
struct FeedRefreshServiceSingleFeedTests {
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
                        body: makeValidRSSFeedXML(
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
    func singleFeedRefreshPersistsEveryAcceptedCanonicalGUIDAndContentEntry() async throws {
        let feedURL = "https://example.com/persistable-entry-contract.xml"
        let canonicalURL = "https://example.com/articles/canonical-only"
        let contentOnlyURL = "https://example.com/articles/content-only"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
                          <channel>
                            <title>Persistable Entry Contract</title>
                            <link>https://example.com/</link>
                            <description>Persistence contract fixture</description>
                            <item>
                              <comments>\(canonicalURL)</comments>
                              <description>Canonical summary</description>
                            </item>
                            <item>
                              <guid isPermaLink="false">guid-content-only</guid>
                              <content:encoded><![CDATA[<p>GUID-only readable content</p>]]></content:encoded>
                            </item>
                            <item>
                              <link>\(contentOnlyURL)</link>
                              <content:encoded><![CDATA[<p>URL content without title</p>]]></content:encoded>
                            </item>
                            <item>
                              <content:encoded><![CDATA[<p>Reference-free content</p>]]></content:encoded>
                            </item>
                          </channel>
                        </rss>
                        """
                    )
                ]
            )
        )
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)

        let result = await harness.service.refresh(feedID: feed.id)
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let canonicalArticle = try #require(
            articles.first { $0.canonicalURL == canonicalURL }
        )
        let guidContentArticle = try #require(
            articles.first { $0.guid == "guid-content-only" }
        )
        let urlContentArticle = try #require(
            articles.first { $0.url == contentOnlyURL }
        )

        #expect(result.status == .fetched)
        #expect(result.processedEntryCount == 4)
        #expect(result.upsertedEntryCount == 3)
        #expect(result.rejectedEntryCount == 1)
        #expect(result.diagnosticsSummary.rejectedEntryCount == 1)
        #expect(articles.count == 3)

        #expect(canonicalArticle.url == canonicalURL)
        #expect(canonicalArticle.title == "Canonical summary")
        #expect(guidContentArticle.url.isEmpty)
        #expect(guidContentArticle.title.isEmpty)
        #expect(guidContentArticle.contentHTML == "<p>GUID-only readable content</p>")
        #expect(urlContentArticle.title.isEmpty)
        #expect(urlContentArticle.contentHTML == "<p>URL content without title</p>")
    }

    @Test
    func singleFeedRefreshPreservesExistingIconURL() async throws {
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Updated Feed Title",
                            channelLink: "https://example.com/",
                            channelImageURL: "https://example.com/new-icon.png",
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
            iconURL: "https://example.com/original-icon.png"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.iconURL == "https://example.com/original-icon.png")
    }

    @Test
    func singleFeedRefreshFillsMissingIconURLFromDiscovery() async throws {
        let discoveredIconURL = try #require(URL(string: "https://example.com/discovered-icon.png"))
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Updated Feed Title",
                            channelLink: "https://example.com/",
                            channelImageURL: "https://example.com/new-icon.png",
                            language: "en",
                            itemTitle: "Article One",
                            itemLink: "https://example.com/articles/1",
                            itemGUID: "article-1",
                            itemDescription: "Readable summary",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            ),
            feedIconDiscoveryService: StubFeedIconDiscoveryService(iconURL: discoveredIconURL)
        )

        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Old Feed Title"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.iconURL == discoveredIconURL.absoluteString)
    }

    @Test
    func singleFeedRefreshReplacesExistingIconURLWhenDiscoveryFindsWorkingAlternative() async throws {
        let discoveredIconURL = try #require(URL(string: "https://example.com/discovered-icon.png"))
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
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
            ),
            feedIconDiscoveryService: StubFeedIconDiscoveryService(iconURL: discoveredIconURL)
        )

        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Old Feed Title",
            iconURL: "https://example.com/stale-icon.png"
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.iconURL == discoveredIconURL.absoluteString)
    }

    @Test
    func singleFeedRefreshNotModifiedRunsIconDiscoveryForExistingIconURL() async throws {
        let iconURL = try #require(URL(string: "https://example.com/original-icon.png"))
        let discoveryService = RecordingFeedIconDiscoveryService(iconURL: iconURL)
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
            ),
            feedIconDiscoveryService: discoveryService
        )

        let feed = Feed(
            url: "https://example.com/feed.xml",
            siteURL: "https://example.com/",
            title: "Stable Feed Title",
            iconURL: iconURL.absoluteString,
            lastETag: "\"etag-old\""
        )
        try harness.feedRepository.insert(feed)

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .notModified)
        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.iconURL == iconURL.absoluteString)
        #expect(discoveryService.calls.count == 1)
        #expect(discoveryService.calls.first?.metadataIconURL == iconURL)
        #expect(discoveryService.calls.first?.siteURL == URL(string: "https://example.com/"))
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
    func repeatedFetchedAndNotModifiedRefreshKeepUpdatedOnlyAtomEffectiveDateStable() async throws {
        let sourceUpdatedAt = try #require(
            FeedDateParsingService.parse("2024-01-02T10:15:30.486Z")
        )
        let atomXML = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Apple-like Updated-only Feed</title>
          <link href="https://example.com/" />
          <updated>2024-01-10T12:00:00Z</updated>
          <entry>
            <id>updated-only-entry</id>
            <title>Stable Source Date</title>
            <link href="https://example.com/articles/updated-only" />
            <summary>Updated-only Atom entry.</summary>
            <updated>2024-01-02T10:15:30.486Z</updated>
          </entry>
        </feed>
        """
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [
                    .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/atom+xml; charset=utf-8"],
                        body: atomXML
                    ),
                    .delayedResponse(
                        statusCode: 200,
                        headers: ["Content-Type": "application/atom+xml; charset=utf-8"],
                        body: atomXML,
                        delayNanoseconds: 1_000_000
                    ),
                    .response(statusCode: 304, headers: [:], body: "")
                ]
            )
        )
        let feed = Feed(url: "https://example.com/updated-only.atom", title: "Updated-only")
        try harness.feedRepository.insert(feed)

        let firstResult = await harness.service.refresh(feedID: feed.id)
        let firstArticle = try #require(try harness.articleRepository.fetchArticles(feedID: feed.id).first)
        let firstFetchedAt = firstArticle.fetchedAt

        let secondResult = await harness.service.refresh(feedID: feed.id)
        let secondArticle = try #require(try harness.articleRepository.fetchArticles(feedID: feed.id).first)
        let secondFetchedAt = secondArticle.fetchedAt

        let notModifiedResult = await harness.service.refresh(feedID: feed.id)
        let notModifiedArticle = try #require(
            try harness.articleRepository.fetchArticles(feedID: feed.id).first
        )

        #expect(firstResult.status == .fetched)
        #expect(secondResult.status == .fetched)
        #expect(notModifiedResult.status == .notModified)
        #expect(firstArticle.publishedAt == nil)
        #expect(firstArticle.updatedAtSource == sourceUpdatedAt)
        #expect(firstArticle.querySortDate == sourceUpdatedAt)
        #expect(secondFetchedAt > firstFetchedAt)
        #expect(secondArticle.querySortDate == sourceUpdatedAt)
        #expect(notModifiedArticle.fetchedAt == secondFetchedAt)
        #expect(notModifiedArticle.querySortDate == sourceUpdatedAt)
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
}
