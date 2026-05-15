import Foundation
import SwiftUI
import SwiftData
@testable import RSSReader

func makeArticleListItemDTO(
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
func makeReaderArticleDTO(
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

func makeValidRSSFeedXML(
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

struct TestHarness {
    let dependencies: AppDependencies
    let modelContainer: ModelContainer
    let feedRepository: SwiftDataFeedRepository
    let folderRepository: SwiftDataFolderRepository
    let articleRepository: SwiftDataArticleRepository
    let articleStateRepository: SwiftDataArticleStateRepository
    let articleStateService: ArticleStateService
    let feedFetchLogRepository: SwiftDataFeedFetchLogRepository
    let service: FeedRefreshService
    let httpClient: ScriptedHTTPClient

    @MainActor
    static func make(httpClient: ScriptedHTTPClient) throws -> TestHarness {
        let schema = AppComposition.persistenceModelPartition.schema
        let configurationPlan = AppPersistenceConfigurationPlan.make(
            modelPartition: AppComposition.persistenceModelPartition,
            isStoredInMemoryOnly: true
        )
        let modelContainer = try ModelContainer(
            for: schema,
            configurations: configurationPlan.modelContainerConfigurations
        )
        let modelContext = modelContainer.mainContext
        let feedFetcher = FeedFetcher(
            httpClient: httpClient,
            retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
        )
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: httpClient,
            feedFetcher: feedFetcher,
            modelContainer: modelContainer,
            tracksFeedSaveRefreshTasks: true
        )

        let feedRepository = SwiftDataFeedRepository(modelContext: modelContext)
        let folderRepository = SwiftDataFolderRepository(modelContext: modelContext)
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
            folderRepository: folderRepository,
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
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
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

struct TestLogger: Logging {
    func debug(_ message: @autoclosure () -> String) {}
    func info(_ message: @autoclosure () -> String) {}
    func error(_ message: @autoclosure () -> String) {}
}

final class RecordingLogger: Logging {
    struct Entry: Equatable {
        let level: LogLevel
        let message: String
    }

    private(set) var entries: [Entry] = []

    func debug(_ message: @autoclosure () -> String) {
        entries.append(Entry(level: .debug, message: message()))
    }

    func info(_ message: @autoclosure () -> String) {
        entries.append(Entry(level: .info, message: message()))
    }

    func error(_ message: @autoclosure () -> String) {
        entries.append(Entry(level: .error, message: message()))
    }

    func contains(_ fragment: String, level: LogLevel? = nil) -> Bool {
        entries.contains { entry in
            let matchesLevel = level.map { entry.level == $0 } ?? true
            return matchesLevel && entry.message.contains(fragment)
        }
    }
}

extension SourceManagementScreenState {
    static func makePreviewFixture(
        presentedScenarioID: SourceManagementScenarioID? = nil
    ) -> SourceManagementScreenState {
        var state = SourceManagementScreenState()
        if let presentedScenarioID {
            state.presentScenario(presentedScenarioID)
        }
        return state
    }
}

actor ScriptedHTTPClient: HTTPClient {
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
