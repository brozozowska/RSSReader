import Foundation

extension AppComposition {
    @MainActor
    static func applyCurrentICloudSyncStatus(
        from syncCoordinator: SyncCoordinator?,
        to appState: AppState
    ) {
        guard let syncCoordinator else { return }

        let resolvedStatus = syncCoordinator.iCloudSyncStatus
        if appState.iCloudSyncStatus != resolvedStatus {
            appState.applyICloudSyncStatus(resolvedStatus)
        }
    }
}
