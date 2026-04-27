import Foundation

enum ICloudSyncStatus: Equatable, Sendable {
    case disabled
    case statusUnavailable
    case idle
    case syncing
    case failed(String)
}

protocol ICloudSyncStatusService {
    @MainActor
    func currentStatus() throws -> ICloudSyncStatus
}

struct DefaultICloudSyncStatusService: ICloudSyncStatusService {
    let syncCoordinator: SyncCoordinator

    @MainActor
    func currentStatus() throws -> ICloudSyncStatus {
        syncCoordinator.iCloudSyncStatus
    }
}
