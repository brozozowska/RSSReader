import Foundation
import SwiftUI
import SwiftData

// MARK: - AppDependencies protocol
public protocol AppDependenciesProtocol {
    var logger: Logging { get }
    var httpClient: any HTTPClient { get }
    var feedFetcher: any FeedFetching { get }
    var modelContainer: ModelContainer? { get }
}

public final class AppDependencies: AppDependenciesProtocol {
    
    public let logger: Logging
    public let httpClient: any HTTPClient
    public let feedFetcher: any FeedFetching
    let feedRefreshService: FeedRefreshService?
    let feedRepository: (any FeedRepository)?
    let articleRepository: (any ArticleRepository)?
    let articleStateService: ArticleStateService?
    let articleQueryService: (any ArticleQueryService)?
    let articleStateRepository: (any ArticleStateRepository)?
    let appSettingsRepository: (any AppSettingsRepository)?
    let feedFetchLogRepository: (any FeedFetchLogRepository)?
    public let modelContainer: ModelContainer?

    public init(
        logger: Logging,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        feedFetcher: (any FeedFetching)? = nil,
        modelContainer: ModelContainer? = nil
    ) {
        let feedRepository = modelContainer.map { container in
            SwiftDataFeedRepository(modelContext: container.mainContext)
        }
        let articleRepository = modelContainer.map { container in
            SwiftDataArticleRepository(modelContext: container.mainContext)
        }
        let articleStateRepository = modelContainer.map { container in
            SwiftDataArticleStateRepository(modelContext: container.mainContext)
        }
        let articleQueryService: (any ArticleQueryService)? = {
            guard let articleRepository,
                  let articleStateRepository else {
                return nil
            }

            return DefaultArticleQueryService(
                articleRepository: articleRepository,
                articleStateRepository: articleStateRepository
            )
        }()
        let articleStateService = articleStateRepository.map { repository in
            ArticleStateService(
                logger: logger,
                articleStateRepository: repository
            )
        }
        let appSettingsRepository = modelContainer.map { container in
            SwiftDataAppSettingsRepository(modelContext: container.mainContext)
        }
        let feedFetchLogRepository = modelContainer.map { container in
            SwiftDataFeedFetchLogRepository(modelContext: container.mainContext)
        }
        let resolvedFeedFetcher = feedFetcher ?? Self.makeFeedFetcher(
            httpClient: httpClient
        )
        let feedRefreshService: FeedRefreshService? = {
            guard let feedRepository, let articleRepository else {
                return nil
            }

            return FeedRefreshService(
                logger: logger,
                feedFetcher: resolvedFeedFetcher,
                feedRepository: feedRepository,
                articleRepository: articleRepository,
                feedFetchLogRepository: feedFetchLogRepository
            )
        }()

        self.logger = logger
        self.httpClient = httpClient
        self.modelContainer = modelContainer
        self.feedRefreshService = feedRefreshService
        self.feedRepository = feedRepository
        self.articleRepository = articleRepository
        self.articleStateService = articleStateService
        self.articleStateRepository = articleStateRepository
        self.articleQueryService = articleQueryService
        self.appSettingsRepository = appSettingsRepository
        self.feedFetchLogRepository = feedFetchLogRepository
        self.feedFetcher = resolvedFeedFetcher
    }
}

// MARK: - Factory
public extension AppDependencies {
    static func makeDefault() -> AppDependencies {
#if DEBUG
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .debug, base: baseLogger)
#else
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .info, base: baseLogger)
#endif
        return AppDependencies(logger: logger)
    }
    
    static func makeWithSwiftData(models: [any PersistentModel.Type]) -> AppDependencies {
#if DEBUG
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .debug, base: baseLogger)
#else
        let baseLogger = OSLogger(category: "app")
        let logger: Logging = FilteredLogger(minLevel: .info, base: baseLogger)
#endif
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let modelContainer = try? ModelContainer(for: schema, configurations: [configuration])
        return AppDependencies(logger: logger, modelContainer: modelContainer)
    }
}

extension AppDependencies {
    @MainActor
    func refreshFeed(id feedID: UUID) async -> FeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }

        return await feedRefreshService.refresh(feedID: feedID)
    }

    @MainActor
    func refreshSelectedFeed(using appState: AppState) async -> FeedRefreshResult? {
        guard let selectedFeedID = appState.selectedFeedID else {
            logger.info("Skipped manual refresh because no feed is selected")
            return nil
        }

        return await refreshFeed(id: selectedFeedID)
    }

    @MainActor
    func refreshAllFeeds() async -> FeedRefreshBatchResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }

        return await feedRefreshService.refreshAllActiveFeeds()
    }

    @MainActor
    func refreshFeedsForBackground() async -> BackgroundFeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }

        return await feedRefreshService.refreshAllActiveFeedsForBackground()
    }
}

private extension AppDependencies {
    static func makeFeedFetcher(
        httpClient: any HTTPClient
    ) -> any FeedFetching {
        FeedFetcher(httpClient: httpClient)
    }
}
