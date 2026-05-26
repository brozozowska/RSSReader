import CloudKit
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
    }

    @Test
    func appDependenciesExposeBackgroundRefreshRuntimePrerequisitesSnapshot() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer
        )

        let snapshot = dependencies.currentBackgroundRefreshRuntimePrerequisites()

        #expect(snapshot.refreshIntervalPreference == .manual)
        #expect(snapshot.schedulingMode == .manual)
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
    func appDependenciesResolveSyncBootstrapContextKeepsDesiredSyncIntentWhenCloudKitBootstrapFallsBackToLocalOnly() {
        let context = AppDependencies.resolveSyncBootstrapContext(
            desiredBootPreference: .enabled,
            desiredPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
            logger: TestLogger(),
            resolvedAccountStatus: .temporarilyUnavailable
        )

        #expect(context.desiredBootPreference == .enabled)
        #expect(context.desiredSyncBackedCloudKitPolicy == .privateContainer(CloudKitContainerConfiguration.containerIdentifier))
        #expect(context.modelContainerCloudKitPolicy == .disabled)
        #expect(context.accountAvailabilityAtBootstrap == .temporarilyUnavailable)
        #expect(context.isSyncRequested)
        #expect(context.isUsingCloudKitForCurrentLaunch == false)
        #expect(context.isRunningLocalOnlyFallbackForCurrentLaunch)
    }

    @Test
    func appDependenciesResolveSyncBootstrapContextGatesCloudKitBootstrapForEachAccountStatus() {
        for scenario in SyncBootstrapAccountStatusScenario.allCases {
            let context = AppDependencies.resolveSyncBootstrapContext(
                desiredBootPreference: .enabled,
                desiredPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
                logger: TestLogger(),
                resolvedAccountStatus: scenario.accountStatus
            )

            #expect(context.desiredBootPreference == .enabled)
            #expect(context.desiredSyncBackedCloudKitPolicy == .privateContainer(CloudKitContainerConfiguration.containerIdentifier))
            #expect(context.modelContainerCloudKitPolicy == scenario.expectedModelContainerPolicy)
            #expect(context.accountAvailabilityAtBootstrap == scenario.expectedAccountAvailability)
            #expect(context.isSyncRequested)
            #expect(context.isUsingCloudKitForCurrentLaunch == scenario.expectsCloudKitBootstrap)
            #expect(context.isRunningLocalOnlyFallbackForCurrentLaunch == scenario.expectsLocalOnlyFallback)
        }
    }

    @Test
    func appDependenciesResolveSyncBootstrapContextLogsAccountResolutionAndFallbackSelection() {
        let logger = RecordingLogger()

        _ = AppDependencies.resolveSyncBootstrapContext(
            desiredBootPreference: .enabled,
            desiredPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
            logger: logger,
            resolvedAccountStatus: .noAccount
        )

        #expect(logger.contains("Resolved sync bootstrap account status"))
        #expect(logger.contains("availability=noAccount"))
        #expect(logger.contains("Skipped CloudKit-backed model container bootstrap because account status is"))
        #expect(logger.contains("noAccount"))
        #expect(logger.contains("using local-only fallback for current launch"))
    }

    @Test
    func appDependenciesResolveSyncBootstrapContextLogsLocalOnlyBootstrapPolicyWithoutCloudKit() {
        let logger = RecordingLogger()

        _ = AppDependencies.resolveSyncBootstrapContext(
            desiredBootPreference: .disabled,
            desiredPolicy: .disabled,
            logger: logger
        )

        #expect(logger.contains("Using local-only sync bootstrap path because desired policy does not require CloudKit"))
        #expect(logger.contains("desiredBootPreference=disabled"))
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
            syncBootstrapPreferenceStore: FixedAppSyncBootstrapPreferenceStore(currentPreference: nil),
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
        try await expectEventually {
            cloudKitRuntimeEventSource.subscriberCount == 1
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
            syncBootstrapPreferenceStore: FixedAppSyncBootstrapPreferenceStore(currentPreference: nil),
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
    func appDependenciesStartSyncCoordinatorAppLifetimeKeepsRuntimeDisabledWhenBootstrapStayedLocalOnly() async throws {
        let syncCoordinator = SyncCoordinator()
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            syncBootstrapContext: AppSyncBootstrapContext(
                desiredBootPreference: .enabled,
                desiredSyncBackedCloudKitPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
                modelContainerCloudKitPolicy: .disabled,
                accountAvailabilityAtBootstrap: .temporarilyUnavailable
            ),
            iCloudAccountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            syncCoordinator: syncCoordinator
        )

        dependencies.startSyncCoordinatorAppLifetime()

        try await expectEventually {
            syncCoordinator.runtimeState == .disabled
        }

        await accountAvailabilityService.yield(.available)
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
    func appDependenciesStartSyncCoordinatorAppLifetimeLogsBootstrapEnablementResolution() {
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(logger: logger)
        let dependencies = AppDependencies(
            logger: logger,
            syncBootstrapContext: AppSyncBootstrapContext(
                desiredBootPreference: .enabled,
                desiredSyncBackedCloudKitPolicy: .privateContainer(CloudKitContainerConfiguration.containerIdentifier),
                modelContainerCloudKitPolicy: .disabled,
                accountAvailabilityAtBootstrap: .temporarilyUnavailable
            ),
            syncCoordinator: syncCoordinator
        )

        dependencies.startSyncCoordinatorAppLifetime()

        #expect(logger.contains("Resolved initial sync enablement from bootstrap context"))
        #expect(logger.contains("isUsingCloudKitForCurrentLaunch=false"))
        #expect(logger.contains("Starting SyncCoordinator app lifetime: isSyncEnabled=false"))
    }

    @Test
    func appDependenciesStopSyncRuntimeAppLifetimeDisconnectsSyncCoordinatorRuntimeSources() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator()
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBootstrapPreferenceStore: FixedAppSyncBootstrapPreferenceStore(currentPreference: .enabled),
            iCloudAccountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            syncCoordinator: syncCoordinator
        )

        dependencies.startSyncCoordinatorAppLifetime()

        try await expectEventually {
            syncCoordinator.runtimeState.phase == .idle
        }
        try await expectEventually {
            accountAvailabilityService.subscriberCount == 1
                && cloudKitRuntimeEventSource.subscriberCount == 1
        }

        dependencies.stopSyncRuntimeAppLifetime()

        try await expectEventually {
            accountAvailabilityService.subscriberCount == 0
                && cloudKitRuntimeEventSource.subscriberCount == 0
        }

        await accountAvailabilityService.yield(.restricted)
        await cloudKitRuntimeEventSource.yield(
            .started(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: nil
                )
            )
        )

        try await Task.sleep(for: .milliseconds(100))

        #expect(syncCoordinator.runtimeState.phase == .idle)
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
            syncBackedStoreReference: testSyncBackedStoreReference(),
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectEventually {
            cloudKitRuntimeEventSource.subscriberCount == 1
                && remoteChangeSource.subscriberCount == 1
        }

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

        #expect(appState.lastContentReloadTrigger == .remoteSyncImport)
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
            syncBackedStoreReference: testSyncBackedStoreReference(),
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

        #expect(appState.lastContentReloadTrigger == .remoteSyncImport)
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequiresFreshRemoteChangeAfterImportFailure() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: logger,
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        try await expectEventually {
            cloudKitRuntimeEventSource.subscriberCount == 1
                && remoteChangeSource.subscriberCount == 1
        }

        await remoteChangeSource.yield(
            PersistentStoreRemoteChangeEvent(
                storeUUID: "SyncBackedStore",
                storeURL: URL(string: "file:///tmp/SyncBackedStore.sqlite")
            )
        )
        try await expectEventually {
            logger.contains(
                "Observed persistent store remote change; marked store change pending",
                level: .info
            )
        }
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
        try await expectEventually {
            logger.contains(
                "Observed CloudKit import failure; cleared pending remote reload correlation",
                level: .error
            )
        }
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

        try await expectNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
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
            syncBackedStoreReference: testSyncBackedStoreReference(),
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

        try await expectNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
        )
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadForMismatchedRemoteChangeStore() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
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
                storeUUID: "LocalOnlyStore",
                storeURL: URL(string: "file:///tmp/LocalOnlyStore.sqlite")
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
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadForMismatchedImportStoreIdentifier() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
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
                    storeIdentifier: "LocalOnlyStore",
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

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeDoesNotReloadTwiceForRepeatedImportCompletionWithoutNewRemoteChange() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
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

        let firstSidebarReloadID = appState.sourcesSidebarReloadID
        let firstArticleListReloadID = appState.articleListReloadID
        let firstArticleScreenReloadID = appState.articleScreenReloadID

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

        #expect(appState.sourcesSidebarReloadID == firstSidebarReloadID)
        #expect(appState.articleListReloadID == firstArticleListReloadID)
        #expect(appState.articleScreenReloadID == firstArticleScreenReloadID)
    }

    @Test
    func appDependenciesStartRemoteSyncReloadAppLifetimeRequiresFreshRemoteChangeAfterImportCancellation() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: logger,
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
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
        try await expectEventually {
            logger.contains(
                "Observed persistent store remote change; marked store change pending",
                level: .info
            )
        }
        await cloudKitRuntimeEventSource.yield(
            .failed(
                .import,
                CloudKitRuntimeEventContext(
                    identifier: UUID(),
                    storeIdentifier: "SyncBackedStore",
                    startDate: .distantPast,
                    endDate: .now
                ),
                "cancelled"
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

        try await expectNoReload(
            sidebarReloadID: initialSidebarReloadID,
            articleListReloadID: initialArticleListReloadID,
            articleScreenReloadID: initialArticleScreenReloadID,
            in: appState
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
    func appDependenciesRemoteSyncReloadLogsCorrelationEvents() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true, logger: logger)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: logger,
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()

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
            logger.contains(
                "Requesting app-level remote sync reload after matching import completion and persistent store remote change for sync-backed storeIdentifier=SyncBackedStore"
            )
        }

        #expect(logger.contains("Starting remote sync reload app lifetime observation"))
        #expect(logger.contains("Observed persistent store remote change; marked store change pending"))
        #expect(logger.contains("Observed CloudKit import completion; marked import completion pending"))
    }

    @Test
    func appLevelReloadBoundaryKeepsRemoteSyncAndBackgroundRefreshTriggersSeparateAfterDiagnosticsCleanup() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let backgroundRefreshHandoffCoordinator = RecordingBackgroundRefreshForegroundHandoffCoordinator()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
            backgroundRefreshForegroundHandoffCoordinator: backgroundRefreshHandoffCoordinator,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        AppComposition.bindBackgroundRefreshForegroundReloadHandler(
            using: dependencies,
            appState: appState
        )
        dependencies.startRemoteSyncReloadAppLifetime(using: appState)

        backgroundRefreshHandoffCoordinator.triggerBoundReloadHandler()

        #expect(appState.lastContentReloadTrigger == .backgroundRefresh)
        #expect(appState.sourcesSidebarReloadID != initialSidebarReloadID)
        #expect(appState.articleListReloadID != initialArticleListReloadID)
        #expect(appState.articleScreenReloadID != initialArticleScreenReloadID)

        let backgroundRefreshSidebarReloadID = appState.sourcesSidebarReloadID
        let backgroundRefreshArticleListReloadID = appState.articleListReloadID
        let backgroundRefreshArticleScreenReloadID = appState.articleScreenReloadID

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
            appState.lastContentReloadTrigger == .remoteSyncImport
                && appState.sourcesSidebarReloadID != backgroundRefreshSidebarReloadID
                && appState.articleListReloadID != backgroundRefreshArticleListReloadID
                && appState.articleScreenReloadID != backgroundRefreshArticleScreenReloadID
        }
    }

    @Test
    func appDependenciesStopSyncRuntimeAppLifetimeCancelsRemoteReloadObservation() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        syncCoordinator.applyAccountAvailability(.available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let remoteChangeSource = TestPersistentStoreRemoteChangeSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBackedStoreReference: testSyncBackedStoreReference(),
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            persistentStoreRemoteChangeSource: remoteChangeSource,
            syncCoordinator: syncCoordinator
        )
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        dependencies.startRemoteSyncReloadAppLifetime(using: appState)
        dependencies.stopSyncRuntimeAppLifetime()

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

        try await Task.sleep(for: .milliseconds(100))

        #expect(appState.sourcesSidebarReloadID == initialSidebarReloadID)
        #expect(appState.articleListReloadID == initialArticleListReloadID)
        #expect(appState.articleScreenReloadID == initialArticleScreenReloadID)
    }

    @Test
    func appDependenciesMakeWithSwiftDataLogsModelContainerSetupMarkers() {
        let logger = RecordingLogger()
        let syncCoordinator = SyncCoordinator(logger: logger)

        _ = AppDependencies.makeWithSwiftData(
            modelPartition: .current,
            syncEnablementPolicy: .current,
            syncCoordinator: syncCoordinator,
            syncBootstrapPreferenceStore: FixedAppSyncBootstrapPreferenceStore(currentPreference: .disabled),
            logger: logger
        )

        #expect(logger.contains("Starting model container setup"))
        #expect(logger.contains("syncBackedStoreIdentifier=SyncBackedStore"))
        #expect(logger.contains("Model container setup succeeded"))
    }
}

private final class TestICloudAccountAvailabilityService: ICloudAccountAvailabilityService, @unchecked Sendable {
    private let initialAvailability: ICloudAccountAvailability
    private let queue = DispatchQueue(label: "RSSReaderTests.AppDependencies.AccountAvailability")
    private var continuations: [UUID: AsyncStream<ICloudAccountAvailability>.Continuation] = [:]

    init(initialAvailability: ICloudAccountAvailability) {
        self.initialAvailability = initialAvailability
    }

    func currentAvailability() async -> ICloudAccountAvailability {
        initialAvailability
    }

    func availabilityChanges() -> AsyncStream<ICloudAccountAvailability> {
        AsyncStream { continuation in
            let id = UUID()
            queue.sync {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async {
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    var subscriberCount: Int {
        queue.sync {
            continuations.count
        }
    }

    func yield(_ availability: ICloudAccountAvailability) async {
        let activeContinuations = queue.sync {
            Array(continuations.values)
        }
        activeContinuations.forEach { continuation in
            continuation.yield(availability)
        }
    }
}

@MainActor
private final class RecordingBackgroundRefreshForegroundHandoffCoordinator:
    BackgroundRefreshForegroundHandoffCoordinating
{
    private var reloadHandler: (@MainActor () -> Void)?

    func bindReloadHandler(_ handler: @escaping @MainActor () -> Void) {
        reloadHandler = handler
    }

    func unbindReloadHandler() {
        reloadHandler = nil
    }

    func updateRuntimeState(_ runtimeState: AppRuntimeReloadState) {}

    func handleBackgroundRefreshExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome) {}

    func triggerBoundReloadHandler() {
        reloadHandler?()
    }
}

private final class TestCloudKitRuntimeEventSource: CloudKitRuntimeEventSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "RSSReaderTests.AppDependencies.CloudKitRuntimeEvents")
    private var continuations: [UUID: AsyncStream<CloudKitRuntimeEvent>.Continuation] = [:]

    func events() -> AsyncStream<CloudKitRuntimeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            queue.sync {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async {
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    var subscriberCount: Int {
        queue.sync {
            continuations.count
        }
    }

    func yield(_ event: CloudKitRuntimeEvent) async {
        let activeContinuations = queue.sync {
            Array(continuations.values)
        }
        activeContinuations.forEach { continuation in
            continuation.yield(event)
        }
    }
}

private final class TestPersistentStoreRemoteChangeSource: PersistentStoreRemoteChangeSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "RSSReaderTests.AppDependencies.PersistentStoreRemoteChanges")
    private var continuations: [UUID: AsyncStream<PersistentStoreRemoteChangeEvent>.Continuation] = [:]

    func events() -> AsyncStream<PersistentStoreRemoteChangeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            queue.sync {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async {
                    self.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    var subscriberCount: Int {
        queue.sync {
            continuations.count
        }
    }

    func yield(_ event: PersistentStoreRemoteChangeEvent) async {
        let activeContinuations = queue.sync {
            Array(continuations.values)
        }
        activeContinuations.forEach { continuation in
            continuation.yield(event)
        }
    }
}

private struct FixedAppSyncBootstrapPreferenceStore: AppSyncBootstrapPreferenceStoring {
    let currentPreference: AppSyncBootPreference?

    func currentBootPreference() -> AppSyncBootPreference? {
        currentPreference
    }

    func saveBootPreference(_ preference: AppSyncBootPreference) {}
}

private struct TimedOutError: Error {}

private enum SyncBootstrapAccountStatusScenario: CaseIterable {
    case available
    case temporarilyUnavailable
    case noAccount
    case restricted
    case couldNotDetermine

    var accountStatus: CKAccountStatus {
        switch self {
        case .available:
            .available
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .couldNotDetermine:
            .couldNotDetermine
        }
    }

    var expectedAccountAvailability: ICloudAccountAvailability {
        DefaultICloudAccountAvailabilityService.mapAccountAvailability(from: accountStatus)
    }

    var expectedModelContainerPolicy: AppPersistenceCloudKitPolicy {
        expectsCloudKitBootstrap
            ? .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
            : .disabled
    }

    var expectsCloudKitBootstrap: Bool {
        self == .available
    }

    var expectsLocalOnlyFallback: Bool {
        expectsCloudKitBootstrap == false
    }
}

private func testSyncBackedStoreReference() -> SyncBackedStoreReference {
    SyncBackedStoreReference(
        runtimeStoreIdentifier: "SyncBackedStore",
        persistentStoreURL: URL(fileURLWithPath: "/tmp/SyncBackedStore.sqlite")
    )
}

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

private func expectNoReload(
    sidebarReloadID: UUID,
    articleListReloadID: UUID,
    articleScreenReloadID: UUID,
    in appState: AppState,
    durationNanoseconds: UInt64 = 200_000_000
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(durationNanoseconds))

    while ContinuousClock.now < deadline {
        let reloadOccurred = await MainActor.run {
            appState.sourcesSidebarReloadID != sidebarReloadID
                || appState.articleListReloadID != articleListReloadID
                || appState.articleScreenReloadID != articleScreenReloadID
        }

        #expect(reloadOccurred == false)
        try await Task.sleep(for: .milliseconds(10))
    }
}
