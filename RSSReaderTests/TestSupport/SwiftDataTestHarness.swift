import Foundation
import SwiftData
@testable import RSSReader

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
            unreadAppIconBadgeService: NoOpUnreadAppIconBadgeService(),
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
        archivedAt: Date? = nil
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
            archivedAt: archivedAt
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
