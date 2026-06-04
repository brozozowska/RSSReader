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
    func applyAccountAvailabilityMapsEachAvailabilityToExpectedRuntimePhase() {
        for scenario in SyncCoordinatorAccountAvailabilityScenario.allCases {
            let coordinator = SyncCoordinator(isSyncEnabled: true)

            coordinator.applyAccountAvailability(scenario.availability)

            #expect(coordinator.runtimeState.phase == scenario.expectedPhase)
            #expect(coordinator.runtimeState.accountAvailability == scenario.availability)
            #expect(coordinator.iCloudSyncStatus == scenario.expectedICloudSyncStatus)
        }
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
    func applyCloudKitRuntimeEventRestoresIdlePhaseWhenImportFinishes() {
        let coordinator = SyncCoordinator(isSyncEnabled: true)
        let activeContext = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )
        let finishedContext = CloudKitRuntimeEventContext(
            identifier: activeContext.identifier,
            storeIdentifier: activeContext.storeIdentifier,
            startDate: activeContext.startDate,
            endDate: .now
        )

        coordinator.applyAccountAvailability(.available)
        coordinator.applyCloudKitRuntimeEvent(.started(.import, activeContext))
        coordinator.applyCloudKitRuntimeEvent(.finished(.import, finishedContext))

        #expect(coordinator.runtimeState.phase == .idle)
        #expect(coordinator.runtimeState.activeActivity == nil)
        #expect(coordinator.runtimeState.lastEventContext == finishedContext)
        #expect(coordinator.iCloudSyncStatus == .idle)
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
    func applyCloudKitFailureLogsRuntimeFailureContextAndStateTransition() {
        let logger = RecordingLogger()
        let coordinator = SyncCoordinator(isSyncEnabled: true, logger: logger)
        let context = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: .now
        )

        coordinator.applyCloudKitRuntimeEvent(.failed(.setup, context, "Setup failed."))

        #expect(logger.contains("SyncCoordinator handling CloudKit runtime failure", level: .error))
        #expect(logger.contains("storeIdentifier=SyncBackedStore", level: .error))
        #expect(logger.contains("runtime state changed", level: .info))
        #expect(logger.contains("failed(activity=setup, message=Setup failed.)", level: .info))
    }

    @Test
    func applyCloudKitRuntimeEventLogsActivityStartAndFinish() {
        let logger = RecordingLogger()
        let coordinator = SyncCoordinator(isSyncEnabled: true, logger: logger)
        let startedContext = CloudKitRuntimeEventContext(
            identifier: UUID(),
            storeIdentifier: "SyncBackedStore",
            startDate: .distantPast,
            endDate: nil
        )
        let finishedContext = CloudKitRuntimeEventContext(
            identifier: startedContext.identifier,
            storeIdentifier: startedContext.storeIdentifier,
            startDate: startedContext.startDate,
            endDate: .now
        )

        coordinator.applyCloudKitRuntimeEvent(.started(.import, startedContext))
        coordinator.applyCloudKitRuntimeEvent(.finished(.import, finishedContext))

        #expect(logger.contains("SyncCoordinator handling CloudKit runtime activity start", level: .info))
        #expect(logger.contains("started(activity=import, storeIdentifier=SyncBackedStore", level: .info))
        #expect(logger.contains("SyncCoordinator handling CloudKit runtime activity finish", level: .info))
        #expect(logger.contains("finished(activity=import, storeIdentifier=SyncBackedStore", level: .info))
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
        try await expectEventually {
            accountAvailabilityService.subscriberCount == 1
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
        try await expectEventually {
            cloudKitRuntimeEventSource.subscriberCount == 1
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
        try await expectEventually {
            cloudKitRuntimeEventSource.subscriberCount == 1
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

private final class TestICloudAccountAvailabilityService: ICloudAccountAvailabilityService, @unchecked Sendable {
    private let initialAvailability: ICloudAccountAvailability
    private let queue = DispatchQueue(label: "RSSReaderTests.SyncCoordinator.AccountAvailability")
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

private final class TestCloudKitRuntimeEventSource: CloudKitRuntimeEventSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "RSSReaderTests.SyncCoordinator.CloudKitRuntimeEvents")
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

private struct TimedOutError: Error {}

private enum SyncCoordinatorAccountAvailabilityScenario: CaseIterable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var availability: ICloudAccountAvailability {
        switch self {
        case .available:
            .available
        case .noAccount:
            .noAccount
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .couldNotDetermine
        }
    }

    var expectedPhase: SyncRuntimePhase {
        switch availability {
        case .available:
            .idle
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine:
            .accountProblem(availability)
        }
    }

    var expectedICloudSyncStatus: ICloudSyncStatus {
        switch availability {
        case .available:
            .idle
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine:
            .statusUnavailable
        }
    }
}

private func expectEventually(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
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
