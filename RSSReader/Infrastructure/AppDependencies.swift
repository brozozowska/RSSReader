import CloudKit
import Foundation
import SwiftUI
import SwiftData

// MARK: - AppDependencies protocol
public protocol AppDependenciesProtocol {
    var logger: Logging { get }
    var httpClient: any HTTPClient { get }
    var feedFetcher: any FeedFetching { get }
    var sourceIconCache: any SourceIconCaching { get }
    var modelContainer: ModelContainer? { get }
}

private final class AppDependencyTaskStore: @unchecked Sendable {
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
    public let sourceIconCache: any SourceIconCaching
    let feedRefreshService: FeedRefreshService?
    let feedRepository: (any FeedRepository)?
    let folderRepository: (any FolderRepository)?
    let sourceManagementService: (any SourceManagementService)?
    let articleRepository: (any ArticleRepository)?
    let articleStateService: ArticleStateService?
    let unreadAppIconBadgeService: (any UnreadAppIconBadgeServicing)?
    let articleRetentionCleanupService: (any ArticleRetentionCleanupServicing)?
    let persistenceBoundedGrowthCleanupService: (any PersistenceBoundedGrowthCleanupServicing)?
    let articleQueryService: (any ArticleQueryService)?
    let sourcesSidebarQueryService: (any SourcesSidebarQueryService)?
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
    private let syncRuntimeOrchestrator: AppSyncRuntimeOrchestrator
    private let feedSaveRefreshTaskStore: AppDependencyTaskStore?

    init(
        logger: Logging,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        feedFetcher: (any FeedFetching)? = nil,
        sourceIconCache: (any SourceIconCaching)? = nil,
        modelContainer: ModelContainer? = nil,
        modelContainerBootstrapFailureDescription: String? = nil,
        syncBackedStoreReference: SyncBackedStoreReference? = nil,
        syncBootstrapPreferenceStore: (any AppSyncBootstrapPreferenceStoring)? = nil,
        syncBootstrapContext: AppSyncBootstrapContext? = nil,
        backgroundRefreshService: (any BackgroundRefreshService)? = nil,
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
            guard let articleRepository, let articleStateRepository else {
                return nil
            }

            return ArticleRetentionCleanupService(
                logger: logger,
                articleRepository: articleRepository,
                articleStateRepository: articleStateRepository
            )
        }()
        let sourcesSidebarQueryService: (any SourcesSidebarQueryService)? = {
            guard let feedRepository,
                  let folderRepository,
                  let articleStateRepository,
                  let articleQueryService else {
                return nil
            }

            return DefaultSourcesSidebarQueryService(
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
        let sourceManagementService: (any SourceManagementService)? = {
            guard let feedRepository, let folderRepository, let articleRepository else {
                return nil
            }

            return DefaultSourceManagementService(
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
        let resolvedSourceIconCache = sourceIconCache ?? SourceIconCacheService(httpClient: httpClient)
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
        self.sourceIconCache = resolvedSourceIconCache
        self.modelContainer = modelContainer
        self.modelContainerBootstrapFailureDescription = modelContainerBootstrapFailureDescription
        self.syncBackedStoreReference = syncBackedStoreReference
        self.syncBootstrapPreferenceStore = syncBootstrapPreferenceStore
        self.syncBootstrapContext = syncBootstrapContext
        self.feedRefreshService = feedRefreshService
        self.feedRepository = feedRepository
        self.folderRepository = folderRepository
        self.sourceManagementService = sourceManagementService
        self.articleRepository = articleRepository
        self.articleStateService = articleStateService
        self.unreadAppIconBadgeService = resolvedUnreadAppIconBadgeService
        self.articleRetentionCleanupService = articleRetentionCleanupService
        self.persistenceBoundedGrowthCleanupService = persistenceBoundedGrowthCleanupService
        self.articleStateRepository = articleStateRepository
        self.articleQueryService = articleQueryService
        self.sourcesSidebarQueryService = sourcesSidebarQueryService
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

// MARK: - Factory
extension AppDependencies {
    static func makeDefaultLogger(category: String = "app") -> Logging {
#if DEBUG
        let baseLogger = OSLogger(category: category)
        return FilteredLogger(minLevel: .debug, base: baseLogger)
#else
        let baseLogger = OSLogger(category: category)
        return FilteredLogger(minLevel: .info, base: baseLogger)
#endif
    }

    static func makeDefault() -> AppDependencies {
        let logger = makeDefaultLogger()
        return AppDependencies(logger: logger)
    }

    @MainActor
    static func makeDefault(syncCoordinator: SyncCoordinator) -> AppDependencies {
        let logger = makeDefaultLogger()
        return AppDependencies(logger: logger, syncCoordinator: syncCoordinator)
    }

}

extension AppDependencies {
    static func makeSwiftDataConfigurationPlan(
        modelPartition: AppPersistenceModelPartition,
        isStoredInMemoryOnly: Bool,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy = CloudKitContainerConfiguration.syncBackedDatabasePolicy
    ) -> AppPersistenceConfigurationPlan {
        AppPersistenceConfigurationPlan.make(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
    }

    @MainActor
    static func makeWithSwiftData(
        modelPartition: AppPersistenceModelPartition,
        syncEnablementPolicy: AppSyncEnablementPolicy
    ) -> AppDependencies {
        let syncCoordinator = SyncCoordinator()
        return makeWithSwiftData(
            modelPartition: modelPartition,
            syncEnablementPolicy: syncEnablementPolicy,
            syncCoordinator: syncCoordinator
        )
    }

    @MainActor
    static func makeWithSwiftData(
        modelPartition: AppPersistenceModelPartition,
        syncEnablementPolicy: AppSyncEnablementPolicy,
        syncCoordinator: SyncCoordinator,
        syncBootstrapPreferenceStore: (any AppSyncBootstrapPreferenceStoring)? = nil,
        logger: Logging? = nil
    ) -> AppDependencies {
        let logger = logger ?? makeDefaultLogger()

        let resolvedSyncBootstrapPreferenceStore = syncBootstrapPreferenceStore
            ?? AppSyncBootstrapPreferenceStore(logger: logger)
        let bootstrapSettingsSnapshot = makeSyncEnablementBootstrapSettingsSnapshot(
            modelPartition: modelPartition,
            logger: logger
        )
        logger.info(
            "Resolved sync bootstrap settings snapshot: useiCloudSync=\(String(describing: bootstrapSettingsSnapshot?.useiCloudSync))"
        )
        let desiredBootPreference = syncEnablementPolicy.bootPreference(
            from: bootstrapSettingsSnapshot,
            localBootstrapPreference: resolvedSyncBootstrapPreferenceStore.currentBootPreference()
        )
        let desiredSyncBackedCloudKitPolicy = resolveSyncBackedCloudKitPolicy(
            syncEnablementPolicy: syncEnablementPolicy,
            bootstrapSettingsSnapshot: bootstrapSettingsSnapshot,
            localBootstrapPreference: desiredBootPreference
        )
        let syncBootstrapContext = resolveSyncBootstrapContext(
            desiredBootPreference: desiredBootPreference,
            desiredPolicy: desiredSyncBackedCloudKitPolicy,
            logger: logger
        )
        logger.info(
            "Resolved sync bootstrap policy selection: desiredBootPreference=\(desiredBootPreference.rawValue) desiredSyncBackedCloudKitPolicy=\(String(describing: desiredSyncBackedCloudKitPolicy)) effectiveModelContainerCloudKitPolicy=\(String(describing: syncBootstrapContext.modelContainerCloudKitPolicy)) accountAvailabilityAtBootstrap=\(String(describing: syncBootstrapContext.accountAvailabilityAtBootstrap)) localOnlyFallback=\(syncBootstrapContext.isRunningLocalOnlyFallbackForCurrentLaunch)"
        )
        let syncBackedCloudKitPolicy = syncBootstrapContext.modelContainerCloudKitPolicy
        let syncBackedStoreReference = makeSyncBackedStoreReference(
            modelPartition: modelPartition,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
        let modelContainer: ModelContainer?
        let modelContainerBootstrapFailureDescription: String?
        do {
            logger.info(
                "Starting model container setup: syncBackedPolicy=\(String(describing: syncBackedCloudKitPolicy)) syncBackedStoreIdentifier=\(syncBackedStoreReference.runtimeStoreIdentifier) syncBackedStoreURL=\(syncBackedStoreReference.persistentStoreURL.path)"
            )
            modelContainer = try makeModelContainer(
                modelPartition: modelPartition,
                isStoredInMemoryOnly: false,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
            )
            modelContainerBootstrapFailureDescription = nil
            logger.info(
                "Model container setup succeeded: syncBackedPolicy=\(String(describing: syncBackedCloudKitPolicy)) syncBackedStoreIdentifier=\(syncBackedStoreReference.runtimeStoreIdentifier)"
            )
        } catch {
            let persistentStoreProbeFailureDescription = makePersistentStoreProbeFailureDescription(
                modelPartition: modelPartition,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
            )
            logger.error(
                "Model container setup failed: syncBackedPolicy=\(String(describing: syncBackedCloudKitPolicy)) syncBackedStoreIdentifier=\(syncBackedStoreReference.runtimeStoreIdentifier) error=\(error)"
            )
            modelContainer = nil
            modelContainerBootstrapFailureDescription = makeModelContainerBootstrapFailureDescription(
                for: error,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy,
                persistentStoreProbeFailureDescription: persistentStoreProbeFailureDescription
            )
        }
        return AppDependencies(
            logger: logger,
            modelContainer: modelContainer,
            modelContainerBootstrapFailureDescription: modelContainerBootstrapFailureDescription,
            syncBackedStoreReference: syncBackedStoreReference,
            syncBootstrapPreferenceStore: resolvedSyncBootstrapPreferenceStore,
            syncBootstrapContext: syncBootstrapContext,
            syncCoordinator: syncCoordinator
        )
    }
}

extension AppDependencies {
    static func resolveSyncBackedCloudKitPolicy(
        syncEnablementPolicy: AppSyncEnablementPolicy,
        bootstrapSettingsSnapshot: AppSettingsSnapshot?,
        localBootstrapPreference: AppSyncBootPreference? = nil
    ) -> AppPersistenceCloudKitPolicy {
        syncEnablementPolicy.syncBackedCloudKitPolicy(
            for: bootstrapSettingsSnapshot,
            localBootstrapPreference: localBootstrapPreference
        )
    }

    static func resolveSyncBootstrapContext(
        desiredBootPreference: AppSyncBootPreference,
        desiredPolicy: AppPersistenceCloudKitPolicy,
        logger: Logging,
        resolvedAccountStatus: CKAccountStatus? = nil
    ) -> AppSyncBootstrapContext {
        guard case .privateContainer(let containerIdentifier) = desiredPolicy else {
            logger.info(
                "Using local-only sync bootstrap path because desired policy does not require CloudKit: desiredBootPreference=\(desiredBootPreference.rawValue) desiredPolicy=\(String(describing: desiredPolicy))"
            )
            return AppSyncBootstrapContext(
                desiredBootPreference: desiredBootPreference,
                desiredSyncBackedCloudKitPolicy: desiredPolicy,
                modelContainerCloudKitPolicy: desiredPolicy,
                accountAvailabilityAtBootstrap: nil
            )
        }

        let resolvedContainerIdentifier = containerIdentifier.isEmpty
            ? CloudKitContainerConfiguration.containerIdentifier
            : containerIdentifier
        let accountStatus = resolvedAccountStatus
            ?? CloudKitAccountStatusResolver.currentStatus(for: resolvedContainerIdentifier)
        let accountAvailability = DefaultICloudAccountAvailabilityService.mapAccountAvailability(
            from: accountStatus
        )
        logger.info(
            "Resolved sync bootstrap account status: containerIdentifier=\(resolvedContainerIdentifier) accountStatus=\(String(describing: accountStatus)) availability=\(accountAvailability.rawValue)"
        )

        guard accountStatus == .available else {
            logger.info(
                "Skipped CloudKit-backed model container bootstrap because account status is \(String(describing: accountStatus)); using local-only fallback for current launch"
            )
            return AppSyncBootstrapContext(
                desiredBootPreference: desiredBootPreference,
                desiredSyncBackedCloudKitPolicy: desiredPolicy,
                modelContainerCloudKitPolicy: .disabled,
                accountAvailabilityAtBootstrap: accountAvailability
            )
        }

        return AppSyncBootstrapContext(
            desiredBootPreference: desiredBootPreference,
            desiredSyncBackedCloudKitPolicy: desiredPolicy,
            modelContainerCloudKitPolicy: desiredPolicy,
            accountAvailabilityAtBootstrap: accountAvailability
        )
    }

    @MainActor
    static func fetchSyncEnablementBootstrapSettings(
        from modelContainer: ModelContainer
    ) throws -> AppSettingsSnapshot? {
        let repository = SwiftDataAppSettingsRepository(modelContext: modelContainer.mainContext)
        guard let settings = try repository.fetch() else {
            return nil
        }

        return AppSettingsSnapshot(settings: settings)
    }

    private static func makeModelContainer(
        modelPartition: AppPersistenceModelPartition,
        isStoredInMemoryOnly: Bool,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) throws -> ModelContainer {
        let schema = modelPartition.schema
        let configurationPlan = makeSwiftDataConfigurationPlan(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )

        return try ModelContainer(
            for: schema,
            configurations: configurationPlan.modelContainerConfigurations
        )
    }

    static func makeModelContainerBootstrapFailureDescription(
        for error: Error,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy,
        persistentStoreProbeFailureDescription: String? = nil
    ) -> String {
        let policyDescription = String(describing: syncBackedCloudKitPolicy)
        let errorDescription = CloudKitStoreBootstrapDiagnostics.describeErrorChain(error).joined(separator: "\n")
        let persistentStoreProbeSection: String
        if let persistentStoreProbeFailureDescription {
            persistentStoreProbeSection = "\nPersistent store probe:\n\(persistentStoreProbeFailureDescription)"
        } else {
            persistentStoreProbeSection = ""
        }
        return """
        The app could not initialize its data store for the current sync configuration (\(policyDescription)).
        \(errorDescription)
        \(persistentStoreProbeSection)
        """
    }

    private static func makePersistentStoreProbeFailureDescription(
        modelPartition: AppPersistenceModelPartition,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) -> String? {
        guard let request = makeSyncBackedStoreBootstrapRequest(
            modelPartition: modelPartition,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        ) else {
            return nil
        }

        return CloudKitStoreBootstrapDiagnostics.persistentStoreProbeFailureDescription(using: request)
    }

    @MainActor
    private static func makeSyncEnablementBootstrapSettingsSnapshot(
        modelPartition: AppPersistenceModelPartition,
        logger: Logging
    ) -> AppSettingsSnapshot? {
        do {
            let bootstrapContainer = try makeModelContainer(
                modelPartition: modelPartition,
                isStoredInMemoryOnly: false,
                syncBackedCloudKitPolicy: .disabled
            )
            return try fetchSyncEnablementBootstrapSettings(from: bootstrapContainer)
        } catch {
            logger.error("Failed to resolve sync enablement bootstrap settings: \(error)")
            return nil
        }
    }

    private static func makeSyncBackedStoreBootstrapRequest(
        modelPartition: AppPersistenceModelPartition,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) -> CloudKitStoreBootstrapRequest? {
        guard case .privateContainer(let containerIdentifier) = syncBackedCloudKitPolicy else {
            return nil
        }

        let resolvedContainerIdentifier = containerIdentifier.isEmpty
            ? CloudKitContainerConfiguration.containerIdentifier
            : containerIdentifier
        let configurationPlan = makeSwiftDataConfigurationPlan(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
        let syncBackedStore = configurationPlan.syncBackedStore

        return CloudKitStoreBootstrapRequest(
            containerIdentifier: resolvedContainerIdentifier,
            storeConfigurationName: syncBackedStore.name,
            storeURL: syncBackedStore.modelConfiguration.url,
            modelTypes: syncBackedStore.modelTypes
        )
    }

    private static func makeSyncBackedStoreReference(
        modelPartition: AppPersistenceModelPartition,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy
    ) -> SyncBackedStoreReference {
        let configurationPlan = makeSwiftDataConfigurationPlan(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
        )
        let syncBackedStore = configurationPlan.syncBackedStore

        return SyncBackedStoreReference(
            runtimeStoreIdentifier: syncBackedStore.name,
            persistentStoreURL: syncBackedStore.modelConfiguration.url
        )
    }
}

extension AppDependencies {
    @MainActor
    func reportBackgroundRefreshRegistrationConfigured(
        identifier: String = BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
        handlerDescription: String = "SwiftUI.backgroundTask(.appRefresh)"
    ) {
        backgroundRefreshValidationDiagnosticsReporter.reportRegistrationConfigured(
            identifier: identifier,
            handlerDescription: handlerDescription
        )
    }

    @MainActor
    func executeBackgroundAppRefresh() async -> BackgroundRefreshExecutionOutcome {
        let executionCoordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: self)
        return await executionCoordinator.executeAppRefresh()
    }

    @MainActor
    func startSyncCoordinatorAppLifetime() {
        syncRuntimeOrchestrator.startSyncCoordinatorAppLifetime()
    }

    @MainActor
    func startRemoteSyncReloadAppLifetime(using appState: AppState) {
        syncRuntimeOrchestrator.startRemoteSyncReloadAppLifetime(using: appState)
    }

    @MainActor
    func stopSyncRuntimeAppLifetime() {
        syncRuntimeOrchestrator.stopAppLifetime()
    }
}

extension AppDependencies {
    @MainActor
    func showInbox(using appState: AppState) {
        appState.selectReadingSource(.inbox)
    }

    @MainActor
    func showUnread(using appState: AppState) {
        appState.selectReadingSource(.unread)
    }

    @MainActor
    func showStarred(using appState: AppState) {
        appState.selectReadingSource(.starred)
    }

    @MainActor
    func showFeed(id feedID: UUID, using appState: AppState) {
        appState.selectReadingSource(.feed(feedID))
    }

    @MainActor
    func showFolder(named folderName: String, using appState: AppState) {
        appState.selectReadingSource(.folder(folderName))
    }

    @MainActor
    func selectArticle(id articleID: UUID?, using appState: AppState) {
        guard let articleID else {
            appState.selectedArticleID = nil
            return
        }

        guard shouldPresentSelectedArticleInSafariByDefault() else {
            appState.selectedArticleID = articleID
            return
        }

        guard let articleQueryService else {
            logger.error("Article query service is unavailable for default reader mode policy")
            appState.selectedArticleID = articleID
            return
        }

        do {
            guard let article = try articleQueryService.fetchReaderArticle(id: articleID) else {
                logger.error("Skipped default Safari presentation because article \(articleID) was not found")
                appState.selectedArticleID = articleID
                return
            }

            guard openArticleInSafari(article, using: appState) else {
                appState.selectedArticleID = articleID
                return
            }
        } catch {
            logger.error("Failed to apply default reader mode policy for article \(articleID): \(error)")
            appState.selectedArticleID = articleID
        }
    }

    @MainActor
    func applySourcesFilter(_ filter: SourcesFilter, using appState: AppState) {
        appState.selectSourcesFilter(filter)
    }

    @MainActor
    @discardableResult
    func openArticleInSafari(_ article: ReaderArticleDTO, using appState: AppState) -> Bool {
        guard let url = URL(string: article.canonicalURL ?? article.articleURL) else {
            logger.error("Skipped opening article in Safari because URL is invalid for article \(article.id)")
            return false
        }

        guard appState.presentSafari(articleID: article.id, url: url) else {
            logger.error("Skipped opening article in Safari because URL is unsupported for article \(article.id)")
            return false
        }

        return true
    }

    @MainActor
    func openArticleBodyLink(_ url: URL, articleID: UUID, using appState: AppState) {
        guard appState.presentSafari(articleID: articleID, url: url) else {
            logger.error("Skipped opening article body link in Safari because URL is unsupported for article \(articleID)")
            return
        }
    }

    @MainActor
    func closePresentedArticleSafari(using appState: AppState) {
        appState.dismissPresentedSafari()
    }

    @MainActor
    func showSettings(using appState: AppState) {
        appState.presentSettingsScreen()
    }

    @MainActor
    func dismissSettings(using appState: AppState) {
        appState.dismissSettingsScreen()
    }

    @MainActor
    func showSourceManagement(using appState: AppState) {
        appState.presentSourceManagementScreen()
    }

    @MainActor
    func showFeedEditor(id feedID: UUID, using appState: AppState) {
        appState.presentSourceManagementScreen(launchContext: .editFeed(feedID))
    }

    @MainActor
    func showFeedOrganizer(id feedID: UUID, using appState: AppState) {
        appState.presentSourceManagementScreen(launchContext: .organizeFeed(feedID))
    }

    @MainActor
    func showFolderEditor(named folderName: String, using appState: AppState) {
        guard let folderRepository else {
            logger.error("Folder repository is unavailable for folder editing")
            return
        }

        do {
            guard let folder = try folderRepository.fetchFolder(name: folderName) else {
                logger.error("Skipped folder editor presentation because folder \(folderName) was not found")
                return
            }
            appState.presentSourceManagementScreen(launchContext: .editFolder(folder.id))
        } catch {
            logger.error("Failed to resolve folder editor presentation for \(folderName): \(error)")
        }
    }

    @MainActor
    func loadSourceManagementAddFeedContext(
        into screenState: inout SourceManagementScreenState
    ) {
        guard let sourceManagementService else {
            logger.error("Skipped add-feed folder context loading because source management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyAddFeedFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for add-feed flow: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    @MainActor
    func loadSourceManagementAddFeedEditContext(
        feedID: UUID,
        into screenState: inout SourceManagementScreenState
    ) {
        screenState.resetAddFeedForEntry()

        guard let sourceManagementService else {
            logger.error("Skipped feed editor context loading because source management service is unavailable")
            screenState.applyAddFeedFolderContext(folders: [])
            return
        }

        do {
            guard let feed = try sourceManagementService.fetchFeed(id: feedID) else {
                logger.error("Skipped feed editor context loading because feed \(feedID) was not found")
                screenState.applyAddFeedFolderContext(folders: [])
                return
            }

            let folders = try sourceManagementService.fetchFolders()
            screenState.applyAddFeedEditContext(feed: feed, folders: folders)
        } catch {
            logger.error("Failed to load feed editor context for source management screen: \(error)")
            screenState.applyAddFeedFolderContext(folders: [])
        }
    }

    @MainActor
    func loadSourceManagementCreateFolderContext(
        into screenState: inout SourceManagementScreenState
    ) {
        guard let sourceManagementService else {
            let unavailableMessage = "Folder creation is unavailable in the current app environment."
            logger.error("Skipped create-folder context loading because source management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: "Folder creation is unavailable",
                message: unavailableMessage
            )
            return
        }

        do {
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyCreateFolderContext(folders: folders)
        } catch {
            logger.error("Failed to load folder context for source management screen: \(error)")
            screenState.applyCreateFolderFailure(
                "Unable to load existing folders right now. Try again."
            )
        }
    }

    @MainActor
    func loadSourceManagementCreateFolderEditContext(
        folderID: UUID,
        into screenState: inout SourceManagementScreenState
    ) {
        screenState.resetCreateFolderForEntry()

        guard let sourceManagementService else {
            let unavailableMessage = "Folder editing is unavailable in the current app environment."
            logger.error("Skipped folder editor context loading because source management service is unavailable")
            screenState.applyCreateFolderServiceUnavailable(
                title: "Folder editing is unavailable",
                message: unavailableMessage
            )
            return
        }

        do {
            guard let folder = try sourceManagementService.fetchFolder(id: folderID) else {
                logger.error("Skipped folder editor context loading because folder \(folderID) was not found")
                return
            }

            let folders = try sourceManagementService.fetchFolders()
            screenState.applyCreateFolderEditContext(folder: folder, folders: folders)
        } catch {
            logger.error("Failed to load folder editor context for source management screen: \(error)")
            screenState.applyCreateFolderFailure(
                "Unable to load the folder details right now. Try again."
            )
        }
    }

    @MainActor
    func loadSourceManagementMoveSourceContext(
        selectedFeedID: UUID? = nil,
        into screenState: inout SourceManagementScreenState
    ) {
        guard let sourceManagementService else {
            logger.error("Skipped move-source context loading because source management service is unavailable")
            screenState.applyMoveSourceContext(feeds: [], folders: [])
            screenState.applyMoveSourceFailure(
                "Source moves are unavailable in the current app environment."
            )
            return
        }

        do {
            let feeds = try sourceManagementService.fetchFeeds()
            let folders = try sourceManagementService.fetchFolders()
            screenState.applyMoveSourceContext(
                feeds: feeds,
                folders: folders,
                selectedFeedID: selectedFeedID
            )
        } catch {
            logger.error("Failed to load move-source context for source management screen: \(error)")
            screenState.applyMoveSourceContext(feeds: [], folders: [])
            screenState.applyMoveSourceFailure(
                "Unable to load existing sources right now. Try again."
            )
        }
    }

    @MainActor
    func restoreAddFeedAfterCreatingFolder(
        _ folder: SourceManagementFolderSummary,
        into screenState: inout SourceManagementScreenState
    ) {
        loadSourceManagementAddFeedContext(into: &screenState)
        screenState.selectAddFeedFolderPlacement(.folder(folder.id))
        screenState.presentScenario(.addFeed)
    }

    @MainActor
    func finishFolderEditing(
        previousName: String,
        updatedFolderName: String,
        using appState: AppState
    ) {
        appState.requestSourcesSidebarReload()
        if appState.selectedSidebarSelection == .folder(previousName) {
            showFolder(named: updatedFolderName, using: appState)
        }
        dismissSourceManagement(using: appState)
    }

    @MainActor
    func finishCreatingFolder(named folderName: String, using appState: AppState) {
        logger.info("Finished source management folder creation for \(folderName)")
        appState.requestSourcesSidebarReload()
    }

    @MainActor
    func finishMovingSource(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState
    ) {
        appState.requestSourcesSidebarReload()

        switch appState.selectedSidebarSelection {
        case .feed(let selectedFeedID):
            if selectedFeedID == feedID {
                appState.requestArticleListReload()
            }
        case .folder(let folderName):
            if folderName == previousFolderName || folderName == updatedFolderName {
                appState.requestArticleListReload()
            }
        case .inbox, .unread, .starred, .none:
            break
        }

        dismissSourceManagement(using: appState)
    }

    @MainActor
    func finishSavingFeed(
        id feedID: UUID,
        using appState: AppState,
        selectsSavedFeed: Bool = true
    ) async -> FeedRefreshResult? {
        appState.requestSourcesSidebarReload()
        if selectsSavedFeed {
            showFeed(id: feedID, using: appState)
        } else {
            appState.selectReadingSource(nil)
        }
        dismissSourceManagement(using: appState)
        scheduleInitialRefreshAfterSavingFeed(id: feedID, using: appState)
        return nil
    }

    @MainActor
    private func scheduleInitialRefreshAfterSavingFeed(
        id feedID: UUID,
        using appState: AppState
    ) {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable for source save completion")
            return
        }

        let task = Task { @MainActor in
            _ = await feedRefreshService.refreshAfterAddingFeed(feedID: feedID)
            await refreshUnreadAppIconBadgeCount()
            appState.requestSourcesSidebarReload()
            appState.requestArticleListReload()
        }
        feedSaveRefreshTaskStore?.append(task)
    }

    func waitForScheduledFeedSaveRefreshes() async {
        await feedSaveRefreshTaskStore?.waitForAll()
    }

    @MainActor
    func completeSourceManagementFolderEditing(
        previousName: String?,
        updatedFolderName: String,
        using appState: AppState?
    ) {
        guard let appState, let previousName else { return }
        finishFolderEditing(
            previousName: previousName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func completeSourceManagementFolderCreation(
        named folderName: String,
        using appState: AppState?
    ) {
        guard let appState else { return }
        finishCreatingFolder(named: folderName, using: appState)
    }

    @MainActor
    func completeSourceManagementMove(
        feedID: UUID,
        previousFolderName: String?,
        updatedFolderName: String?,
        using appState: AppState?
    ) {
        guard let appState else { return }
        finishMovingSource(
            feedID: feedID,
            previousFolderName: previousFolderName,
            updatedFolderName: updatedFolderName,
            using: appState
        )
    }

    @MainActor
    func completeSourceManagementFeedSave(
        id feedID: UUID,
        using appState: AppState?,
        selectsSavedFeed: Bool
    ) async -> FeedRefreshResult? {
        guard let appState else { return nil }
        return await finishSavingFeed(
            id: feedID,
            using: appState,
            selectsSavedFeed: selectsSavedFeed
        )
    }

    @MainActor
    func finishUnsubscribingFeed(id feedID: UUID, using appState: AppState) {
        appState.requestSourcesSidebarReload()
        if appState.selectedSidebarSelection == .feed(feedID) {
            showInbox(using: appState)
        } else {
            appState.requestArticleListReload()
        }
    }

    @MainActor
    func finishDeletingFolder(named folderName: String, using appState: AppState) {
        appState.requestSourcesSidebarReload()
        if appState.selectedSidebarSelection == .folder(folderName) {
            showInbox(using: appState)
        } else {
            appState.requestArticleListReload()
        }
    }

    @MainActor
    func unsubscribeFeed(id feedID: UUID, using appState: AppState) {
        guard let sourceManagementService else {
            logger.error("Source management service is unavailable for feed deletion")
            return
        }

        do {
            try sourceManagementService.deleteFeed(id: feedID)
            finishUnsubscribingFeed(id: feedID, using: appState)
            scheduleUnreadAppIconBadgeRefresh()
        } catch {
            logger.error("Failed to unsubscribe feed \(feedID): \(error)")
        }
    }

    @MainActor
    func deleteFolder(named folderName: String, using appState: AppState) {
        guard let folderRepository else {
            logger.error("Folder repository is unavailable for folder deletion")
            return
        }
        guard let sourceManagementService else {
            logger.error("Source management service is unavailable for folder deletion")
            return
        }

        do {
            guard let folder = try folderRepository.fetchFolder(name: folderName) else {
                logger.error("Skipped folder deletion because folder \(folderName) was not found")
                return
            }
            try sourceManagementService.deleteFolder(id: folder.id)
            finishDeletingFolder(named: folderName, using: appState)
        } catch {
            logger.error("Failed to delete folder \(folderName): \(error)")
        }
    }

    @MainActor
    func dismissSourceManagement(using appState: AppState) {
        appState.dismissSourceManagementScreen()
    }

    @MainActor
    func refreshFeed(id feedID: UUID) async -> FeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }

        let result = await feedRefreshService.refresh(feedID: feedID)
        cleanupArchivedArticlesUsingCurrentSettings()
        await refreshUnreadAppIconBadgeCount()
        return result
    }

    @MainActor
    func refreshAfterAddingFeed(id feedID: UUID, using appState: AppState) async -> FeedRefreshResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable for source save completion")
            return nil
        }

        let result = await feedRefreshService.refreshAfterAddingFeed(feedID: feedID)
        cleanupArchivedArticlesUsingCurrentSettings()
        await refreshUnreadAppIconBadgeCount()
        appState.requestSourcesSidebarReload()
        showFeed(id: feedID, using: appState)
        dismissSourceManagement(using: appState)
        return result
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

        let result = await feedRefreshService.refreshAllActiveFeeds()
        recordSourcesRefreshIfNeeded(from: result)
        cleanupArchivedArticlesUsingCurrentSettings()
        await refreshUnreadAppIconBadgeCount()
        return result
    }

    @MainActor
    func refreshCurrentSource(using appState: AppState) async -> FeedRefreshResult? {
        switch appState.selectedSidebarSelection {
        case .feed(let feedID):
            let result = await refreshFeed(id: feedID)
            if result != nil {
                appState.requestArticleListReload()
            }
            return result
        case .inbox, .unread, .starred, .folder, .none:
            logger.info("Skipped source refresh because the current source is not a single feed")
            return nil
        }
    }

    @MainActor
    func refreshCurrentSelection(
        using appState: AppState,
        requestsArticleListReload: Bool = true
    ) async -> FeedRefreshBatchResult? {
        guard let selection = appState.selectedSidebarSelection else {
            logger.info("Skipped selection refresh because no source is selected")
            return nil
        }

        let result: FeedRefreshBatchResult?
        switch selection {
        case .feed(let feedID):
            if let refreshResult = await refreshFeed(id: feedID) {
                result = FeedRefreshBatchResult(
                    startedAt: refreshResult.startedAt,
                    finishedAt: refreshResult.finishedAt,
                    results: [refreshResult]
                )
            } else {
                result = nil
            }
        case .folder(let folderName):
            result = await refreshFeeds(in: folderName)
        case .inbox, .unread, .starred:
            result = await refreshAllFeeds()
        }

        if result != nil {
            appState.requestSourcesSidebarReload()
            if requestsArticleListReload {
                appState.requestArticleListReload()
            }
        }

        return result
    }

    @MainActor
    func refreshVisibleSources(using appState: AppState) async -> FeedRefreshBatchResult? {
        let result = await refreshAllFeeds()
        if result != nil {
            appState.requestSourceIconReload()
            appState.requestArticleListReload()
        }
        return result
    }

    @MainActor
    func refreshFeedsForBackground() async -> BackgroundRefreshServiceExecutionResult {
        guard let backgroundRefreshService else {
            logger.debug(
                "Background refresh dependencies trace outcome=serviceUnavailable operation=executeBackgroundAppRefresh"
            )
            return .failedToStart(.feedRefreshServiceUnavailable)
        }

        let result = await backgroundRefreshService.performScheduledRefresh()
        if case .executed(let refreshResult) = result {
            recordSourcesRefreshIfNeeded(from: refreshResult.batchResult)
            cleanupPersistenceBoundedGrowth()
            await refreshUnreadAppIconBadgeCount()
        }
        return result
    }

    @MainActor
    private func recordSourcesRefreshIfNeeded(from result: FeedRefreshBatchResult) {
        guard result.summary.fetchedCount + result.summary.notModifiedCount > 0 else {
            return
        }

        do {
            _ = try appSettingsService?.updateSettings(
                AppSettingsPatch(
                    lastSourcesRefreshAt: result.finishedAt,
                    updatedAt: result.finishedAt
                )
            )
        } catch {
            logger.error("Failed to persist sources refresh timestamp: \(error)")
        }
    }

    @MainActor
    @discardableResult
    func cleanupArchivedArticles(
        policy: ArticleRetentionPolicy,
        now: Date = .now
    ) -> ArticleRetentionCleanupResult? {
        guard let articleRetentionCleanupService else {
            logger.debug("Article retention cleanup service is unavailable")
            return nil
        }

        do {
            let result = try articleRetentionCleanupService.cleanupArchivedArticles(policy: policy, now: now)
            cleanupPersistenceBoundedGrowth(now: now)
            return result
        } catch {
            logger.error("Failed to clean up archived articles: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func cleanupArchivedArticlesUsingCurrentSettings(now: Date = .now) -> ArticleRetentionCleanupResult? {
        guard let appSettingsService else {
            logger.debug("App settings service is unavailable for article retention cleanup")
            return nil
        }

        do {
            let settings = try appSettingsService.fetchSettings()
            return cleanupArchivedArticles(policy: settings.articleRetentionPolicy, now: now)
        } catch {
            logger.error("Failed to load article retention settings for cleanup: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func purgeArchivedArticles() -> ArticleArchivePurgeResult? {
        guard let articleRetentionCleanupService else {
            logger.debug("Article retention cleanup service is unavailable for article archive purge")
            return nil
        }

        do {
            let result = try articleRetentionCleanupService.purgeArchivedArticles()
            cleanupPersistenceBoundedGrowth()
            return result
        } catch {
            logger.error("Failed to purge archived articles: \(error)")
            return nil
        }
    }

    @MainActor
    @discardableResult
    func cleanupPersistenceBoundedGrowth(now: Date = .now) -> PersistenceBoundedGrowthCleanupResult? {
        guard let persistenceBoundedGrowthCleanupService else {
            logger.debug("Persistence bounded growth cleanup service is unavailable")
            return nil
        }

        do {
            return try persistenceBoundedGrowthCleanupService.cleanupBoundedGrowth(now: now)
        } catch {
            logger.error("Failed to clean up bounded persistence growth: \(error)")
            return nil
        }
    }

    @MainActor
    func refreshUnreadAppIconBadgeCount() async {
        guard let unreadAppIconBadgeService else {
            logger.debug("Unread app icon badge service is unavailable")
            return
        }

        await unreadAppIconBadgeService.refreshBadgeCount()
    }

    @MainActor
    func applyUnreadAppIconBadgePreference(isEnabled: Bool) {
        guard let unreadAppIconBadgeService else {
            logger.debug("Unread app icon badge service is unavailable")
            return
        }

        Task { @MainActor in
            await unreadAppIconBadgeService.applyBadgePreference(isEnabled: isEnabled)
        }
    }

    @MainActor
    func currentBackgroundRefreshRuntimePrerequisites() -> BackgroundRefreshRuntimePrerequisitesSnapshot {
        backgroundRefreshRuntimePrerequisitesSource.currentSnapshot()
    }

    @MainActor
    func currentBackgroundRefreshValidationDiagnostics() -> BackgroundRefreshValidationDiagnosticsSnapshot {
        backgroundRefreshValidationDiagnosticsReporter.currentSnapshot()
    }

    @MainActor
    func configureBackgroundRefreshLaunchScheduling(now: Date = .now) {
        do {
            reportBackgroundRefreshLaunchScheduling(
                try replaceBackgroundRefreshSchedule(now: now)
            )
        } catch {
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .failed,
                identifier: nil,
                earliestBeginDate: nil,
                failureReason: BackgroundRefreshScheduleFailureReason.classify(error)
            )
        }
    }

    @MainActor
    func reportSkippedDuplicateBackgroundRefreshLaunchSchedulingAttempt() {
        backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
            outcome: .skippedDuplicateLaunchAttempt,
            identifier: nil,
            earliestBeginDate: nil,
            failureReason: nil
        )
    }

    @MainActor
    @discardableResult
    func replaceBackgroundRefreshSchedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date = .now
    ) throws -> BackgroundRefreshScheduleResult {
        try backgroundRefreshScheduler.replace(using: configuration, now: now)
    }

    @MainActor
    @discardableResult
    func replaceBackgroundRefreshSchedule(
        now: Date = .now
    ) throws -> BackgroundRefreshScheduleResult? {
        guard let backgroundRefreshService else {
            logger.debug(
                "Background refresh dependencies trace outcome=serviceUnavailable operation=replaceSchedule"
            )
            return nil
        }

        let configuration = try backgroundRefreshService.loadConfiguration()
        return try replaceBackgroundRefreshSchedule(using: configuration, now: now)
    }
}

private extension AppDependencies {
    @MainActor
    func reportBackgroundRefreshLaunchScheduling(_ result: BackgroundRefreshScheduleResult?) {
        switch result {
        case .scheduled(let plan):
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .scheduled,
                identifier: plan.identifier,
                earliestBeginDate: plan.earliestBeginDate,
                failureReason: nil
            )
        case .cancelled:
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .cancelled,
                identifier: nil,
                earliestBeginDate: nil,
                failureReason: nil
            )
        case nil:
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .unavailable,
                identifier: nil,
                earliestBeginDate: nil,
                failureReason: nil
            )
        }
    }

    @MainActor
    func shouldPresentSelectedArticleInSafariByDefault() -> Bool {
        guard let appSettingsService else {
            return false
        }

        do {
            return try appSettingsService.fetchSettings().defaultReaderMode == .browser
        } catch {
            logger.error("Failed to load app settings for default reader mode policy: \(error)")
            return false
        }
    }

    static func makeFeedFetcher(
        httpClient: any HTTPClient
    ) -> any FeedFetching {
        FeedFetcher(httpClient: httpClient)
    }

    @MainActor
    func refreshFeeds(in folderName: String) async -> FeedRefreshBatchResult? {
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            return nil
        }
        guard let feedRepository else {
            logger.error("Feed repository is unavailable")
            return nil
        }

        do {
            let folderFeedIDs = try feedRepository.fetchActiveFeeds()
                .filter { $0.folder?.name == folderName }
                .map(\.id)
            let result = await feedRefreshService.refreshFeeds(folderFeedIDs)
            cleanupArchivedArticlesUsingCurrentSettings()
            await refreshUnreadAppIconBadgeCount()
            return result
        } catch {
            logger.error("Failed to load folder feeds for refresh: \(error)")
            return nil
        }
    }

    @MainActor
    func scheduleUnreadAppIconBadgeRefresh() {
        Task { @MainActor in
            await refreshUnreadAppIconBadgeCount()
        }
    }
}
