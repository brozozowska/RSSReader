import Foundation

enum SettingsScreenSectionID: String, Hashable, Identifiable, Sendable {
    case reading
    case articleList
    case refresh
    case sync
    case advanced

    var id: String { rawValue }
}

enum SettingsScreenItemID: String, Hashable, Identifiable, Sendable {
    case defaultReaderMode
    case markAsReadOnOpen
    case articleSourceLinkOpeningPolicy
    case articleSortMode
    case askBeforeMarkingAllAsRead
    case refreshInterval
    case useICloudSync
    case iCloudSyncStatus
    case articleBodyLinkOpeningPolicy
    case appearance

    var id: String { rawValue }
}

struct SettingsScreenInput: Equatable, Sendable {
    var defaultReaderMode: ReaderMode
    var markAsReadOnOpen: Bool
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy
    var articleListSortOrder: ArticleListSortOrder
    var askBeforeMarkingAllAsRead: Bool
    var refreshIntervalPreference: RefreshPreference
    var useiCloudSync: Bool
    var iCloudSyncStatus: ICloudSyncStatus
    var syncStatusPresentation: SettingsSyncStatusPresentation
    var isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool
    var interfaceThemeMode: InterfaceThemeMode

    init(
        defaultReaderMode: ReaderMode = .embedded,
        markAsReadOnOpen: Bool = true,
        articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy = .inAppBrowser,
        articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy = .inAppBrowser,
        articleListSortOrder: ArticleListSortOrder = .newestFirst,
        askBeforeMarkingAllAsRead: Bool = true,
        refreshIntervalPreference: RefreshPreference = .manual,
        useiCloudSync: Bool = false,
        iCloudSyncStatus: ICloudSyncStatus = .disabled,
        syncStatusPresentation: SettingsSyncStatusPresentation = .disabled,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool = false,
        interfaceThemeMode: InterfaceThemeMode = .automaticLightDark
    ) {
        self.defaultReaderMode = defaultReaderMode
        self.markAsReadOnOpen = markAsReadOnOpen
        self.articleBodyLinkOpeningPolicy = articleBodyLinkOpeningPolicy
        self.articleSourceLinkOpeningPolicy = articleSourceLinkOpeningPolicy
        self.articleListSortOrder = articleListSortOrder
        self.askBeforeMarkingAllAsRead = askBeforeMarkingAllAsRead
        self.refreshIntervalPreference = refreshIntervalPreference
        self.useiCloudSync = useiCloudSync
        self.iCloudSyncStatus = iCloudSyncStatus
        self.syncStatusPresentation = syncStatusPresentation
        self.isUsingLocalOnlySyncFallbackForCurrentLaunch = isUsingLocalOnlySyncFallbackForCurrentLaunch
        self.interfaceThemeMode = interfaceThemeMode
    }
}

enum SettingsSyncStatusPresentation: Equatable, Sendable {
    case disabled
    case statusUnavailable
    case checkingAccount
    case ready
    case syncing
    case preparing
    case importing
    case uploading
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case failed(String)

    init(iCloudSyncStatus: ICloudSyncStatus) {
        switch iCloudSyncStatus {
        case .disabled:
            self = .disabled
        case .statusUnavailable:
            self = .statusUnavailable
        case .idle:
            self = .ready
        case .syncing:
            self = .syncing
        case .failed(let message):
            self = .failed(message)
        }
    }

    init(runtimeState: SyncRuntimeState) {
        switch runtimeState.phase {
        case .disabled:
            self = .disabled
        case .statusUnavailable:
            self = .checkingAccount
        case .idle:
            self = .ready
        case .accountProblem(let availability):
            self.init(accountAvailability: availability)
        case .syncing(let activity):
            switch activity {
            case .setup:
                self = .preparing
            case .import:
                self = .importing
            case .export:
                self = .uploading
            }
        case .failed(let failure):
            self = .failed(failure.resolvedMessage)
        }
    }

    init(accountAvailability: ICloudAccountAvailability?) {
        switch accountAvailability {
        case .available:
            self = .ready
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        case .couldNotDetermine, nil:
            self = .couldNotDetermine
        }
    }

    var iCloudSyncStatus: ICloudSyncStatus {
        switch self {
        case .disabled:
            return .disabled
        case .statusUnavailable,
                .checkingAccount,
                .noAccount,
                .restricted,
                .temporarilyUnavailable,
                .couldNotDetermine:
            return .statusUnavailable
        case .ready:
            return .idle
        case .syncing, .preparing, .importing, .uploading:
            return .syncing
        case .failed(let message):
            return .failed(message)
        }
    }
}

struct SettingsScreenSectionPresentation: Identifiable, Equatable, Sendable {
    let id: SettingsScreenSectionID
    let title: String
    let footer: String?
    let items: [SettingsScreenItemPresentation]
}

struct SettingsScreenViewState: Equatable, Sendable {
    let sections: [SettingsScreenSectionPresentation]
    let primaryLoadingState: SettingsScreenPrimaryLoadingState?
    let placeholder: SettingsScreenPlaceholderState?
    let presentedPicker: SettingsPickerItemPresentation?
}

struct SettingsScreenPrimaryLoadingState: Equatable, Sendable {
    let title: String
}

struct SettingsScreenPlaceholderState: Equatable, Sendable {
    let title: String
    let systemImage: String
    let description: String?
    let actionTitle: String?
}

enum SettingsScreenItemPresentation: Identifiable, Equatable, Sendable {
    case toggle(SettingsToggleItemPresentation)
    case picker(SettingsPickerItemPresentation)
    case statusRow(SettingsStatusRowItemPresentation)

    var id: SettingsScreenItemID {
        switch self {
        case .toggle(let item):
            item.id
        case .picker(let item):
            item.id
        case .statusRow(let item):
            item.id
        }
    }
}

struct SettingsToggleItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let isOn: Bool
}

struct SettingsPickerItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let selectedValueTitle: String
    let options: [SettingsPickerOptionPresentation]
}

struct SettingsPickerOptionPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let isSelected: Bool
}

struct SettingsStatusRowItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let valueTitle: String
}

enum SettingsScreenInputBuilder {
    static func build(
        from snapshot: AppSettingsSnapshot,
        iCloudSyncStatus: ICloudSyncStatus = .disabled,
        syncStatusPresentation: SettingsSyncStatusPresentation? = nil,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool = false
    ) -> SettingsScreenInput {
        let resolvedSyncStatusPresentation = syncStatusPresentation
            ?? SettingsSyncStatusPresentation(iCloudSyncStatus: iCloudSyncStatus)

        return SettingsScreenInput(
            defaultReaderMode: snapshot.defaultReaderMode,
            markAsReadOnOpen: snapshot.markAsReadOnOpen,
            articleBodyLinkOpeningPolicy: snapshot.articleBodyLinkOpeningPolicy,
            articleSourceLinkOpeningPolicy: snapshot.articleSourceLinkOpeningPolicy,
            articleListSortOrder: ArticleListSortOrder(sortMode: snapshot.sortMode),
            askBeforeMarkingAllAsRead: snapshot.askBeforeMarkingAllAsRead,
            refreshIntervalPreference: snapshot.refreshIntervalPreference,
            useiCloudSync: snapshot.useiCloudSync,
            iCloudSyncStatus: resolvedSyncStatusPresentation.iCloudSyncStatus,
            syncStatusPresentation: resolvedSyncStatusPresentation,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: isUsingLocalOnlySyncFallbackForCurrentLaunch,
            interfaceThemeMode: snapshot.interfaceThemeMode
        )
    }
}

enum SettingsScreenPresentationBuilder {
    static func buildSections(from input: SettingsScreenInput) -> [SettingsScreenSectionPresentation] {
        [
            readingSection(from: input),
            articleListSection(from: input),
            refreshSection(from: input),
            syncSection(from: input),
            advancedSection(from: input)
        ]
    }

    private static func readingSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .reading,
            title: "Reading",
            footer: "These preferences control how an article opens and how quickly it leaves the unread state.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .defaultReaderMode,
                        title: "Default Reader",
                        subtitle: "Choose how articles open by default.",
                        selectedValueTitle: readerModeTitle(input.defaultReaderMode),
                        options: ReaderMode.allCases.map { mode in
                            SettingsPickerOptionPresentation(
                                id: mode.rawValue,
                                title: readerModeTitle(mode),
                                isSelected: input.defaultReaderMode == mode
                            )
                        }
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .markAsReadOnOpen,
                        title: "Mark Read on Open",
                        subtitle: "Automatically mark an article as read when it is opened.",
                        isOn: input.markAsReadOnOpen
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleBodyLinkOpeningPolicy,
                        title: "Article Links",
                        subtitle: "Choose how links inside article text should open.",
                        selectedValueTitle: articleBodyLinkOpeningPolicyTitle(input.articleBodyLinkOpeningPolicy),
                        options: ArticleBodyLinkOpeningPolicy.allCases.map { policy in
                            SettingsPickerOptionPresentation(
                                id: policy.rawValue,
                                title: articleBodyLinkOpeningPolicyTitle(policy),
                                isSelected: input.articleBodyLinkOpeningPolicy == policy
                            )
                        }
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleSourceLinkOpeningPolicy,
                        title: "Source Article",
                        subtitle: "Choose how the toolbar action opens the original article URL.",
                        selectedValueTitle: articleSourceLinkOpeningPolicyTitle(input.articleSourceLinkOpeningPolicy),
                        options: ArticleSourceLinkOpeningPolicy.allCases.map { policy in
                            SettingsPickerOptionPresentation(
                                id: policy.rawValue,
                                title: articleSourceLinkOpeningPolicyTitle(policy),
                                isSelected: input.articleSourceLinkOpeningPolicy == policy
                            )
                        }
                    )
                )
            ]
        )
    }

    private static func articleListSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .articleList,
            title: "Article List",
            footer: "Ordering and bulk mark-as-read confirmation are configurable here.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleSortMode,
                        title: "Sort Articles",
                        subtitle: "Choose how unread and article lists are ordered.",
                        selectedValueTitle: articleListSortOrderTitle(input.articleListSortOrder),
                        options: ArticleListSortOrder.allCases.map { order in
                            SettingsPickerOptionPresentation(
                                id: order.rawValue,
                                title: articleListSortOrderTitle(order),
                                isSelected: input.articleListSortOrder == order
                            )
                        }
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .askBeforeMarkingAllAsRead,
                        title: "Ask Before Marking All Read",
                        subtitle: "Show a confirmation before marking all visible articles as read.",
                        isOn: input.askBeforeMarkingAllAsRead
                    )
                )
            ]
        )
    }

    private static func refreshSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .refresh,
            title: "Refresh",
            footer: "Manual disables scheduled background refresh, while automatic intervals are now interpreted through BackgroundRefreshService.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .refreshInterval,
                        title: "Background Refresh",
                        subtitle: "Choose how often feeds should refresh when background refresh is available.",
                        selectedValueTitle: refreshPreferenceTitle(input.refreshIntervalPreference),
                        options: RefreshPreference.allCases.map { preference in
                            SettingsPickerOptionPresentation(
                                id: preference.rawValue,
                                title: refreshPreferenceTitle(preference),
                                isSelected: input.refreshIntervalPreference == preference
                            )
                        }
                    )
                )
            ]
        )
    }

    private static func syncSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        let readingScenario = CrossDeviceReadingScenario.current
        let syncScope = CloudKitSyncScope.current

        return SettingsScreenSectionPresentation(
            id: .sync,
            title: "Sync",
            footer: syncSectionFooter(input: input, syncScope: syncScope, readingScenario: readingScenario),
            items: [
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

    private static func advancedSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .advanced,
            title: "Advanced",
            footer: "Appearance is applied at the app level so the selected interface mode immediately affects the shell and screen surfaces.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .appearance,
                        title: "Appearance",
                        subtitle: "Choose between automatic light/dark handling, automatic light/black, or fixed appearance modes.",
                        selectedValueTitle: interfaceThemeModeTitle(input.interfaceThemeMode),
                        options: InterfaceThemeMode.allCases.map { mode in
                            SettingsPickerOptionPresentation(
                                id: mode.rawValue,
                                title: interfaceThemeModeTitle(mode),
                                isSelected: input.interfaceThemeMode == mode
                            )
                        }
                    )
                )
            ]
        )
    }

    private static func readerModeTitle(_ mode: ReaderMode) -> String {
        switch mode {
        case .embedded:
            "Embedded Reader"
        case .reader:
            "Reader Mode"
        case .browser:
            "In-App Browser"
        }
    }

    private static func articleListSortOrderTitle(_ order: ArticleListSortOrder) -> String {
        switch order {
        case .newestFirst:
            "Newest First"
        case .oldestFirst:
            "Oldest First"
        }
    }

    private static func refreshPreferenceTitle(_ preference: RefreshPreference) -> String {
        switch preference {
        case .manual:
            "Manual"
        case .every15Minutes:
            "Every 15 Minutes"
        case .hourly:
            "Hourly"
        case .every6Hours:
            "Every 6 Hours"
        case .daily:
            "Daily"
        }
    }

    private static func articleBodyLinkOpeningPolicyTitle(_ policy: ArticleBodyLinkOpeningPolicy) -> String {
        switch policy {
        case .inAppBrowser:
            "In-App Browser"
        case .externalBrowser:
            "External Browser"
        }
    }

    private static func articleSourceLinkOpeningPolicyTitle(_ policy: ArticleSourceLinkOpeningPolicy) -> String {
        switch policy {
        case .inAppBrowser:
            "In-App Browser"
        case .externalBrowser:
            "External Browser"
        }
    }

    private static func interfaceThemeModeTitle(_ mode: InterfaceThemeMode) -> String {
        switch mode {
        case .automaticLightDark:
            "Automatic Light/Dark"
        case .automaticLightBlack:
            "Automatic Light/Black"
        case .light:
            "Light"
        case .dark:
            "Dark"
        case .black:
            "Black"
        }
    }

    private static func iCloudSyncPreferenceSubtitle(
        _ isEnabled: Bool,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool,
        syncStatusPresentation: SettingsSyncStatusPresentation
    ) -> String {
        if isEnabled, isUsingLocalOnlySyncFallbackForCurrentLaunch {
            return "Saved for the next launch. This session is still using local-only data because \(bootstrapFallbackReason(syncStatusPresentation))."
        }

        if isEnabled {
            return "Applies on next launch. The app will rebuild its sync container and try to use iCloud for supported data."
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
                return "Sync is enabled as a saved preference, but this app launch is still using the local-only store because the current device is not signed in to iCloud. Relaunch after signing in so the app can rebuild its sync container."
            case .restricted:
                return "Sync is enabled as a saved preference, but this app launch is still using the local-only store because iCloud access is currently restricted on this device. Relaunch after the restriction is removed so the app can rebuild its sync container."
            case .temporarilyUnavailable:
                return "Sync is enabled as a saved preference, but this app launch is still using the local-only store because the current iCloud account is temporarily unavailable. Relaunch after iCloud becomes available so the app can rebuild its sync container."
            case .couldNotDetermine, .statusUnavailable, .checkingAccount:
                return "Sync is enabled as a saved preference, but this app launch is still using the local-only store because the app could not confirm a usable iCloud account/runtime path during bootstrap. Relaunch after iCloud becomes available so the app can rebuild its sync container."
            case .disabled, .ready, .syncing, .preparing, .importing, .uploading, .failed:
                break
            }
        }

        switch status {
        case .disabled:
            return "The current app session is running without iCloud sync."
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
            return "Sign in to iCloud with the Apple ID used on this device to enable sync. RSSReader does not require a separate account."
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

    private static func syncSectionFooter(
        input: SettingsScreenInput,
        syncScope: CloudKitSyncScope,
        readingScenario: CrossDeviceReadingScenario
    ) -> String {
        let scopeFooter = syncScope.settingsSectionFooter(readingScenario: readingScenario)
        let accountFooter = "RSSReader uses the Apple ID already signed in to this device for iCloud sync and does not require a separate app account."
        let relaunchFooter = "Changing the sync preference applies on the next app launch because the model container must be rebuilt for the selected sync policy."
        let fallbackFooter: String
        if input.isUsingLocalOnlySyncFallbackForCurrentLaunch {
            fallbackFooter = "The saved sync preference is currently waiting for a later launch that can rebuild the model container with a valid iCloud account/runtime path."
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
            "the app could not confirm a usable iCloud account/runtime path during bootstrap"
        case .disabled, .ready, .syncing, .preparing, .importing, .uploading, .failed:
            "the app is waiting for a later launch to rebuild its sync container"
        }
    }
}
