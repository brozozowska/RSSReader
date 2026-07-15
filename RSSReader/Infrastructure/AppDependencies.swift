import CloudKit
import Foundation
import SwiftUI
import SwiftData

// MARK: - AppDependencies protocol
public protocol AppDependenciesProtocol {
    var logger: Logging { get }
    var httpClient: any HTTPClient { get }
    var feedFetcher: any FeedFetching { get }
    var feedIconCache: any FeedIconCaching { get }
    var modelContainer: ModelContainer? { get }
}

final class AppDependencyTaskStore: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []

    func append(_ task: Task<Void, Never>) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    func waitForAll() async {
        while true {
            let currentTasks = takeTasks()

            guard currentTasks.isEmpty == false else { return }

            for task in currentTasks {
                await task.value
            }
        }
    }

    private func takeTasks() -> [Task<Void, Never>] {
        lock.lock()
        let currentTasks = tasks
        tasks.removeAll()
        lock.unlock()
        return currentTasks
    }
}

public final class AppDependencies: AppDependenciesProtocol {
    
    public let logger: Logging
    public let httpClient: any HTTPClient
    public let feedFetcher: any FeedFetching
    public let feedIconCache: any FeedIconCaching
    let feedRefreshService: FeedRefreshService?
    let feedRepository: (any FeedRepository)?
    let folderRepository: (any FolderRepository)?
    let feedManagementService: (any FeedManagementService)?
    let articleRepository: (any ArticleRepository)?
    let articleStateService: ArticleStateService?
    let unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)?
    let articleRetentionCleanupService: (any ArticleRetentionCleanupServicing)?
    let persistenceBoundedGrowthCleanupService: (any PersistenceBoundedGrowthCleanupServicing)?
    let articleQueryService: (any ArticleQueryService)?
    let sidebarQueryService: (any SidebarQueryService)?
    let articleStateRepository: (any ArticleStateRepository)?
    let appSettingsRepository: (any AppSettingsRepository)?
    let appSettingsService: (any AppSettingsService)?
    let backgroundRefreshService: (any BackgroundRefreshService)?
    let backgroundRefreshRuntimePrerequisitesSource: any BackgroundRefreshRuntimePrerequisitesSnapshotting
    let backgroundRefreshValidationDiagnosticsReporter: any BackgroundRefreshValidationDiagnosticsReporting
    let backgroundRefreshForegroundHandoffCoordinator: any BackgroundRefreshForegroundHandoffCoordinating
    let backgroundRefreshScheduler: any BackgroundRefreshScheduling
    let iCloudAccountAvailabilityService: any ICloudAccountAvailabilityService
    let cloudKitRuntimeEventSource: any CloudKitRuntimeEventSource
    let persistentStoreRemoteChangeSource: any PersistentStoreRemoteChangeSource
    let syncCoordinator: SyncCoordinator?
    let feedFetchLogRepository: (any FeedFetchLogRepository)?
    public let modelContainer: ModelContainer?
    let modelContainerBootstrapFailureDescription: String?
    let syncBackedStoreReference: SyncBackedStoreReference?
    let syncBootstrapPreferenceStore: any AppSyncBootstrapPreferenceStoring
    let syncBootstrapContext: AppSyncBootstrapContext?
    let syncRuntimeOrchestrator: AppSyncRuntimeOrchestrator
    let feedSaveRefreshTaskStore: AppDependencyTaskStore?

    init(
        logger: Logging,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        feedFetcher: (any FeedFetching)? = nil,
        feedIconCache: (any FeedIconCaching)? = nil,
        modelContainer: ModelContainer? = nil,
        modelContainerBootstrapFailureDescription: String? = nil,
        syncBackedStoreReference: SyncBackedStoreReference? = nil,
        syncBootstrapPreferenceStore: (any AppSyncBootstrapPreferenceStoring)? = nil,
        syncBootstrapContext: AppSyncBootstrapContext? = nil,
        backgroundRefreshService: (any BackgroundRefreshService)? = nil,
        feedIconDiscoveryService: (any FeedIconDiscovering)? = nil,
        backgroundRefreshForegroundHandoffCoordinator: (any BackgroundRefreshForegroundHandoffCoordinating)? = nil,
        backgroundRefreshScheduler: (any BackgroundRefreshScheduling)? = nil,
        iCloudAccountAvailabilityService: (any ICloudAccountAvailabilityService)? = nil,
        cloudKitRuntimeEventSource: (any CloudKitRuntimeEventSource)? = nil,
        persistentStoreRemoteChangeSource: (any PersistentStoreRemoteChangeSource)? = nil,
        syncCoordinator: SyncCoordinator? = nil,
        unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)? = nil,
        tracksFeedSaveRefreshTasks: Bool = false
    ) {
        let feedRepository = modelContainer.map { container in
            SwiftDataFeedRepository(modelContext: container.mainContext)
        }
        let folderRepository = modelContainer.map { container in
            SwiftDataFolderRepository(modelContext: container.mainContext)
        }
        let articleRepository = modelContainer.map { container in
            SwiftDataArticleRepository(modelContext: container.mainContext)
        }
        let articleStateRepository = modelContainer.map { container in
            SwiftDataArticleStateRepository(modelContext: container.mainContext)
        }
        let appSettingsRepository = modelContainer.map { container in
            SwiftDataAppSettingsRepository(modelContext: container.mainContext)
        }
        let appSettingsService = appSettingsRepository.map { repository in
            DefaultAppSettingsService(repository: repository)
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
        let resolvedUnreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)? = unreadAppIconBadgeService ?? {
            guard let feedRepository, let articleStateRepository, let appSettingsService else {
                return nil
            }

            return UnreadAppIconBadgeService(
                logger: logger,
                feedRepository: feedRepository,
                articleStateRepository: articleStateRepository,
                appSettingsService: appSettingsService
            )
        }()
        let articleStateService = articleStateRepository.map { repository in
            ArticleStateService(
                logger: logger,
                articleStateRepository: repository,
                unreadAppIconBadgeService: resolvedUnreadAppIconBadgeService
            )
        }
        let articleRetentionCleanupService: (any ArticleRetentionCleanupServicing)? = {
            guard let feedRepository, let articleRepository, let articleStateRepository else {
                return nil
            }

            return ArticleRetentionCleanupService(
                logger: logger,
                feedRepository: feedRepository,
                articleRepository: articleRepository,
                articleStateRepository: articleStateRepository
            )
        }()
        let sidebarQueryService: (any SidebarQueryService)? = {
            guard let feedRepository,
                  let folderRepository,
                  let articleStateRepository,
                  let articleQueryService else {
                return nil
            }

            return DefaultSidebarQueryService(
                feedRepository: feedRepository,
                folderRepository: folderRepository,
                articleStateRepository: articleStateRepository,
                articleQueryService: articleQueryService
            )
        }()
        let feedFetchLogRepository = modelContainer.map { container in
            SwiftDataFeedFetchLogRepository(modelContext: container.mainContext)
        }
        let persistenceBoundedGrowthCleanupService: (any PersistenceBoundedGrowthCleanupServicing)? = {
            guard let articleRepository, let articleStateRepository, let feedFetchLogRepository else {
                return nil
            }

            return PersistenceBoundedGrowthCleanupService(
                logger: logger,
                articleRepository: articleRepository,
                articleStateRepository: articleStateRepository,
                feedFetchLogRepository: feedFetchLogRepository
            )
        }()
        let resolvedFeedFetcher = feedFetcher ?? Self.makeFeedFetcher(
            httpClient: httpClient
        )
        let feedManagementService: (any FeedManagementService)? = {
            guard let feedRepository, let folderRepository, let articleRepository else {
                return nil
            }

            return DefaultFeedManagementService(
                logger: logger,
                httpClient: httpClient,
                feedFetcher: FeedFetcher(
                    httpClient: httpClient,
                    retryPolicy: FeedRetryPolicy(maxAttempts: 1)
                ),
                feedRepository: feedRepository,
                folderRepository: folderRepository,
                articleRepository: articleRepository
            )
        }()
        let resolvedFeedIconCache = feedIconCache ?? FeedIconCacheService(httpClient: httpClient)
        let resolvedFeedIconDiscoveryService = feedIconDiscoveryService ?? FeedIconDiscoveryService(
            logger: logger,
            httpClient: httpClient,
            feedIconCache: resolvedFeedIconCache
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
                feedIconDiscoveryService: resolvedFeedIconDiscoveryService,
                feedFetchLogRepository: feedFetchLogRepository
            )
        }()
        let resolvedBackgroundRefreshService = backgroundRefreshService ?? appSettingsService.map { service in
            DefaultBackgroundRefreshService(
                logger: logger,
                appSettingsService: service,
                feedRefreshService: feedRefreshService,
                articleRetentionCleanupService: articleRetentionCleanupService
            )
        }
        let backgroundRefreshRuntimePrerequisitesSource = DefaultBackgroundRefreshRuntimePrerequisitesSource(
            backgroundRefreshService: resolvedBackgroundRefreshService
        )
        let backgroundRefreshValidationDiagnosticsReporter =
            DefaultBackgroundRefreshValidationDiagnosticsReporter(logger: logger)
        let backgroundRefreshForegroundHandoffCoordinator = backgroundRefreshForegroundHandoffCoordinator
            ?? DefaultBackgroundRefreshForegroundHandoffCoordinator()
        let backgroundRefreshScheduler = backgroundRefreshScheduler
            ?? DefaultBackgroundRefreshScheduler(logger: logger)
        let iCloudAccountAvailabilityService = iCloudAccountAvailabilityService
            ?? DefaultICloudAccountAvailabilityService(logger: logger)
        let cloudKitRuntimeEventSource = cloudKitRuntimeEventSource ?? DefaultCloudKitRuntimeEventSource()
        let persistentStoreRemoteChangeSource = persistentStoreRemoteChangeSource ?? DefaultPersistentStoreRemoteChangeSource()
        let syncBootstrapPreferenceStore = syncBootstrapPreferenceStore
            ?? AppSyncBootstrapPreferenceStore(logger: logger)
        self.logger = logger
        self.httpClient = httpClient
        self.feedIconCache = resolvedFeedIconCache
        self.modelContainer = modelContainer
        self.modelContainerBootstrapFailureDescription = modelContainerBootstrapFailureDescription
        self.syncBackedStoreReference = syncBackedStoreReference
        self.syncBootstrapPreferenceStore = syncBootstrapPreferenceStore
        self.syncBootstrapContext = syncBootstrapContext
        self.feedRefreshService = feedRefreshService
        self.feedRepository = feedRepository
        self.folderRepository = folderRepository
        self.feedManagementService = feedManagementService
        self.articleRepository = articleRepository
        self.articleStateService = articleStateService
        self.unreadAppIconBadgeService = resolvedUnreadAppIconBadgeService
        self.articleRetentionCleanupService = articleRetentionCleanupService
        self.persistenceBoundedGrowthCleanupService = persistenceBoundedGrowthCleanupService
        self.articleStateRepository = articleStateRepository
        self.articleQueryService = articleQueryService
        self.sidebarQueryService = sidebarQueryService
        self.appSettingsRepository = appSettingsRepository
        self.appSettingsService = appSettingsService
        self.backgroundRefreshService = resolvedBackgroundRefreshService
        self.backgroundRefreshRuntimePrerequisitesSource = backgroundRefreshRuntimePrerequisitesSource
        self.backgroundRefreshValidationDiagnosticsReporter = backgroundRefreshValidationDiagnosticsReporter
        self.backgroundRefreshForegroundHandoffCoordinator = backgroundRefreshForegroundHandoffCoordinator
        self.backgroundRefreshScheduler = backgroundRefreshScheduler
        self.iCloudAccountAvailabilityService = iCloudAccountAvailabilityService
        self.cloudKitRuntimeEventSource = cloudKitRuntimeEventSource
        self.persistentStoreRemoteChangeSource = persistentStoreRemoteChangeSource
        self.syncCoordinator = syncCoordinator
        self.feedFetchLogRepository = feedFetchLogRepository
        self.feedFetcher = resolvedFeedFetcher
        self.feedSaveRefreshTaskStore = tracksFeedSaveRefreshTasks
            ? AppDependencyTaskStore()
            : nil
        self.syncRuntimeOrchestrator = AppSyncRuntimeOrchestrator(
            logger: logger,
            syncCoordinator: syncCoordinator,
            iCloudAccountAvailabilityService: iCloudAccountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: persistentStoreRemoteChangeSource,
            syncBackedStoreReference: syncBackedStoreReference,
            syncBootstrapPreferenceStore: syncBootstrapPreferenceStore,
            syncBootstrapContext: syncBootstrapContext,
            appSettingsService: appSettingsService
        )
    }
}
