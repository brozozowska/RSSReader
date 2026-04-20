import Foundation

enum ICloudSyncStatus: Equatable, Sendable {
    case disabled
    case statusUnavailable
    case idle
    case syncing
    case failed(String)
}

protocol ICloudSyncStatusService {
    func currentStatus() throws -> ICloudSyncStatus
}

struct DefaultICloudSyncStatusService: ICloudSyncStatusService {
    let appSettingsService: any AppSettingsService

    func currentStatus() throws -> ICloudSyncStatus {
        let settings = try appSettingsService.fetchSettings()

        guard settings.useiCloudSync else {
            return .disabled
        }

        return .statusUnavailable
    }
}
