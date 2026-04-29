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
    let articleQueryService: (any ArticleQueryService)?
    let sourcesSidebarQueryService: (any SourcesSidebarQueryService)?
    let articleStateRepository: (any ArticleStateRepository)?
    let appSettingsRepository: (any AppSettingsRepository)?
    let appSettingsService: (any AppSettingsService)?
    let backgroundRefreshService: (any BackgroundRefreshService)?
    let iCloudAccountAvailabilityService: any ICloudAccountAvailabilityService
    let cloudKitRuntimeEventSource: any CloudKitRuntimeEventSource
    let persistentStoreRemoteChangeSource: any PersistentStoreRemoteChangeSource
    let syncCoordinator: SyncCoordinator?
    let iCloudSyncStatusService: (any ICloudSyncStatusService)?
    let feedFetchLogRepository: (any FeedFetchLogRepository)?
    public let modelContainer: ModelContainer?
    let modelContainerBootstrapFailureDescription: String?
    let syncBootstrapPreferenceStore: any AppSyncBootstrapPreferenceStoring
    let syncBootstrapContext: AppSyncBootstrapContext?
    private var hasStartedSyncCoordinatorAppLifetime = false
    private var hasStartedRemoteSyncReloadAppLifetime = false
    private var remoteSyncReloadObservationTask: Task<Void, Never>?
    private var remoteSyncReloadPendingImportCompletion = false
    private var remoteSyncReloadPendingStoreChange = false

    init(
        logger: Logging,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        feedFetcher: (any FeedFetching)? = nil,
        sourceIconCache: (any SourceIconCaching)? = nil,
        modelContainer: ModelContainer? = nil,
        modelContainerBootstrapFailureDescription: String? = nil,
        syncBootstrapPreferenceStore: (any AppSyncBootstrapPreferenceStoring)? = nil,
        syncBootstrapContext: AppSyncBootstrapContext? = nil,
        iCloudAccountAvailabilityService: (any ICloudAccountAvailabilityService)? = nil,
        cloudKitRuntimeEventSource: (any CloudKitRuntimeEventSource)? = nil,
        persistentStoreRemoteChangeSource: (any PersistentStoreRemoteChangeSource)? = nil,
        syncCoordinator: SyncCoordinator? = nil
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
        let sourcesSidebarQueryService: (any SourcesSidebarQueryService)? = {
            guard let feedRepository,
                  let articleStateRepository,
                  let articleQueryService else {
                return nil
            }

            return DefaultSourcesSidebarQueryService(
                feedRepository: feedRepository,
                articleStateRepository: articleStateRepository,
                articleQueryService: articleQueryService
            )
        }()
        let appSettingsRepository = modelContainer.map { container in
            SwiftDataAppSettingsRepository(modelContext: container.mainContext)
        }
        let appSettingsService = appSettingsRepository.map { repository in
            DefaultAppSettingsService(repository: repository)
        }
        let feedFetchLogRepository = modelContainer.map { container in
            SwiftDataFeedFetchLogRepository(modelContext: container.mainContext)
        }
        let resolvedFeedFetcher = feedFetcher ?? Self.makeFeedFetcher(
            httpClient: httpClient
        )
        let sourceManagementService: (any SourceManagementService)? = {
            guard let feedRepository, let folderRepository, let articleRepository else {
                return nil
            }

            return DefaultSourceManagementService(
                logger: logger,
                feedFetcher: resolvedFeedFetcher,
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
        let backgroundRefreshService = appSettingsService.map { service in
            DefaultBackgroundRefreshService(
                logger: logger,
                appSettingsService: service,
                feedRefreshService: feedRefreshService
            )
        }
        let iCloudAccountAvailabilityService = iCloudAccountAvailabilityService
            ?? DefaultICloudAccountAvailabilityService(logger: logger)
        let cloudKitRuntimeEventSource = cloudKitRuntimeEventSource ?? DefaultCloudKitRuntimeEventSource()
        let persistentStoreRemoteChangeSource = persistentStoreRemoteChangeSource ?? DefaultPersistentStoreRemoteChangeSource()
        let syncBootstrapPreferenceStore = syncBootstrapPreferenceStore
            ?? AppSyncBootstrapPreferenceStore(logger: logger)
        let iCloudSyncStatusService = syncCoordinator.map { syncCoordinator in
            DefaultICloudSyncStatusService(syncCoordinator: syncCoordinator)
        }

        self.logger = logger
        self.httpClient = httpClient
        self.sourceIconCache = resolvedSourceIconCache
        self.modelContainer = modelContainer
        self.modelContainerBootstrapFailureDescription = modelContainerBootstrapFailureDescription
        self.syncBootstrapPreferenceStore = syncBootstrapPreferenceStore
        self.syncBootstrapContext = syncBootstrapContext
        self.feedRefreshService = feedRefreshService
        self.feedRepository = feedRepository
        self.folderRepository = folderRepository
        self.sourceManagementService = sourceManagementService
        self.articleRepository = articleRepository
        self.articleStateService = articleStateService
        self.articleStateRepository = articleStateRepository
        self.articleQueryService = articleQueryService
        self.sourcesSidebarQueryService = sourcesSidebarQueryService
        self.appSettingsRepository = appSettingsRepository
        self.appSettingsService = appSettingsService
        self.backgroundRefreshService = backgroundRefreshService
        self.iCloudAccountAvailabilityService = iCloudAccountAvailabilityService
        self.cloudKitRuntimeEventSource = cloudKitRuntimeEventSource
        self.persistentStoreRemoteChangeSource = persistentStoreRemoteChangeSource
        self.syncCoordinator = syncCoordinator
        self.iCloudSyncStatusService = iCloudSyncStatusService
        self.feedFetchLogRepository = feedFetchLogRepository
        self.feedFetcher = resolvedFeedFetcher
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
        let modelContainer: ModelContainer?
        let modelContainerBootstrapFailureDescription: String?
        do {
            modelContainer = try makeModelContainer(
                modelPartition: modelPartition,
                isStoredInMemoryOnly: false,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
            )
            modelContainerBootstrapFailureDescription = nil
            logger.info(
                "Created model container for sync policy \(String(describing: syncBackedCloudKitPolicy))"
            )
        } catch {
            let persistentStoreProbeFailureDescription = makePersistentStoreProbeFailureDescription(
                modelPartition: modelPartition,
                syncBackedCloudKitPolicy: syncBackedCloudKitPolicy
            )
            logger.error(
                "Failed to create model container for sync policy \(String(describing: syncBackedCloudKitPolicy)): \(error)"
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
                "Skipped CloudKit-backed model container bootstrap because account status is \(String(describing: accountStatus))"
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
}

extension AppDependencies {
    @MainActor
    func startSyncCoordinatorAppLifetime() {
        guard hasStartedSyncCoordinatorAppLifetime == false else { return }
        hasStartedSyncCoordinatorAppLifetime = true

        guard let syncCoordinator else { return }

        let isSyncEnabled = resolveInitialSyncEnablementForCoordinator()
        logger.info("Starting SyncCoordinator app lifetime: isSyncEnabled=\(isSyncEnabled)")
        syncCoordinator.applySyncEnablement(isEnabled: isSyncEnabled)
        syncCoordinator.connectRuntimeSources(
            accountAvailabilityService: iCloudAccountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource
        )
    }

    @MainActor
    func startRemoteSyncReloadAppLifetime(using appState: AppState) {
        guard hasStartedRemoteSyncReloadAppLifetime == false else { return }
        hasStartedRemoteSyncReloadAppLifetime = true
        logger.info("Starting remote sync reload app lifetime observation")
        let runtimeEvents = cloudKitRuntimeEventSource.events()
        let remoteChangeEvents = persistentStoreRemoteChangeSource.events()

        remoteSyncReloadObservationTask = Task { [weak self] in
            guard let self else { return }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    guard let self else { return }

                    for await runtimeEvent in runtimeEvents {
                        guard Task.isCancelled == false else { return }
                        await MainActor.run {
                            self.handleRemoteSyncReload(runtimeEvent: runtimeEvent, using: appState)
                        }
                    }
                }

                group.addTask { [weak self] in
                    guard let self else { return }

                    for await remoteChangeEvent in remoteChangeEvents {
                        guard Task.isCancelled == false else { return }
                        await MainActor.run {
                            self.handleRemoteSyncReload(remoteChangeEvent: remoteChangeEvent, using: appState)
                        }
                    }
                }

                await group.waitForAll()
            }
        }
    }

    @MainActor
    private func resolveInitialSyncEnablementForCoordinator() -> Bool {
        if let syncBootstrapContext {
            logger.info(
                "Resolved initial sync enablement from bootstrap context: isUsingCloudKitForCurrentLaunch=\(syncBootstrapContext.isUsingCloudKitForCurrentLaunch) desiredBootPreference=\(syncBootstrapContext.desiredBootPreference.rawValue)"
            )
            return syncBootstrapContext.isUsingCloudKitForCurrentLaunch
        }

        if let localBootstrapPreference = syncBootstrapPreferenceStore.currentBootPreference() {
            logger.info(
                "Resolved initial sync enablement from local bootstrap preference: \(localBootstrapPreference.rawValue)"
            )
            return localBootstrapPreference.usesCloudKit
        }

        guard let appSettingsService else {
            logger.info("Resolved initial sync enablement with default disabled value because app settings service is unavailable")
            return false
        }

        do {
            let isEnabled = try appSettingsService.fetchSettings().useiCloudSync
            logger.info("Resolved initial sync enablement from persisted app settings: \(isEnabled)")
            return isEnabled
        } catch {
            logger.error("Failed to resolve initial sync enablement for SyncCoordinator: \(error)")
            return false
        }
    }

    @MainActor
    private func handleRemoteSyncReload(
        runtimeEvent: CloudKitRuntimeEvent,
        using appState: AppState
    ) {
        guard syncCoordinator?.runtimeState.isSyncEnabled == true else {
            logger.debug("Ignored CloudKit runtime event for remote reload correlation because sync is disabled")
            return
        }

        switch runtimeEvent {
        case .started(.import, _):
            remoteSyncReloadPendingImportCompletion = false
            logger.info("Observed CloudKit import start; cleared pending remote reload import completion")
        case .finished(.import, _):
            remoteSyncReloadPendingImportCompletion = true
            logger.info("Observed CloudKit import completion; marked import completion pending for remote reload correlation")
            flushPendingRemoteSyncReloadIfNeeded(using: appState)
        case .failed(.import, let context, let message):
            remoteSyncReloadPendingImportCompletion = false
            remoteSyncReloadPendingStoreChange = false
            logger.error(
                "Observed CloudKit import failure; cleared pending remote reload correlation storeIdentifier=\(context.storeIdentifier) message=\(message ?? "nil")"
            )
        case .started, .finished, .failed:
            return
        }
    }

    @MainActor
    private func handleRemoteSyncReload(
        remoteChangeEvent: PersistentStoreRemoteChangeEvent,
        using appState: AppState
    ) {
        guard syncCoordinator?.runtimeState.isSyncEnabled == true else {
            logger.debug("Ignored persistent store remote change because sync is disabled")
            return
        }

        remoteSyncReloadPendingStoreChange = true
        logger.info(
            "Observed persistent store remote change; marked store change pending for remote reload correlation storeUUID=\(remoteChangeEvent.storeUUID ?? "nil") storeURL=\(remoteChangeEvent.storeURL?.absoluteString ?? "nil")"
        )
        flushPendingRemoteSyncReloadIfNeeded(using: appState)
    }

    @MainActor
    private func flushPendingRemoteSyncReloadIfNeeded(using appState: AppState) {
        guard remoteSyncReloadPendingImportCompletion, remoteSyncReloadPendingStoreChange else {
            logger.debug(
                "Remote sync reload correlation is waiting for pair completion: pendingImportCompletion=\(remoteSyncReloadPendingImportCompletion) pendingStoreChange=\(remoteSyncReloadPendingStoreChange)"
            )
            return
        }

        remoteSyncReloadPendingImportCompletion = false
        remoteSyncReloadPendingStoreChange = false
        logger.info("Requesting app-level remote sync reload after matching import completion and persistent store remote change")
        appState.requestRemoteSyncReload()
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

        guard shouldPresentSelectedArticleInWebViewByDefault() else {
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
                logger.error("Skipped default web view presentation because article \(articleID) was not found")
                appState.selectedArticleID = articleID
                return
            }

            openArticleInWebView(article, using: appState)
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
    func openArticleInWebView(_ article: ReaderArticleDTO, using appState: AppState) {
        guard let url = URL(string: article.canonicalURL ?? article.articleURL) else {
            logger.error("Skipped opening article in web view because URL is invalid for article \(article.id)")
            return
        }

        appState.presentWebView(articleID: article.id, url: url)
    }

    @MainActor
    func openArticleBodyLink(_ url: URL, articleID: UUID, using appState: AppState) {
        appState.presentWebView(articleID: articleID, url: url)
    }

    @MainActor
    func closePresentedArticleWebView(using appState: AppState) {
        appState.dismissPresentedWebView()
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
            screenState.applyMoveSourceContext(feeds: feeds, folders: folders)
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
    func finishSavingFeed(id feedID: UUID, using appState: AppState) async -> FeedRefreshResult? {
        let result: FeedRefreshResult?
        if let feedRefreshService {
            result = await feedRefreshService.refreshAfterAddingFeed(feedID: feedID)
        } else {
            logger.error("Feed refresh service is unavailable for source save completion")
            result = nil
        }

        appState.requestSourcesSidebarReload()
        showFeed(id: feedID, using: appState)
        dismissSourceManagement(using: appState)
        return result
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
        using appState: AppState?
    ) async -> FeedRefreshResult? {
        guard let appState else { return nil }
        return await finishSavingFeed(id: feedID, using: appState)
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

        return await feedRefreshService.refresh(feedID: feedID)
    }

    @MainActor
    func refreshAfterAddingFeed(id feedID: UUID, using appState: AppState) async -> FeedRefreshResult? {
        await finishSavingFeed(id: feedID, using: appState)
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
    func refreshCurrentSelection(using appState: AppState) async -> FeedRefreshBatchResult? {
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
            appState.requestArticleListReload()
        }

        return result
    }

    @MainActor
    func refreshVisibleSources(using appState: AppState) async -> FeedRefreshBatchResult? {
        let result = await refreshAllFeeds()
        if result != nil {
            appState.requestArticleListReload()
        }
        return result
    }

    @MainActor
    func refreshFeedsForBackground() async -> BackgroundFeedRefreshResult? {
        guard let backgroundRefreshService else {
            logger.error("Background refresh service is unavailable")
            return nil
        }

        return await backgroundRefreshService.performScheduledRefresh()
    }
}

private extension AppDependencies {
    @MainActor
    func shouldPresentSelectedArticleInWebViewByDefault() -> Bool {
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
            return await feedRefreshService.refreshFeeds(folderFeedIDs)
        } catch {
            logger.error("Failed to load folder feeds for refresh: \(error)")
            return nil
        }
    }
}
