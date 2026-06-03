import Foundation

extension SettingsScreenPresentationBuilder {
    static func updatesAndSyncSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        let readingScenario = CrossDeviceReadingScenario.current
        let syncScope = CloudKitSyncScope.current

        return SettingsScreenSectionPresentation(
            id: .updatesAndSync,
            title: "Updates & Sync",
            footer: updatesAndSyncSectionFooter(input: input, syncScope: syncScope, readingScenario: readingScenario),
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .refreshInterval,
                        title: "Background Refresh",
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
                        title: "Enable iCloud Sync",
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
                        title: "Current Status",
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
            return "Saved for the next launch. This session keeps using local data because \(bootstrapFallbackReason(syncStatusPresentation))."
        }

        if isEnabled {
            return "Applies on next launch. Supported data will sync through iCloud when available."
        }

        return "Applies on next launch. Supported sync data will stay only on this device until iCloud sync is enabled again."
    }

    private static func iCloudSyncStatusTitle(_ status: SettingsSyncStatusPresentation) -> String {
        switch status {
        case .disabled:
            "Off"
        case .statusUnavailable:
            "Status Unavailable"
        case .checkingAccount:
            "Checking"
        case .ready:
            "Ready"
        case .syncing:
            "Syncing"
        case .preparing:
            "Preparing"
        case .importing:
            "Importing"
        case .uploading:
            "Uploading"
        case .noAccount:
            "Sign In Required"
        case .restricted:
            "Restricted"
        case .temporarilyUnavailable:
            "Temporarily Unavailable"
        case .couldNotDetermine:
            "Account Unavailable"
        case .failed:
            "Error"
        }
    }

    private static func iCloudSyncStatusSubtitle(
        _ status: SettingsSyncStatusPresentation,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool
    ) -> String {
        if isUsingLocalOnlySyncFallbackForCurrentLaunch {
            switch status {
            case .noAccount:
                return "Sync is enabled, but this launch cannot use iCloud because the device is not signed in. Relaunch after signing in."
            case .restricted:
                return "Sync is enabled, but this launch cannot use iCloud because access is restricted on this device. Relaunch after the restriction is removed."
            case .temporarilyUnavailable:
                return "Sync is enabled, but this launch cannot use iCloud because the current account is temporarily unavailable. Relaunch after iCloud becomes available."
            case .couldNotDetermine, .statusUnavailable, .checkingAccount:
                return "Sync is enabled, but this launch could not confirm iCloud availability. Relaunch after iCloud becomes available."
            case .disabled, .ready, .syncing, .preparing, .importing, .uploading, .failed:
                break
            }
        }

        switch status {
        case .disabled:
            return "iCloud sync is off."
        case .statusUnavailable:
            return "The current app session could not read the live iCloud sync status."
        case .checkingAccount:
            return "The app is checking the current iCloud account and CloudKit session status."
        case .ready:
            return "iCloud sync is available for the Apple ID currently signed in on this device."
        case .syncing:
            return "Changes are currently syncing with iCloud."
        case .preparing:
            return "The app is preparing the iCloud sync session for supported data."
        case .importing:
            return "Changes from iCloud are currently being applied on this device."
        case .uploading:
            return "Changes from this device are currently being uploaded to iCloud."
        case .noAccount:
            return "Sign in to iCloud with the Apple ID used on this device to enable sync."
        case .restricted:
            return "This device cannot use iCloud right now because account changes or CloudKit access are restricted."
        case .temporarilyUnavailable:
            return "The current iCloud account is temporarily unavailable. Try again later."
        case .couldNotDetermine:
            return "The app could not determine the current iCloud account status. Check the device Apple ID and iCloud availability, then try again."
        case .failed(let message):
            return message
        }
    }

    private static func updatesAndSyncSectionFooter(
        input: SettingsScreenInput,
        syncScope: CloudKitSyncScope,
        readingScenario: CrossDeviceReadingScenario
    ) -> String {
        let scopeFooter = syncScope.settingsSectionFooter(readingScenario: readingScenario)
        let accountFooter = "iCloud sync uses the Apple ID signed in on this device."
        let relaunchFooter = "Changing the sync preference applies on the next app launch."
        let fallbackFooter: String
        if input.isUsingLocalOnlySyncFallbackForCurrentLaunch {
            fallbackFooter = "Sync will try again on the next launch when iCloud is available."
        } else {
            fallbackFooter = ""
        }

        return "\(scopeFooter) \(accountFooter) \(relaunchFooter) \(fallbackFooter)".trimmingCharacters(in: .whitespaces)
    }

    private static func bootstrapFallbackReason(_ status: SettingsSyncStatusPresentation) -> String {
        switch status {
        case .noAccount:
            "the device is not signed in to iCloud"
        case .restricted:
            "iCloud access is currently restricted on this device"
        case .temporarilyUnavailable:
            "the current iCloud account is temporarily unavailable"
        case .couldNotDetermine, .statusUnavailable, .checkingAccount:
            "iCloud availability could not be confirmed"
        case .disabled, .ready, .syncing, .preparing, .importing, .uploading, .failed:
            "iCloud is not available for this launch"
        }
    }
}
