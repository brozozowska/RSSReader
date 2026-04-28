import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies")
@MainActor
struct AppDependenciesTests {
    @Test
    func appDependenciesExposeSeparateFolderRepositoryWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.folderRepository != nil)
    }

    @Test
    func appDependenciesExposeSourceManagementServiceWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.sourceManagementService != nil)
    }

    @Test
    func appDependenciesExposeCloudKitRuntimeEventSource() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        _ = harness.dependencies.cloudKitRuntimeEventSource
    }

    @Test
    func appDependenciesExposeInjectedSyncCoordinator() throws {
        let syncCoordinator = SyncCoordinator()
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncCoordinator: syncCoordinator
        )

        #expect(dependencies.syncCoordinator === syncCoordinator)
        #expect(dependencies.iCloudSyncStatusService != nil)
    }

    @Test
    func appDependenciesBuildSwiftDataConfigurationsWithActiveCloudKitOnlyForSyncBackedStore() throws {
        let configurationPlan = AppDependencies.makeSwiftDataConfigurationPlan(
            modelPartition: AppPersistenceModelPartition.current,
            isStoredInMemoryOnly: false
        )

        let configurationsByName = Dictionary(
            uniqueKeysWithValues: configurationPlan.modelContainerConfigurations.map { ($0.name, $0) }
        )
        let syncBackedConfiguration = try #require(configurationsByName["SyncBackedStore"])
        let localOnlyConfiguration = try #require(configurationsByName["LocalOnlyStore"])
        let syncBackedCloudKitDatabase = String(describing: syncBackedConfiguration.cloudKitDatabase)
        let localOnlyCloudKitDatabase = String(describing: localOnlyConfiguration.cloudKitDatabase)

        #expect(configurationPlan.modelContainerConfigurations.count == 2)
        #expect(
            syncBackedCloudKitDatabase
                .contains("_privateDBName: Optional(\"\(CloudKitContainerConfiguration.containerIdentifier)\")")
        )
        #expect(localOnlyCloudKitDatabase.contains("_none: true"))
        #expect(syncBackedConfiguration.isStoredInMemoryOnly == false)
        #expect(localOnlyConfiguration.isStoredInMemoryOnly == false)
    }

    @Test
    func appDependenciesBuildSwiftDataConfigurationsWithoutCloudKitWhenSyncEnablementResolvesDisabled() throws {
        let configurationPlan = AppDependencies.makeSwiftDataConfigurationPlan(
            modelPartition: AppPersistenceModelPartition.current,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: .disabled
        )

        let configurationsByName = Dictionary(
            uniqueKeysWithValues: configurationPlan.modelContainerConfigurations.map { ($0.name, $0) }
        )
        let syncBackedConfiguration = try #require(configurationsByName["SyncBackedStore"])
        let syncBackedCloudKitDatabase = String(describing: syncBackedConfiguration.cloudKitDatabase)

        #expect(syncBackedCloudKitDatabase.contains("_none: true"))
    }

    @Test
    func appDependenciesResolveSyncBackedCloudKitPolicyFromPersistedSyncPreference() {
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: false)
            ) == .disabled
        )
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: true)
            ) == .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
        )
    }

    @Test
    func appDependenciesResolveSyncBackedCloudKitPolicyPrefersLocalBootstrapPreferenceWhenAvailable() {
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: false),
                localBootstrapPreference: .enabled
            ) == .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
        )
        #expect(
            AppDependencies.resolveSyncBackedCloudKitPolicy(
                syncEnablementPolicy: .current,
                bootstrapSettingsSnapshot: AppSettingsSnapshot(useiCloudSync: true),
                localBootstrapPreference: .disabled
            ) == .disabled
        )
    }

    @Test
    func appDependenciesFetchSyncEnablementBootstrapSettingsFromModelContainer() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                useiCloudSync: true,
                updatedAt: .distantPast
            )
        )

        let bootstrapSettings = try AppDependencies.fetchSyncEnablementBootstrapSettings(
            from: harness.modelContainer
        )

        #expect(bootstrapSettings?.useiCloudSync == true)
    }

    @Test
    func appDependenciesBootstrapFailureDescriptionIncludesNSErrorContext() {
        let underlyingError = NSError(
            domain: "NSCocoaErrorDomain",
            code: 134060,
            userInfo: [
                NSLocalizedDescriptionKey: "Persistent store failed to load."
            ]
        )
        let topLevelError = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [
                NSUnderlyingErrorKey: underlyingError
            ]
        )

        let description = AppDependencies.makeModelContainerBootstrapFailureDescription(
            for: topLevelError,
            syncBackedCloudKitPolicy: .privateContainer("iCloud.ru.brozozowska.RSSReader")
        )

        #expect(description.contains("privateContainer(\"iCloud.ru.brozozowska.RSSReader\")"))
        #expect(description.contains("Error: domain=SwiftData.SwiftDataError code=1"))
        #expect(description.contains("Underlying error 1: domain=NSCocoaErrorDomain code=134060"))
        #expect(description.contains("Persistent store failed to load."))
    }

    @Test
    func appDependenciesBootstrapFailureDescriptionAppendsPersistentStoreProbeDetails() {
        let error = NSError(
            domain: "SwiftData.SwiftDataError",
            code: 1,
            userInfo: [:]
        )

        let description = AppDependencies.makeModelContainerBootstrapFailureDescription(
            for: error,
            syncBackedCloudKitPolicy: .privateContainer("iCloud.ru.brozozowska.RSSReader"),
            persistentStoreProbeFailureDescription: "Error: domain=NSCocoaErrorDomain code=134060 localizedDescription=Persistent store probe failed. userInfo={}"
        )

        #expect(description.contains("Persistent store probe:"))
        #expect(description.contains("domain=NSCocoaErrorDomain code=134060"))
        #expect(description.contains("Persistent store probe failed."))
    }

    @Test
    func appDependenciesStartSyncCoordinatorAppLifetimeUsesPersistedSyncEnablementAndConnectsRuntimeSources() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator()
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            iCloudAccountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            syncCoordinator: syncCoordinator
        )
        let appSettingsService = try #require(dependencies.appSettingsService)

        _ = try appSettingsService.saveSettings(
            AppSettingsSnapshot(useiCloudSync: true),
            updatedAt: .distantPast
        )

        dependencies.startSyncCoordinatorAppLifetime()

        try await expectEventually {
            syncCoordinator.runtimeState.phase == .idle
        }

        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )
        await cloudKitRuntimeEventSource.yield(.started(.export, context))

        try await expectEventually {
            syncCoordinator.runtimeState.phase == .syncing(.export)
        }
    }

    @Test
    func appDependenciesStartSyncCoordinatorAppLifetimeKeepsDisabledStateWhenPersistedSyncIsOff() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator()
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            iCloudAccountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            syncCoordinator: syncCoordinator
        )

        dependencies.startSyncCoordinatorAppLifetime()

        try await expectEventually {
            syncCoordinator.runtimeState == .disabled
        }

        await accountAvailabilityService.yield(.restricted)
        await cloudKitRuntimeEventSource.yield(
            .started(
                .setup,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: nil
                )
            )
        )

        try await expectEventually {
            syncCoordinator.runtimeState == .disabled
        }
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequestsReloadWhenRemoteChangeAndImportCompletionArrive() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        await cloudKitRuntimeEventSource.yield(
            .finished(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                )
            )
        )

        try await expectEventually {
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequestsReloadWhenImportCompletionArrivesBeforeRemoteChange() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)

        await cloudKitRuntimeEventSource.yield(
            .finished(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                )
            )
        )
        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )

        try await expectEventually {
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequiresFreshRemoteChangeAfterImportFailure() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        await cloudKitRuntimeEventSource.yield(
            .failed(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                ),
                "Import failed."
            )
        )
        await cloudKitRuntimeEventSource.yield(
            .finished(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                )
            )
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(appState.sourcesSidebarReloadID == initialSidebarReloadID)
        #expect(appState.articleListReloadID == initialArticleListReloadID)
        #expect(appState.articleScreenReloadID == initialArticleScreenReloadID)

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )

        try await expectEventually {
            appState.sourcesSidebarReloadID != initialSidebarReloadID
                && appState.articleListReloadID != initialArticleListReloadID
                && appState.articleScreenReloadID != initialArticleScreenReloadID
        }
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadForExportCompletion() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        await cloudKitRuntimeEventSource.yield(
            .finished(
                .export,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                )
            )
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(appState.sourcesSidebarReloadID == initialSidebarReloadID)
        #expect(appState.articleListReloadID == initialArticleListReloadID)
        #expect(appState.articleScreenReloadID == initialArticleScreenReloadID)
    }
}

private actor TestICloudAccountAvailabilityService: ICloudAccountAvailabilityService {
    private let initialAvailability: ICloudAccountAvailability
    private let stream: AsyncStream<ICloudAccountAvailability>
    private let continuation: AsyncStream<ICloudAccountAvailability>.Continuation

    init(initialAvailability: ICloudAccountAvailability) {
        self.initialAvailability = initialAvailability

        let components = AsyncStream.makeStream(of: ICloudAccountAvailability.self)
        self.stream = components.stream
        self.continuation = components.continuation
    }

    func currentAvailability() async -> ICloudAccountAvailability {
        initialAvailability
    }

    nonisolated func availabilityChanges() -> AsyncStream<ICloudAccountAvailability> {
        stream
    }

    func yield(_ availability: ICloudAccountAvailability) {
        continuation.yield(availability)
    }
}

private actor TestCloudKitRuntimeEventSource: CloudKitRuntimeEventSource {
    private let stream: AsyncStream<CloudKitRuntimeEvent>
    private let continuation: AsyncStream<CloudKitRuntimeEvent>.Continuation

    init() {
        let components = AsyncStream.makeStream(of: CloudKitRuntimeEvent.self)
        self.stream = components.stream
        self.continuation = components.continuation
    }

    nonisolated func events() -> AsyncStream<CloudKitRuntimeEvent> {
        stream
    }

    func yield(_ event: CloudKitRuntimeEvent) {
        continuation.yield(event)
    }
}

private actor TestPersistentStoreRemoteChangeSource: PersistentStoreRemoteChangeSource {
    private let stream: AsyncStream<PersistentStoreRemoteChangeEvent>
    private let continuation: AsyncStream<PersistentStoreRemoteChangeEvent>.Continuation

    init() {
        let components = AsyncStream.makeStream(of: PersistentStoreRemoteChangeEvent.self)
        self.stream = components.stream
        self.continuation = components.continuation
    }

    nonisolated func events() -> AsyncStream<PersistentStoreRemoteChangeEvent> {
        stream
    }

    func yield(_ event: PersistentStoreRemoteChangeEvent) {
        continuation.yield(event)
    }
}

private struct TimedOutError: Error {}

private func expectEventually(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))

    while ContinuousClock.now < deadline {
        if await MainActor.run(body: condition) {
            return
        }

        try await Task.sleep(for: .milliseconds(10))
    }

    throw TimedOutError()
}
