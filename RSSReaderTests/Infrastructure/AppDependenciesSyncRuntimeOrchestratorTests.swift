import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / Sync Runtime Orchestrator")
@MainActor
struct AppDependenciesSyncRuntimeOrchestratorTests {
    @Test
    func appDependenciesStartSyncCoordinatorAppLifetimeUsesPersistedSyncEnablementAndConnectsRuntimeSources() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator()
        let accountAvailabilityService = AppDependenciesTestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBootstrapPreferenceStore: AppDependenciesFixedSyncBootstrapPreferenceStore(currentPreference: nil),
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

        try await expectAppDependenciesEventually {
            syncCoordinator.runtimeState.phase == .idle
        }
        try await expectAppDependenciesEventually {
            cloudKitRuntimeEventSource.subscriberCount == 1
        }

        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )
        await cloudKitRuntimeEventSource.yield(.started(.export, context))

        try await expectAppDependenciesEventually {
            syncCoordinator.runtimeState.phase == .syncing(.export)
        }
    }

    @Test
    func appDependenciesStartSyncCoordinatorAppLifetimeKeepsDisabledStateWhenPersistedSyncIsOff() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncCoordinator = SyncCoordinator()
        let accountAvailabilityService = AppDependenciesTestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBootstrapPreferenceStore: AppDependenciesFixedSyncBootstrapPreferenceStore(currentPreference: nil),
            iCloudAccountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            syncCoordinator: syncCoordinator
        )

        dependencies.startSyncCoordinatorAppLifetime()

        try await expectAppDependenciesEventually {
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

        try await expectAppDependenciesEventually {
            syncCoordinator.runtimeState == .disabled
        }
    }

    @Test
    func appDependenciesStartSyncCoordinatorAppLifetimeKeepsRuntimeDisabledWhenBootstrapStayedLocalOnly() async throws {
        let syncCoordinator = SyncCoordinator()
        let accountAvailabilityService = AppDependenciesTestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
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

        try await expectAppDependenciesEventually {
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

        try await expectAppDependenciesEventually {
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
        let accountAvailabilityService = AppDependenciesTestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = AppDependenciesTestCloudKitRuntimeEventSource()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            modelContainer: harness.modelContainer,
            syncBootstrapPreferenceStore: AppDependenciesFixedSyncBootstrapPreferenceStore(currentPreference: .enabled),
            iCloudAccountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource,
            syncCoordinator: syncCoordinator
        )

        dependencies.startSyncCoordinatorAppLifetime()

        try await expectAppDependenciesEventually {
            syncCoordinator.runtimeState.phase == .idle
        }
        try await expectAppDependenciesEventually {
            accountAvailabilityService.subscriberCount == 1
                && cloudKitRuntimeEventSource.subscriberCount == 1
        }

        dependencies.stopSyncRuntimeAppLifetime()

        try await expectAppDependenciesEventually {
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
}
