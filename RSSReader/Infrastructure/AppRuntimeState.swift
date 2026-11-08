import Foundation

/// App-facing snapshots only; services retain theme persistence and sync execution.
struct AppRuntimeState {
    private(set) var interfaceThemeMode: InterfaceThemeMode = .automaticLightDark
    private(set) var iCloudSyncStatus: ICloudSyncStatus = .disabled

    mutating func applyInterfaceThemeMode(_ mode: InterfaceThemeMode) { interfaceThemeMode = mode }
    mutating func applyICloudSyncStatus(_ status: ICloudSyncStatus) { iCloudSyncStatus = status }
}
