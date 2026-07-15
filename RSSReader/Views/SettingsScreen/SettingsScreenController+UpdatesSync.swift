import Foundation

@MainActor
extension SettingsScreenController {
    func updateUseICloudSync(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.useiCloudSync != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.useiCloudSync = isOn
        screenState.applyDraftInput(input)
    }

    func updateRefreshIntervalPreference(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPreference = RefreshPreference(rawValue: optionID) else {
            dependencies.logger.error("Skipped refresh interval update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.refreshIntervalPreference != selectedPreference else {
            return
        }

        var input = screenState.settingsInput
        input.refreshIntervalPreference = selectedPreference
        screenState.applyDraftInput(input)
    }

    func resolveSyncStatusPresentation(
        dependencies: AppDependencies,
        appState: AppState?,
        settingsSnapshot: AppSettingsSnapshot
    ) -> SettingsSyncStatusPresentation {
        if let syncCoordinator = dependencies.syncCoordinator,
           syncCoordinator.runtimeState.isSyncEnabled {
            let resolvedStatus = SettingsSyncStatusPresentation(runtimeState: syncCoordinator.runtimeState)
            appState?.applyICloudSyncStatus(resolvedStatus.iCloudSyncStatus)
            return resolvedStatus
        }

        if let syncBootstrapContext = dependencies.syncBootstrapContext,
           syncBootstrapContext.isRunningLocalOnlyFallbackForCurrentLaunch {
            let fallbackStatus = bootstrapFallbackStatusPresentation(for: syncBootstrapContext)
            appState?.applyICloudSyncStatus(fallbackStatus.iCloudSyncStatus)
            return fallbackStatus
        }

        if let appState, appState.iCloudSyncStatus != .disabled {
            return SettingsSyncStatusPresentation(iCloudSyncStatus: appState.iCloudSyncStatus)
        }

        if let appState {
            return SettingsSyncStatusPresentation(iCloudSyncStatus: appState.iCloudSyncStatus)
        }

        if settingsSnapshot.useiCloudSync == false {
            return .disabled
        }

        return .statusUnavailable
    }

    func applySettingsSideEffects(
        previousSnapshot: AppSettingsSnapshot,
        updatedSnapshot: AppSettingsSnapshot,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        if previousSnapshot.useiCloudSync != updatedSnapshot.useiCloudSync {
            dependencies.syncBootstrapPreferenceStore.saveBootPreference(
                updatedSnapshot.useiCloudSync ? .enabled : .disabled
            )
        }

        if previousSnapshot.interfaceThemeMode != updatedSnapshot.interfaceThemeMode {
            appState?.applyInterfaceThemeMode(updatedSnapshot.interfaceThemeMode)
        }

        if previousSnapshot.articleRetentionPolicy != updatedSnapshot.articleRetentionPolicy {
            let cleanupResult = dependencies.appActions.cleanupArticles(
                policy: updatedSnapshot.articleRetentionPolicy,
                now: .now
            )
            if cleanupResult?.deletedCount ?? 0 > 0 {
                appState?.requestSidebarReload()
                appState?.requestArticleListReload()
                dependencies.appActions.scheduleUnreadAppIconBadgeRefresh()
            }
        }

        if previousSnapshot.showUnreadCountBadge != updatedSnapshot.showUnreadCountBadge {
            dependencies.appActions.applyUnreadAppIconBadgePreference(isEnabled: updatedSnapshot.showUnreadCountBadge)
        }

        guard previousSnapshot.refreshIntervalPreference != updatedSnapshot.refreshIntervalPreference else {
            return
        }

        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: updatedSnapshot,
            policy: BackgroundRefreshPolicy(preference: updatedSnapshot.refreshIntervalPreference)
        )

        do {
            try dependencies.replaceBackgroundRefreshSchedule(
                using: configuration,
                now: .now
            )
        } catch {
            let failureReason = BackgroundRefreshScheduleFailureReason.classify(error).rawValue
            dependencies.logger.error(
                "Failed to replace background refresh schedule after applying settings changes: reason=\(failureReason) error=\(error)"
            )
        }
    }

    func applyUpdatedSettingsSnapshot(_ snapshot: AppSettingsSnapshot) {
        screenState.applyLoadedSnapshot(
            snapshot,
            iCloudSyncStatus: screenState.iCloudSyncStatus,
            syncStatusPresentation: screenState.syncStatusPresentation,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: screenState.settingsInput.isUsingLocalOnlySyncFallbackForCurrentLaunch
        )
    }

    func bootstrapFallbackStatusPresentation(
        for syncBootstrapContext: AppSyncBootstrapContext
    ) -> SettingsSyncStatusPresentation {
        SettingsSyncStatusPresentation(accountAvailability: syncBootstrapContext.accountAvailabilityAtBootstrap)
    }
}
