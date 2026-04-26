import Testing
@testable import RSSReader

@Suite("Infrastructure / AppComposition")
@MainActor
struct AppCompositionTests {
    @Test
    func appCompositionAppliesCurrentICloudSyncStatusFromSyncCoordinatorToAppState() {
        let syncCoordinator = SyncCoordinator(isSyncEnabled: true)
        let appState = AppState()

        syncCoordinator.applyAccountAvailability(.available)
        AppComposition.applyCurrentICloudSyncStatus(from: syncCoordinator, to: appState)

        #expect(appState.iCloudSyncStatus == .idle)
    }

    @Test
    func appCompositionLeavesAppStateUntouchedWhenSyncCoordinatorIsUnavailable() {
        let appState = AppState()
        appState.applyICloudSyncStatus(.syncing)

        AppComposition.applyCurrentICloudSyncStatus(from: nil, to: appState)

        #expect(appState.iCloudSyncStatus == .syncing)
    }
}
