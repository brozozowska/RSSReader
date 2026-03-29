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
    let feedRepository: (any FeedRepository)?
    let articleRepository: (any ArticleRepository)?
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
        self.logger = logger
        self.httpClient = httpClient
        self.modelContainer = modelContainer
        self.feedRepository = modelContainer.map { container in
            SwiftDataFeedRepository(modelContext: container.mainContext)
        }
        self.articleRepository = modelContainer.map { container in
            SwiftDataArticleRepository(modelContext: container.mainContext)
        }
        self.articleStateRepository = modelContainer.map { container in
            SwiftDataArticleStateRepository(modelContext: container.mainContext)
        }
        self.appSettingsRepository = modelContainer.map { container in
            SwiftDataAppSettingsRepository(modelContext: container.mainContext)
        }
        self.feedFetchLogRepository = modelContainer.map { container in
            SwiftDataFeedFetchLogRepository(modelContext: container.mainContext)
        }
        self.feedFetcher = feedFetcher ?? Self.makeFeedFetcher(
            httpClient: httpClient,
            logger: logger,
            feedFetchLogRepository: self.feedFetchLogRepository
        )
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

private extension AppDependencies {
    static func makeFeedFetcher(
        httpClient: any HTTPClient,
        logger: Logging,
        feedFetchLogRepository: (any FeedFetchLogRepository)?
    ) -> any FeedFetching {
        guard let feedFetchLogRepository else {
            return FeedFetcher(httpClient: httpClient)
        }

        return FeedFetcher(
            httpClient: httpClient,
            logSink: { log in
                do {
                    try await MainActor.run(resultType: Void.self) {
                        try feedFetchLogRepository.insert(log)
                    }
                } catch {
                    logger.error("Failed to persist FeedFetchLog: \(error)")
                }
            }
        )
    }
}
