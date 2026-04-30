import Foundation

enum ICloudSyncStatus: Equatable, Sendable {
    case disabled
    case statusUnavailable
    case idle
    case syncing
    case failed(String)
}
