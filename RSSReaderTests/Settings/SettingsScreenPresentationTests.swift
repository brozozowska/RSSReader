import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Presentation")
@MainActor
struct SettingsScreenPresentationTests {
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

        #expect(sections.map(\.id) == [.appearance, .reading, .articleList, .updatesAndSync, .notifications, .storage])

        let appearanceItems = sections[0].items
        let readingItems = sections[1].items
        let articleListItems = sections[2].items
        let updatesAndSyncItems = sections[3].items
        let notificationsItems = sections[4].items
        let storageItems = sections[5].items

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
    func settingsScreenPresentationBuilderEnablesArticleImageCacheResetWhenCacheExists() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot()),
            hasArticleImageCache: true
        )
        let storageSection = try #require(sections.first(where: { $0.id == .storage }))

        #expect(
            storageSection.items == [
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
                        isEnabled: true
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
    func settingsScreenPresentationBuilderEnablesSourceIconCacheResetWhenCacheExists() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot()),
            hasSourceIconCache: true
        )
        let storageSection = try #require(sections.first(where: { $0.id == .storage }))

        #expect(
            storageSection.items.last == .button(
                SettingsButtonItemPresentation(
                    id: .clearSourceIconCache,
                    title: "Clear Source Icon Cache",
                    subtitle: "Remove feed icons saved on this device.",
                    systemImage: "newspaper",
                    role: .destructive,
                    isEnabled: true
                )
            )
        )
    }

    @Test
    func settingsScreenPresentationBuilderEnablesArchivedArticlePurgeWhenArchivedArticlesExist() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot()),
            hasArchivedArticles: true
        )
        let storageSection = try #require(sections.first(where: { $0.id == .storage }))

        #expect(
            storageSection.items.first == .button(
                SettingsButtonItemPresentation(
                    id: .purgeArchivedArticles,
                    title: "Clear Archived Articles",
                    subtitle: "Remove archived articles except starred ones from this device and iCloud.",
                    systemImage: "archivebox",
                    role: .destructive,
                    isEnabled: true
                )
            )
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

    @Test
    func settingsScreenPresentationBuilderShowsAppleIDSignInGuidanceWhenNoICloudAccountIsAvailable() throws {
        let input = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .noAccount
        )

        let syncSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: input).first(where: { $0.id == .updatesAndSync })
        )
        let statusRow = try #require(syncSection.items.last)

        #expect(
            statusRow == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Sign in to iCloud with the Apple ID used on this device to enable sync.",
                    valueTitle: "Sign In Required"
                )
            )
        )
        #expect(syncSection.footer?.contains("iCloud sync uses the Apple ID signed in on this device.") == true)
    }

    @Test
    func settingsScreenPresentationBuilderShowsSpecificAccountProblemCopyForRestrictedAndTemporaryCases() throws {
        let restrictedInput = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .restricted
        )
        let temporarilyUnavailableInput = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .temporarilyUnavailable
        )
        let couldNotDetermineInput = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .couldNotDetermine
        )

        let restrictedSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: restrictedInput).first(where: { $0.id == .updatesAndSync })
        )
        let temporarilyUnavailableSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: temporarilyUnavailableInput).first(where: { $0.id == .updatesAndSync })
        )
        let couldNotDetermineSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: couldNotDetermineInput).first(where: { $0.id == .updatesAndSync })
        )

        #expect(
            restrictedSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "This device cannot use iCloud right now because account changes or CloudKit access are restricted.",
                    valueTitle: "Restricted"
                )
            )
        )
        #expect(
            temporarilyUnavailableSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "The current iCloud account is temporarily unavailable. Try again later.",
                    valueTitle: "Temporarily Unavailable"
                )
            )
        )
        #expect(
            couldNotDetermineSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "The app could not determine the current iCloud account status. Check the device Apple ID and iCloud availability, then try again.",
                    valueTitle: "Account Unavailable"
                )
            )
        )
    }

    @Test
    func settingsScreenPresentationBuilderExplainsLocalOnlyFallbackWhenSyncPreferenceIsSavedButBootstrapStayedLocal() throws {
        let input = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .temporarilyUnavailable,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: true
        )

        let syncSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: input).first(where: { $0.id == .updatesAndSync })
        )

        #expect(
            syncSection.items.dropFirst().first == .toggle(
                SettingsToggleItemPresentation(
                    id: .useICloudSync,
                    title: "Enable iCloud Sync",
                    subtitle: "Saved for the next launch. This session keeps using local data because the current iCloud account is temporarily unavailable.",
                    isOn: true
                )
            )
        )
        #expect(
            syncSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Sync is enabled, but this launch cannot use iCloud because the current account is temporarily unavailable. Relaunch after iCloud becomes available.",
                    valueTitle: "Temporarily Unavailable"
                )
            )
        )
        #expect(
            syncSection.footer?.contains("Sync will try again on the next launch when iCloud is available.") == true
        )
    }
}
