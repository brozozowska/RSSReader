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
    let modelContainer: ModelContainer
    let feedRepository: SwiftDataFeedRepository
    let articleRepository: SwiftDataArticleRepository
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

        let feedRepository = SwiftDataFeedRepository(modelContext: modelContext)
        let articleRepository = SwiftDataArticleRepository(modelContext: modelContext)
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
            modelContainer: modelContainer,
            feedRepository: feedRepository,
            articleRepository: articleRepository,
            feedFetchLogRepository: feedFetchLogRepository,
            service: service,
            httpClient: httpClient
        )
    }

    @MainActor
    func fetchFeed(id: UUID) throws -> Feed? {
        try feedRepository.fetchFeed(id: id)
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
        case invalidResponse
        case urlError(URLError.Code)
        case cancelled
    }

    private var steps: [Step]
    private var requests: [HTTPRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard steps.isEmpty == false else {
            throw URLError(.badServerResponse)
        }

        let step = steps.removeFirst()
        switch step {
        case .response(let statusCode, let headers, let body):
            return await MainActor.run {
                HTTPResponse(
                    url: request.url,
                    statusCode: statusCode,
                    headers: headers,
                    body: Data(body.utf8)
                )
            }
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
}
