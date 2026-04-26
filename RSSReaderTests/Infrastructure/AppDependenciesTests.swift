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
