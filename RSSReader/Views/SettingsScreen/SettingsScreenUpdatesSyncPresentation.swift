import Foundation

extension SettingsScreenPresentationBuilder {
    static func updatesAndSyncSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        let readingScenario = CrossDeviceReadingScenario.current
        let syncScope = CloudKitSyncScope.current

        return SettingsScreenSectionPresentation(
            id: .updatesAndSync,
            title: SettingsLocalization.updatesSyncSectionTitle,
            footer: updatesAndSyncSectionFooter(input: input, syncScope: syncScope, readingScenario: readingScenario),
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .refreshInterval,
                        title: SettingsLocalization.backgroundRefreshTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.refreshPreferenceTitle(input.refreshIntervalPreference),
                        options: RefreshPreference.allCases.map { preference in
                            SettingsPickerOptionPresentation(
                                id: preference.rawValue,
                                title: SettingsScreenPresentationFormatter.refreshPreferenceTitle(preference),
                                isSelected: input.refreshIntervalPreference == preference
                            )
                        }
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .useICloudSync,
                        title: SettingsLocalization.enableICloudSyncTitle,
                        subtitle: iCloudSyncPreferenceSubtitle(
                            input.useiCloudSync,
                            isUsingLocalOnlySyncFallbackForCurrentLaunch: input.isUsingLocalOnlySyncFallbackForCurrentLaunch,
                            syncStatusPresentation: input.syncStatusPresentation
                        ),
                        isOn: input.useiCloudSync
                    )
                ),
                .statusRow(
                    SettingsStatusRowItemPresentation(
                        id: .iCloudSyncStatus,
                        title: SettingsLocalization.currentStatusTitle,
                        subtitle: iCloudSyncStatusSubtitle(
                            input.syncStatusPresentation,
                            isUsingLocalOnlySyncFallbackForCurrentLaunch: input.isUsingLocalOnlySyncFallbackForCurrentLaunch
                        ),
                        valueTitle: iCloudSyncStatusTitle(input.syncStatusPresentation)
                    )
                )
            ]
        )
    }

    private static func iCloudSyncPreferenceSubtitle(
        _ isEnabled: Bool,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool,
        syncStatusPresentation: SettingsSyncStatusPresentation
    ) -> String {
        if isEnabled, isUsingLocalOnlySyncFallbackForCurrentLaunch {
            return SettingsLocalization.iCloudSyncPreferenceFallbackSubtitle(
                reason: bootstrapFallbackReason(syncStatusPresentation)
            )
        }

        if isEnabled {
            return SettingsLocalization.iCloudSyncPreferenceEnabledSubtitle
        }

        return SettingsLocalization.iCloudSyncPreferenceDisabledSubtitle
    }

    private static func iCloudSyncStatusTitle(_ status: SettingsSyncStatusPresentation) -> String {
        switch status {
        case .disabled:
            SettingsLocalization.syncStatusOffTitle
        case .statusUnavailable:
            SettingsLocalization.syncStatusUnavailableTitle
        case .checkingAccount:
            SettingsLocalization.syncStatusCheckingTitle
        case .ready:
            SettingsLocalization.syncStatusReadyTitle
        case .syncing:
            SettingsLocalization.syncStatusSyncingTitle
        case .preparing:
            SettingsLocalization.syncStatusPreparingTitle
        case .importing:
            SettingsLocalization.syncStatusImportingTitle
        case .uploading:
            SettingsLocalization.syncStatusUploadingTitle
        case .noAccount:
            SettingsLocalization.syncStatusNoAccountTitle
        case .restricted:
            SettingsLocalization.syncStatusRestrictedTitle
        case .temporarilyUnavailable:
            SettingsLocalization.syncStatusTemporarilyUnavailableTitle
        case .couldNotDetermine:
            SettingsLocalization.syncStatusCouldNotDetermineTitle
        case .failed:
            SettingsLocalization.syncStatusErrorTitle
        }
    }

    private static func iCloudSyncStatusSubtitle(
        _ status: SettingsSyncStatusPresentation,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool
    ) -> String {
        if isUsingLocalOnlySyncFallbackForCurrentLaunch {
            switch status {
            case .noAccount:
                return SettingsLocalization.syncFallbackNoAccountSubtitle
            case .restricted:
                return SettingsLocalization.syncFallbackRestrictedSubtitle
            case .temporarilyUnavailable:
                return SettingsLocalization.syncFallbackTemporarilyUnavailableSubtitle
            case .couldNotDetermine, .statusUnavailable, .checkingAccount:
                return SettingsLocalization.syncFallbackCouldNotDetermineSubtitle
            case .disabled, .ready, .syncing, .preparing, .importing, .uploading, .failed:
                break
            }
        }

        switch status {
        case .disabled:
            return SettingsLocalization.syncDisabledSubtitle
        case .statusUnavailable:
            return SettingsLocalization.syncStatusUnavailableSubtitle
        case .checkingAccount:
            return SettingsLocalization.syncCheckingAccountSubtitle
        case .ready:
            return SettingsLocalization.syncReadySubtitle
        case .syncing:
            return SettingsLocalization.syncSyncingSubtitle
        case .preparing:
            return SettingsLocalization.syncPreparingSubtitle
        case .importing:
            return SettingsLocalization.syncImportingSubtitle
        case .uploading:
            return SettingsLocalization.syncUploadingSubtitle
        case .noAccount:
            return SettingsLocalization.syncNoAccountSubtitle
        case .restricted:
            return SettingsLocalization.syncRestrictedSubtitle
        case .temporarilyUnavailable:
            return SettingsLocalization.syncTemporarilyUnavailableSubtitle
        case .couldNotDetermine:
            return SettingsLocalization.syncCouldNotDetermineSubtitle
        case .failed(let message):
            return message
        }
    }

    private static func updatesAndSyncSectionFooter(
        input: SettingsScreenInput,
        syncScope: CloudKitSyncScope,
        readingScenario: CrossDeviceReadingScenario
    ) -> String {
        let fallbackFooter: String
        if input.isUsingLocalOnlySyncFallbackForCurrentLaunch {
            fallbackFooter = SettingsLocalization.iCloudScopeFallbackFooter
        } else {
            fallbackFooter = ""
        }

        _ = syncScope
        _ = readingScenario

        return "\(SettingsLocalization.iCloudScopeAccountFooter) \(fallbackFooter)"
            .trimmingCharacters(in: .whitespaces)
    }

    private static func bootstrapFallbackReason(_ status: SettingsSyncStatusPresentation) -> String {
        switch status {
        case .noAccount:
            SettingsLocalization.bootstrapFallbackNoAccountReason
        case .restricted:
            SettingsLocalization.bootstrapFallbackRestrictedReason
        case .temporarilyUnavailable:
            SettingsLocalization.bootstrapFallbackTemporarilyUnavailableReason
        case .couldNotDetermine, .statusUnavailable, .checkingAccount:
            SettingsLocalization.bootstrapFallbackCouldNotDetermineReason
        case .disabled, .ready, .syncing, .preparing, .importing, .uploading, .failed:
            SettingsLocalization.bootstrapFallbackUnavailableReason
        }
    }
}
