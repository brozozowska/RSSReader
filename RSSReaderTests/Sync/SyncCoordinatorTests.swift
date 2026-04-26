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
}
