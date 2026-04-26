import Foundation
import Testing
@testable import RSSReader

@Suite("Sync / Coordinator")
@MainActor
struct SyncCoordinatorTests {
    @Test
    func initStartsInDisabledPhaseWhenSyncIsDisabled() {
        let coordinator = SyncCoordinator()

        #expect(coordinator.runtimeState == .disabled)
        #expect(coordinator.iCloudSyncStatus == .disabled)
    }

    @Test
    func initStartsInStatusUnavailablePhaseWhenSyncIsEnabled() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)

        #expect(coordinator.runtimeState.phase == .statusUnavailable)
        #expect(coordinator.iCloudSyncStatus == .statusUnavailable)
    }

    @Test
    func applyAccountAvailabilityTransitionsEnabledCoordinatorToIdle() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)

        coordinator.applyAccountAvailability(.available)

        #expect(coordinator.runtimeState.phase == .idle)
        #expect(coordinator.iCloudSyncStatus == .idle)
    }

    @Test
    func applyAccountAvailabilityPreservesAccountProblemInRuntimeState() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)

        coordinator.applyAccountAvailability(.noAccount)

        #expect(coordinator.runtimeState.phase == .accountProblem(.noAccount))
        #expect(coordinator.runtimeState.accountAvailability == .noAccount)
        #expect(coordinator.iCloudSyncStatus == .statusUnavailable)
    }

    @Test
    func applyCloudKitRuntimeEventTransitionsCoordinatorToSyncing() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )

        coordinator.applyCloudKitRuntimeEvent(.started(.import, context))

        #expect(coordinator.runtimeState.phase == .syncing(.import))
        #expect(coordinator.runtimeState.activeActivity == .import)
        #expect(coordinator.iCloudSyncStatus == .syncing)
    }

    @Test
    func applyCloudKitFailureTransitionsCoordinatorToFailedState() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: .now
        )

        coordinator.applyCloudKitRuntimeEvent(.failed(.export, context, "Export request failed."))

        #expect(
            coordinator.runtimeState.phase
                == .failed(SyncRuntimeFailure(activity: .export, message: "Export request failed."))
        )
        #expect(coordinator.iCloudSyncStatus == .failed("Export request failed."))
    }

    @Test
    func clearRuntimeFailureRestoresPhaseFromLatestAccountAvailability() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: .now
        )

        coordinator.applyAccountAvailability(.available)
        coordinator.applyCloudKitRuntimeEvent(.failed(.setup, context, nil))
        coordinator.clearRuntimeFailure()

        #expect(coordinator.runtimeState.phase == .idle)
        #expect(coordinator.iCloudSyncStatus == .idle)
    }

    @Test
    func applySyncEnablementClearsRuntimeInputsWhenSyncIsDisabled() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )

        coordinator.applyAccountAvailability(.available)
        coordinator.applyCloudKitRuntimeEvent(.started(.setup, context))
        coordinator.applySyncEnablement(isEnabled: false)

        #expect(coordinator.runtimeState == .disabled)
        #expect(coordinator.iCloudSyncStatus == .disabled)
    }

    @Test
    func connectRuntimeSourcesAppliesCurrentAccountAvailability() async throws {
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let coordinator = SyncCoordinator(isSyncEnabled: true)

        coordinator.connectRuntimeSources(
            accountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource
        )

        try await expectEventually {
            coordinator.runtimeState.phase == .idle
        }
        #expect(coordinator.iCloudSyncStatus == .idle)
    }

    @Test
    func connectRuntimeSourcesConsumesAccountAvailabilityChanges() async throws {
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let coordinator = SyncCoordinator(isSyncEnabled: true)

        coordinator.connectRuntimeSources(
            accountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource
        )
        try await expectEventually {
            coordinator.runtimeState.phase == .idle
        }

        await accountAvailabilityService.yield(.restricted)

        try await expectEventually {
            coordinator.runtimeState.phase == .accountProblem(.restricted)
        }
        #expect(coordinator.runtimeState.accountAvailability == .restricted)
    }

    @Test
    func connectRuntimeSourcesConsumesCloudKitRuntimeEvents() async throws {
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let coordinator = SyncCoordinator(isSyncEnabled: true)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )

        coordinator.connectRuntimeSources(
            accountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource
        )
        try await expectEventually {
            coordinator.runtimeState.phase == .idle
        }

        await cloudKitRuntimeEventSource.yield(.started(.import, context))

        try await expectEventually {
            coordinator.runtimeState.phase == .syncing(.import)
        }
        #expect(coordinator.iCloudSyncStatus == .syncing)
    }

    @Test
    func connectRuntimeSourcesConsumesCloudKitFailures() async throws {
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let coordinator = SyncCoordinator(isSyncEnabled: true)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: .now
        )

        coordinator.connectRuntimeSources(
            accountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource
        )
        try await expectEventually {
            coordinator.runtimeState.phase == .idle
        }

        await cloudKitRuntimeEventSource.yield(.failed(.setup, context, "Setup failed."))

        try await expectEventually {
            coordinator.runtimeState.phase == .failed(
                SyncRuntimeFailure(activity: .setup, message: "Setup failed.")
            )
        }
        #expect(coordinator.iCloudSyncStatus == .failed("Setup failed."))
    }

    @Test
    func connectRuntimeSourcesDoesNotLeaveDisabledStateWhenSyncIsDisabled() async throws {
        let accountAvailabilityService = TestICloudAccountAvailabilityService(initialAvailability: .available)
        let cloudKitRuntimeEventSource = TestCloudKitRuntimeEventSource()
        let coordinator = SyncCoordinator(isSyncEnabled: false)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )

        coordinator.connectRuntimeSources(
            accountAvailabilityService: accountAvailabilityService,
            cloudKitRuntimeEventSource: cloudKitRuntimeEventSource
        )
        await accountAvailabilityService.yield(.restricted)
        await cloudKitRuntimeEventSource.yield(.started(.export, context))

        try await expectEventually {
            coordinator.runtimeState == .disabled
        }
        #expect(coordinator.iCloudSyncStatus == .disabled)
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
