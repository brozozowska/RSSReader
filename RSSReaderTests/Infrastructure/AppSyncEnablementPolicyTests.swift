import Testing
@testable import RSSReader

@Suite("Infrastructure / Sync Enablement Policy")
@MainActor
struct AppSyncEnablementPolicyTests {
    @Test
    func currentPolicyUsesPersistedAppSettingsFlagAsSourceOfTruth() {
        let policy = AppSyncEnablementPolicy.current

        #expect(matchesSourceOfTruth(policy.sourceOfTruth, .bootstrapPreferenceAndAppSettings))
        #expect(matchesFirstLaunchBehavior(policy.firstLaunchBehavior, .defaultToDisabled))
        #expect(matchesDisabledBehavior(policy.disabledBehavior, .keepSyncScopedModelsInLocalStore))
        #expect(matchesSettingsChangeBehavior(policy.settingsChangeBehavior, .requiresAppRelaunch))
    }

    @Test
    func firstLaunchDefaultsToDisabledWhenNoSettingsSnapshotExistsYet() {
        let policy = AppSyncEnablementPolicy.current

        #expect(matchesBootPreference(policy.bootPreference(from: nil), .disabled))
        #expect(matchesCloudKitPolicy(policy.syncBackedCloudKitPolicy(for: nil), .disabled))
    }

    @Test
    func bootPreferenceFollowsPersistedUseICloudSyncFlag() {
        let policy = AppSyncEnablementPolicy.current

        #expect(matchesBootPreference(policy.bootPreference(from: AppSettingsSnapshot(useiCloudSync: false)), .disabled))
        #expect(matchesBootPreference(policy.bootPreference(from: AppSettingsSnapshot(useiCloudSync: true)), .enabled))
    }

    @Test
    func localBootstrapPreferenceOverridesPersistedAppSettingsDuringContainerBootstrap() {
        let policy = AppSyncEnablementPolicy.current

        #expect(
            matchesBootPreference(
                policy.bootPreference(
                    from: AppSettingsSnapshot(useiCloudSync: false),
                    localBootstrapPreference: .enabled
                ),
                .enabled
            )
        )
        #expect(
            matchesBootPreference(
                policy.bootPreference(
                    from: AppSettingsSnapshot(useiCloudSync: true),
                    localBootstrapPreference: .disabled
                ),
                .disabled
            )
        )
    }

    @Test
    func disabledPreferenceKeepsSyncBackedModelsLocalOnly() {
        let policy = AppSyncEnablementPolicy.current

        #expect(matchesCloudKitPolicy(
            policy.syncBackedCloudKitPolicy(for: AppSettingsSnapshot(useiCloudSync: false)),
            .disabled
        ))
    }

    @Test
    func enabledPreferenceUsesConfiguredPrivateCloudKitContainer() {
        let policy = AppSyncEnablementPolicy.current

        #expect(matchesCloudKitPolicy(
            policy.syncBackedCloudKitPolicy(for: AppSettingsSnapshot(useiCloudSync: true)),
            .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
        ))
    }

    @Test
    func changingSyncPreferenceRequiresContainerRebuildOnNextLaunch() {
        let policy = AppSyncEnablementPolicy.current

        #expect(policy.requiresContainerRebuildAfterSettingsChange)
    }

    private func matchesSourceOfTruth(
        _ lhs: AppSyncEnablementSourceOfTruth,
        _ rhs: AppSyncEnablementSourceOfTruth
    ) -> Bool {
        switch (lhs, rhs) {
        case (.bootstrapPreferenceAndAppSettings, .bootstrapPreferenceAndAppSettings):
            true
        }
    }

    private func matchesFirstLaunchBehavior(
        _ lhs: AppSyncFirstLaunchBehavior,
        _ rhs: AppSyncFirstLaunchBehavior
    ) -> Bool {
        switch (lhs, rhs) {
        case (.defaultToDisabled, .defaultToDisabled):
            true
        }
    }

    private func matchesDisabledBehavior(
        _ lhs: AppSyncDisabledBehavior,
        _ rhs: AppSyncDisabledBehavior
    ) -> Bool {
        switch (lhs, rhs) {
        case (.keepSyncScopedModelsInLocalStore, .keepSyncScopedModelsInLocalStore):
            true
        }
    }

    private func matchesSettingsChangeBehavior(
        _ lhs: AppSyncSettingsChangeBehavior,
        _ rhs: AppSyncSettingsChangeBehavior
    ) -> Bool {
        switch (lhs, rhs) {
        case (.requiresAppRelaunch, .requiresAppRelaunch):
            true
        }
    }

    private func matchesBootPreference(
        _ lhs: AppSyncBootPreference,
        _ rhs: AppSyncBootPreference
    ) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled), (.enabled, .enabled):
            true
        default:
            false
        }
    }

    private func matchesCloudKitPolicy(
        _ lhs: AppPersistenceCloudKitPolicy,
        _ rhs: AppPersistenceCloudKitPolicy
    ) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled), (.automatic, .automatic):
            true
        case (.privateContainer(let lhsIdentifier), .privateContainer(let rhsIdentifier)):
            lhsIdentifier == rhsIdentifier
        default:
            false
        }
    }
}
