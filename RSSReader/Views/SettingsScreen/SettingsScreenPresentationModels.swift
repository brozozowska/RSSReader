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
        self.interfaceThemeMode = interfaceThemeMode
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
        iCloudSyncStatus: ICloudSyncStatus = .disabled
    ) -> SettingsScreenInput {
        SettingsScreenInput(
            defaultReaderMode: snapshot.defaultReaderMode,
            markAsReadOnOpen: snapshot.markAsReadOnOpen,
            articleBodyLinkOpeningPolicy: snapshot.articleBodyLinkOpeningPolicy,
            articleSourceLinkOpeningPolicy: snapshot.articleSourceLinkOpeningPolicy,
            articleListSortOrder: ArticleListSortOrder(sortMode: snapshot.sortMode),
            askBeforeMarkingAllAsRead: snapshot.askBeforeMarkingAllAsRead,
            refreshIntervalPreference: snapshot.refreshIntervalPreference,
            useiCloudSync: snapshot.useiCloudSync,
            iCloudSyncStatus: iCloudSyncStatus,
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
                        subtitle: iCloudSyncPreferenceSubtitle(input.useiCloudSync),
                        isOn: input.useiCloudSync
                    )
                ),
                .statusRow(
                    SettingsStatusRowItemPresentation(
                        id: .iCloudSyncStatus,
                        title: "Current Status",
                        subtitle: iCloudSyncStatusSubtitle(input.iCloudSyncStatus),
                        valueTitle: iCloudSyncStatusTitle(input.iCloudSyncStatus)
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

    private static func iCloudSyncPreferenceSubtitle(_ isEnabled: Bool) -> String {
        if isEnabled {
            return "Applies on next launch. The app will rebuild its sync container and try to use iCloud for supported data."
        }

        return "Applies on next launch. Supported sync data will stay only on this device until iCloud sync is enabled again."
    }

    private static func iCloudSyncStatusTitle(_ status: ICloudSyncStatus) -> String {
        switch status {
        case .disabled:
            "Off"
        case .statusUnavailable:
            "Status Unavailable"
        case .idle:
            "Ready"
        case .syncing:
            "Syncing"
        case .failed:
            "Error"
        }
    }

    private static func iCloudSyncStatusSubtitle(_ status: ICloudSyncStatus) -> String {
        switch status {
        case .disabled:
            "The current app session is running without iCloud sync."
        case .statusUnavailable:
            "This session is configured for sync, but CloudKit runtime wiring and account status are not implemented yet."
        case .idle:
            "iCloud sync is available and waiting for the next sync event."
        case .syncing:
            "Changes are currently syncing with iCloud."
        case .failed(let message):
            message
        }
    }

    private static func syncSectionFooter(
        input: SettingsScreenInput,
        syncScope: CloudKitSyncScope,
        readingScenario: CrossDeviceReadingScenario
    ) -> String {
        let scopeFooter = syncScope.settingsSectionFooter(readingScenario: readingScenario)
        let relaunchFooter = "Changing the sync preference applies on the next app launch because the model container must be rebuilt for the selected sync policy."

        return "\(scopeFooter) \(relaunchFooter)"
    }
}
