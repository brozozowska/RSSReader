import Foundation

enum AppSyncEnablementSourceOfTruth: String, Equatable, Sendable {
    case appSettingsUseICloudSync
}

enum AppSyncBootPreference: String, Equatable, Sendable {
    case disabled
    case enabled

    var usesCloudKit: Bool {
        self == .enabled
    }
}

enum AppSyncFirstLaunchBehavior: Equatable, Sendable {
    case defaultToDisabled
}

enum AppSyncDisabledBehavior: Equatable, Sendable {
    case keepSyncScopedModelsInLocalStore
}

enum AppSyncSettingsChangeBehavior: Equatable, Sendable {
    case requiresAppRelaunch
}

/// App-level policy for choosing whether sync-backed models should start with CloudKit enabled.
/// The next roadmap step wires this policy into container construction.
struct AppSyncEnablementPolicy: Equatable, Sendable {
    let sourceOfTruth: AppSyncEnablementSourceOfTruth
    let firstLaunchBehavior: AppSyncFirstLaunchBehavior
    let disabledBehavior: AppSyncDisabledBehavior
    let settingsChangeBehavior: AppSyncSettingsChangeBehavior

    static let current = AppSyncEnablementPolicy(
        sourceOfTruth: .appSettingsUseICloudSync,
        firstLaunchBehavior: .defaultToDisabled,
        disabledBehavior: .keepSyncScopedModelsInLocalStore,
        settingsChangeBehavior: .requiresAppRelaunch
    )

    func bootPreference(from settingsSnapshot: AppSettingsSnapshot?) -> AppSyncBootPreference {
        guard let settingsSnapshot else {
            return .disabled
        }

        return settingsSnapshot.useiCloudSync ? .enabled : .disabled
    }

    func syncBackedCloudKitPolicy(
        for settingsSnapshot: AppSettingsSnapshot?,
        enabledPolicy: AppPersistenceCloudKitPolicy = CloudKitContainerConfiguration.syncBackedDatabasePolicy
    ) -> AppPersistenceCloudKitPolicy {
        bootPreference(from: settingsSnapshot).usesCloudKit ? enabledPolicy : .disabled
    }

    /// `ModelContainer` captures CloudKit configuration at creation time, so changing
    /// the persisted preference later requires a fresh app launch that rebuilds the container.
    var requiresContainerRebuildAfterSettingsChange: Bool {
        settingsChangeBehavior == .requiresAppRelaunch
    }
}
