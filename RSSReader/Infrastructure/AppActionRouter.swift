import Foundation

extension AppDependencies {
    var appActions: AppActionRouter {
        AppActionRouter(dependencies: self)
    }
}

struct AppActionRouter {
    let dependencies: AppDependencies

    var logger: Logging { dependencies.logger }
    var articleQueryService: (any ArticleQueryService)? { dependencies.articleQueryService }
    var articleStateService: (any ArticleStateServicing)? { dependencies.articleStateService }
    var folderRepository: (any FolderRepository)? { dependencies.folderRepository }
    var feedManagementService: (any FeedManagementService)? { dependencies.feedManagementService }
    var feedRefreshService: FeedRefreshService? { dependencies.feedRefreshService }
    var feedRepository: (any FeedRepository)? { dependencies.feedRepository }
    var appSettingsService: (any AppSettingsService)? { dependencies.appSettingsService }
    var articleRetentionCleanupService: (any ArticleRetentionCleanupServicing)? {
        dependencies.articleRetentionCleanupService
    }
    var persistenceBoundedGrowthCleanupService: (any PersistenceBoundedGrowthCleanupServicing)? {
        dependencies.persistenceBoundedGrowthCleanupService
    }
    var backgroundRefreshService: (any BackgroundRefreshService)? { dependencies.backgroundRefreshService }
    var unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)? {
        dependencies.unreadAppIconBadgeService
    }
    var feedSaveRefreshTaskStore: AppDependencyTaskStore? { dependencies.feedSaveRefreshTaskStore }
}
