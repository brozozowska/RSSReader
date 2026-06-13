import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Presentation / Contract")
@MainActor
struct SettingsScreenPresentationContractTests {
    @Test
    func settingsScreenPresentationBuilderBuildsSectionedContractFromSettingsSnapshot() {
        let snapshot = AppSettingsSnapshot(
            articleOpeningMode: .safariView,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .daily,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            showUnreadCountBadge: true,
            unreadArticleSortMode: .publishedAtDescending,
            articleRetentionPolicy: .twoWeeks,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            readerAdjacentNavigationControlsMode: .swipesOnly,
            interfaceThemeMode: .black
        )
        let input = SettingsScreenInputBuilder.build(
            from: snapshot,
            iCloudSyncStatus: .statusUnavailable
        )

        let sections = SettingsScreenPresentationBuilder.buildSections(from: input)

        #expect(sections.map(\.id) == [.appearance, .reading, .articleList, .updatesAndSync, .notifications, .sourcePortability, .storage])

        let appearanceItems = sections[0].items
        let readingItems = sections[1].items
        let articleListItems = sections[2].items
        let updatesAndSyncItems = sections[3].items
        let notificationsItems = sections[4].items
        let sourcePortabilityItems = sections[5].items
        let storageItems = sections[6].items

        #expect(
            appearanceItems == [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .appearance,
                        title: "Theme",
                        subtitle: nil,
                        selectedValueTitle: "Black",
                        options: [
                            SettingsPickerOptionPresentation(id: "automaticLightDark", title: "Automatic Light/Dark", isSelected: false),
                            SettingsPickerOptionPresentation(id: "automaticLightBlack", title: "Automatic Light/Black", isSelected: false),
                            SettingsPickerOptionPresentation(id: "light", title: "Light", isSelected: false),
                            SettingsPickerOptionPresentation(id: "dark", title: "Dark", isSelected: false),
                            SettingsPickerOptionPresentation(id: "black", title: "Black", isSelected: true)
                        ]
                    )
                )
            ]
        )
        #expect(
            readingItems[0] == .picker(
                SettingsPickerItemPresentation(
                    id: .articleOpeningMode,
                    title: "Open Articles",
                    subtitle: nil,
                    selectedValueTitle: "Safari View",
                    options: [
                        SettingsPickerOptionPresentation(id: "feedReader", title: "Feed Reader", isSelected: false),
                        SettingsPickerOptionPresentation(id: "safariView", title: "Safari View", isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[1] == .picker(
                SettingsPickerItemPresentation(
                    id: .articleSourceLinkOpeningPolicy,
                    title: "Open Original Article",
                    subtitle: nil,
                    selectedValueTitle: "External Browser",
                    options: [
                        SettingsPickerOptionPresentation(id: "inAppBrowser", title: "In-App Browser", isSelected: false),
                        SettingsPickerOptionPresentation(id: "externalBrowser", title: "External Browser", isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[2] == .picker(
                SettingsPickerItemPresentation(
                    id: .articleBodyLinkOpeningPolicy,
                    title: "Open Article Links",
                    subtitle: nil,
                    selectedValueTitle: "External Browser",
                    options: [
                        SettingsPickerOptionPresentation(id: "inAppBrowser", title: "In-App Browser", isSelected: false),
                        SettingsPickerOptionPresentation(id: "externalBrowser", title: "External Browser", isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[3] == .picker(
                SettingsPickerItemPresentation(
                    id: .readerAdjacentNavigationControlsMode,
                    title: "Adjacent Navigation",
                    subtitle: nil,
                    selectedValueTitle: "Swipes",
                    options: [
                        SettingsPickerOptionPresentation(id: "toolbarControlsOnly", title: "Buttons", isSelected: false),
                        SettingsPickerOptionPresentation(id: "swipesOnly", title: "Swipes", isSelected: true),
                        SettingsPickerOptionPresentation(id: "swipesAndToolbarControls", title: "Both", isSelected: false)
                    ]
                )
            )
        )
        #expect(
            readingItems[4] == .toggle(
                SettingsToggleItemPresentation(
                    id: .markAsReadOnOpen,
                    title: "Mark Read on Open",
                    subtitle: "Automatically mark an article as read when it is opened.",
                    isOn: false
                )
            )
        )
        #expect(
            articleListItems == [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .unreadArticleSortOrder,
                        title: "Sort Unread Articles",
                        subtitle: nil,
                        selectedValueTitle: "Newest First",
                        options: [
                            SettingsPickerOptionPresentation(id: "newestFirst", title: "Newest First", isSelected: true),
                            SettingsPickerOptionPresentation(id: "oldestFirst", title: "Oldest First", isSelected: false)
                        ]
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .askBeforeMarkingAllAsRead,
                        title: "Ask Before Marking All Read",
                        subtitle: "Show a confirmation before marking all visible articles as read.",
                        isOn: false
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleRetentionPolicy,
                        title: "Keep Archived Articles",
                        subtitle: nil,
                        selectedValueTitle: "2 Weeks",
                        options: [
                            SettingsPickerOptionPresentation(id: "currentFeedOnly", title: "None", isSelected: false),
                            SettingsPickerOptionPresentation(id: "twoDays", title: "2 Days", isSelected: false),
                            SettingsPickerOptionPresentation(id: "oneWeek", title: "1 Week", isSelected: false),
                            SettingsPickerOptionPresentation(id: "twoWeeks", title: "2 Weeks", isSelected: true),
                            SettingsPickerOptionPresentation(id: "oneMonth", title: "1 Month", isSelected: false)
                        ]
                    )
                )
            ]
        )
        #expect(
            updatesAndSyncItems.contains(
                .picker(
                    SettingsPickerItemPresentation(
                        id: .refreshInterval,
                        title: "Background Refresh",
                        subtitle: nil,
                        selectedValueTitle: "Daily",
                        options: [
                            SettingsPickerOptionPresentation(id: "manual", title: "Manual", isSelected: false),
                            SettingsPickerOptionPresentation(id: "every15Minutes", title: "Every 15 Minutes", isSelected: false),
                            SettingsPickerOptionPresentation(id: "hourly", title: "Hourly", isSelected: false),
                            SettingsPickerOptionPresentation(id: "every6Hours", title: "Every 6 Hours", isSelected: false),
                            SettingsPickerOptionPresentation(id: "daily", title: "Daily", isSelected: true)
                        ]
                    )
                )
            )
        )
        #expect(
            Array(updatesAndSyncItems.suffix(2)) == [
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .useICloudSync,
                        title: "Enable iCloud Sync",
                        subtitle: "Applies on next launch. Supported data will sync through iCloud when available.",
                        isOn: true
                    )
                ),
                .statusRow(
                    SettingsStatusRowItemPresentation(
                        id: .iCloudSyncStatus,
                        title: "Current Status",
                        subtitle: "The current app session could not read the live iCloud sync status.",
                        valueTitle: "Status Unavailable"
                    )
                )
            ]
        )
        #expect(
            notificationsItems == [
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .showUnreadCountBadge,
                        title: "App Icon Badge",
                        subtitle: "Show the unread article count on the app icon.",
                        isOn: true
                    )
                )
            ]
        )
        #expect(
            sections[5].footer == "Import and export OPML files to move feed subscriptions between apps."
        )
        #expect(
            sourcePortabilityItems == [
                .button(
                    SettingsButtonItemPresentation(
                        id: .importOPML,
                        title: "Import OPML",
                        subtitle: "Preview subscriptions before adding them.",
                        systemImage: "square.and.arrow.down",
                        role: .normal,
                        isEnabled: true
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .exportOPML,
                        title: "Export OPML",
                        subtitle: "Save active subscriptions as an OPML file.",
                        systemImage: "square.and.arrow.up",
                        role: .normal,
                        isEnabled: true
                    )
                )
            ]
        )
        #expect(
            storageItems == [
                .button(
                    SettingsButtonItemPresentation(
                        id: .purgeArchivedArticles,
                        title: "Clear Archived Articles",
                        subtitle: "Remove archived articles except starred ones from this device and iCloud.",
                        systemImage: "archivebox",
                        role: .destructive,
                        isEnabled: false
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearArticleImageCache,
                        title: "Clear Article Image Cache",
                        subtitle: "Remove article images saved on this device.",
                        systemImage: "photo.stack",
                        role: .destructive,
                        isEnabled: false
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearSourceIconCache,
                        title: "Clear Source Icon Cache",
                        subtitle: "Remove feed icons saved on this device.",
                        systemImage: "newspaper",
                        role: .destructive,
                        isEnabled: false
                    )
                )
            ]
        )
    }

    @Test
    func settingsScreenPresentationBuilderIncludesAllSupportedItemTypes() {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot())
        )
        let items = sections.flatMap(\.items)

        #expect(items.contains { item in
            if case .toggle = item { return true }
            return false
        })
        #expect(items.contains { item in
            if case .picker = item { return true }
            return false
        })
        #expect(items.contains { item in
            if case .statusRow = item { return true }
            return false
        })
        #expect(items.contains { item in
            if case .button = item { return true }
            return false
        })
    }

    @Test
    func settingsScreenInputBuilderNormalizesSnapshotIntoScreenSpecificInput() {
        let snapshot = AppSettingsSnapshot(
            articleOpeningMode: .feedReader,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .every6Hours,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            unreadArticleSortMode: .publishedAtAscending,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            readerAdjacentNavigationControlsMode: .swipesOnly,
            interfaceThemeMode: .black
        )

        let input = SettingsScreenInputBuilder.build(
            from: snapshot,
            iCloudSyncStatus: .syncing
        )

        #expect(input.articleOpeningMode == .feedReader)
        #expect(input.markAsReadOnOpen == false)
        #expect(input.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(input.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(input.readerAdjacentNavigationControlsMode == .swipesOnly)
        #expect(input.unreadArticleSortOrder == .oldestFirst)
        #expect(input.askBeforeMarkingAllAsRead == false)
        #expect(input.refreshIntervalPreference == .every6Hours)
        #expect(input.useiCloudSync)
        #expect(input.iCloudSyncStatus == .syncing)
        #expect(input.syncStatusPresentation == .syncing)
        #expect(input.interfaceThemeMode == .black)
    }
}
