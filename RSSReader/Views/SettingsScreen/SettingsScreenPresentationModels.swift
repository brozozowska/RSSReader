import Foundation

enum SettingsScreenSectionID: String, Hashable, Identifiable, Sendable {
    case appearance
    case reading
    case articleList
    case updatesAndSync
    case storage

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
    case readerAdjacentNavigationControlsMode
    case appearance
    case clearArticleImageCache

    var id: String { rawValue }
}

struct SettingsScreenInput: Equatable, Sendable {
    var defaultReaderMode: ReaderMode
    var markAsReadOnOpen: Bool
    var articleBodyLinkOpeningPolicy: ArticleBodyLinkOpeningPolicy
    var articleSourceLinkOpeningPolicy: ArticleSourceLinkOpeningPolicy
    var readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode
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
        readerAdjacentNavigationControlsMode: ReaderAdjacentNavigationControlsMode = .swipesAndToolbarControls,
        articleListSortOrder: ArticleListSortOrder = .oldestFirst,
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
        self.readerAdjacentNavigationControlsMode = readerAdjacentNavigationControlsMode
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
    let canApplyChanges: Bool
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
    case button(SettingsButtonItemPresentation)

    var id: SettingsScreenItemID {
        switch self {
        case .toggle(let item):
            item.id
        case .picker(let item):
            item.id
        case .statusRow(let item):
            item.id
        case .button(let item):
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

struct SettingsButtonItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let systemImage: String
    let role: SettingsButtonItemRole
    let isEnabled: Bool
}

enum SettingsButtonItemRole: Equatable, Sendable {
    case normal
    case destructive
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
            readerAdjacentNavigationControlsMode: snapshot.readerAdjacentNavigationControlsMode,
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
    static func buildSections(
        from input: SettingsScreenInput,
        hasArticleImageCache: Bool = false
    ) -> [SettingsScreenSectionPresentation] {
        [
            appearanceSection(from: input),
            readingSection(from: input),
            articleListSection(from: input),
            updatesAndSyncSection(from: input),
            storageSection(hasArticleImageCache: hasArticleImageCache)
        ]
    }

    private static func appearanceSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .appearance,
            title: "Appearance",
            footer: "Choose how the app renders its interface. The selected mode applies immediately.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .appearance,
                        title: "Theme",
                        subtitle: nil,
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

    private static func readingSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .reading,
            title: "Reading",
            footer: "Choose where articles open, how adjacent article controls appear, where links inside articles open, and whether opening an article should immediately mark it as read.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .defaultReaderMode,
                        title: "Open Articles",
                        subtitle: nil,
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
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleBodyLinkOpeningPolicy,
                        title: "Links in Articles",
                        subtitle: nil,
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
                        title: "Original Article Link",
                        subtitle: nil,
                        selectedValueTitle: articleSourceLinkOpeningPolicyTitle(input.articleSourceLinkOpeningPolicy),
                        options: ArticleSourceLinkOpeningPolicy.allCases.map { policy in
                            SettingsPickerOptionPresentation(
                                id: policy.rawValue,
                                title: articleSourceLinkOpeningPolicyTitle(policy),
                                isSelected: input.articleSourceLinkOpeningPolicy == policy
                            )
                        }
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .readerAdjacentNavigationControlsMode,
                        title: "Adjacent Navigation",
                        subtitle: nil,
                        selectedValueTitle: readerAdjacentNavigationControlsModeTitle(input.readerAdjacentNavigationControlsMode),
                        options: ReaderAdjacentNavigationControlsMode.allCases.map { mode in
                            SettingsPickerOptionPresentation(
                                id: mode.rawValue,
                                title: readerAdjacentNavigationControlsModeTitle(mode),
                                isSelected: input.readerAdjacentNavigationControlsMode == mode
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
                )
            ]
        )
    }

    private static func articleListSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .articleList,
            title: "Article List",
            footer: "Choose how article lists are ordered and whether bulk mark-as-read actions ask for confirmation.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleSortMode,
                        title: "Sort Articles",
                        subtitle: nil,
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

    private static func updatesAndSyncSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
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
                        selectedValueTitle: refreshPreferenceTitle(input.refreshIntervalPreference),
                        options: RefreshPreference.allCases.map { preference in
                            SettingsPickerOptionPresentation(
                                id: preference.rawValue,
                                title: refreshPreferenceTitle(preference),
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

    private static func storageSection(hasArticleImageCache: Bool) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .storage,
            title: "Storage",
            footer: nil,
            items: [
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearArticleImageCache,
                        title: "Clear Article Image Cache",
                        subtitle: "Remove article images saved on this device.",
                        systemImage: "trash",
                        role: .destructive,
                        isEnabled: hasArticleImageCache
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

    private static func readerAdjacentNavigationControlsModeTitle(_ mode: ReaderAdjacentNavigationControlsMode) -> String {
        switch mode {
        case .swipesOnly:
            "Swipes Only"
        case .swipesAndToolbarControls:
            "Swipes and Buttons"
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
