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
    case articleSortMode
    case askBeforeMarkingAllAsRead
    case refreshInterval
    case iCloudSyncStatus
    case linkOpening
    case appearance

    var id: String { rawValue }
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
    case navigationLink(SettingsNavigationLinkItemPresentation)
    case statusRow(SettingsStatusRowItemPresentation)

    var id: SettingsScreenItemID {
        switch self {
        case .toggle(let item):
            item.id
        case .picker(let item):
            item.id
        case .navigationLink(let item):
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

struct SettingsNavigationLinkItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let valueTitle: String?
    let isEnabled: Bool
}

struct SettingsStatusRowItemPresentation: Equatable, Sendable {
    let id: SettingsScreenItemID
    let title: String
    let subtitle: String?
    let valueTitle: String
}

enum SettingsScreenPresentationBuilder {
    static func buildSections(from snapshot: AppSettingsSnapshot) -> [SettingsScreenSectionPresentation] {
        [
            readingSection(from: snapshot),
            articleListSection(from: snapshot),
            refreshSection(from: snapshot),
            syncSection(from: snapshot),
            advancedSection()
        ]
    }

    private static func readingSection(from snapshot: AppSettingsSnapshot) -> SettingsScreenSectionPresentation {
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
                        selectedValueTitle: readerModeTitle(snapshot.defaultReaderMode),
                        options: ReaderMode.allCases.map { mode in
                            SettingsPickerOptionPresentation(
                                id: mode.rawValue,
                                title: readerModeTitle(mode),
                                isSelected: snapshot.defaultReaderMode == mode
                            )
                        }
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .markAsReadOnOpen,
                        title: "Mark Read on Open",
                        subtitle: "Automatically mark an article as read when it is opened.",
                        isOn: snapshot.markAsReadOnOpen
                    )
                )
            ]
        )
    }

    private static func articleListSection(from snapshot: AppSettingsSnapshot) -> SettingsScreenSectionPresentation {
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
                        selectedValueTitle: articleListSortOrderTitle(
                            ArticleListSortOrder(sortMode: snapshot.sortMode)
                        ),
                        options: ArticleListSortOrder.allCases.map { order in
                            SettingsPickerOptionPresentation(
                                id: order.rawValue,
                                title: articleListSortOrderTitle(order),
                                isSelected: ArticleListSortOrder(sortMode: snapshot.sortMode) == order
                            )
                        }
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .askBeforeMarkingAllAsRead,
                        title: "Ask Before Marking All Read",
                        subtitle: "Show a confirmation before marking all visible articles as read.",
                        isOn: snapshot.askBeforeMarkingAllAsRead
                    )
                )
            ]
        )
    }

    private static func refreshSection(from snapshot: AppSettingsSnapshot) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .refresh,
            title: "Refresh",
            footer: "Refresh preferences are represented as picker options even before the runtime orchestration is fully implemented.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .refreshInterval,
                        title: "Background Refresh",
                        subtitle: "Choose how often feeds should refresh when background refresh is available.",
                        selectedValueTitle: refreshPreferenceTitle(snapshot.refreshIntervalPreference),
                        options: RefreshPreference.allCases.map { preference in
                            SettingsPickerOptionPresentation(
                                id: preference.rawValue,
                                title: refreshPreferenceTitle(preference),
                                isSelected: snapshot.refreshIntervalPreference == preference
                            )
                        }
                    )
                )
            ]
        )
    }

    private static func syncSection(from snapshot: AppSettingsSnapshot) -> SettingsScreenSectionPresentation {
        let syncValueTitle = snapshot.useiCloudSync ? "Enabled" : "Off"
        let syncSubtitle = snapshot.useiCloudSync
        ? "Sync is enabled in settings, but CloudKit status is not implemented yet."
        : "Sync is currently turned off."

        return SettingsScreenSectionPresentation(
            id: .sync,
            title: "Sync",
            footer: "Status rows let the screen show runtime or account state without pretending that every setting is editable inline.",
            items: [
                .statusRow(
                    SettingsStatusRowItemPresentation(
                        id: .iCloudSyncStatus,
                        title: "iCloud Sync",
                        subtitle: syncSubtitle,
                        valueTitle: syncValueTitle
                    )
                )
            ]
        )
    }

    private static func advancedSection() -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .advanced,
            title: "Advanced",
            footer: "Navigation link rows reserve space for multi-step settings flows that will be implemented later.",
            items: [
                .navigationLink(
                    SettingsNavigationLinkItemPresentation(
                        id: .linkOpening,
                        title: "Open Links",
                        subtitle: "Link opening policy will be configurable in a dedicated flow.",
                        valueTitle: "Coming Soon",
                        isEnabled: false
                    )
                ),
                .navigationLink(
                    SettingsNavigationLinkItemPresentation(
                        id: .appearance,
                        title: "Appearance",
                        subtitle: "Theme and display preferences will be configured in a dedicated flow.",
                        valueTitle: "Coming Soon",
                        isEnabled: false
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
}
