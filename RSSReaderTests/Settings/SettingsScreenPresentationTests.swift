import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Presentation")
@MainActor
struct SettingsScreenPresentationTests {
    @Test
    func settingsScreenPresentationBuilderBuildsSectionedContractFromSettingsSnapshot() {
        let snapshot = AppSettingsSnapshot(
            defaultReaderMode: .browser,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .daily,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            sortMode: .publishedAtDescending,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            interfaceThemeMode: .black
        )
        let input = SettingsScreenInputBuilder.build(
            from: snapshot,
            iCloudSyncStatus: .statusUnavailable
        )

        let sections = SettingsScreenPresentationBuilder.buildSections(from: input)

        #expect(sections.map(\.id) == [.reading, .articleList, .refresh, .sync, .advanced])

        let readingItems = sections[0].items
        let articleListItems = sections[1].items
        let refreshItems = sections[2].items
        let syncItems = sections[3].items
        let advancedItems = sections[4].items

        #expect(
            readingItems[0] == .picker(
                SettingsPickerItemPresentation(
                    id: .defaultReaderMode,
                    title: "Default Reader",
                    subtitle: "Choose how articles open by default.",
                    selectedValueTitle: "In-App Browser",
                    options: [
                        SettingsPickerOptionPresentation(id: "embedded", title: "Embedded Reader", isSelected: false),
                        SettingsPickerOptionPresentation(id: "reader", title: "Reader Mode", isSelected: false),
                        SettingsPickerOptionPresentation(id: "browser", title: "In-App Browser", isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[1] == .toggle(
                SettingsToggleItemPresentation(
                    id: .markAsReadOnOpen,
                    title: "Mark Read on Open",
                    subtitle: "Automatically mark an article as read when it is opened.",
                    isOn: false
                )
            )
        )
        #expect(
            readingItems[2] == .picker(
                SettingsPickerItemPresentation(
                    id: .articleBodyLinkOpeningPolicy,
                    title: "Article Links",
                    subtitle: "Choose how links inside article text should open.",
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
                    id: .articleSourceLinkOpeningPolicy,
                    title: "Source Article",
                    subtitle: "Choose how the toolbar action opens the original article URL.",
                    selectedValueTitle: "External Browser",
                    options: [
                        SettingsPickerOptionPresentation(id: "inAppBrowser", title: "In-App Browser", isSelected: false),
                        SettingsPickerOptionPresentation(id: "externalBrowser", title: "External Browser", isSelected: true)
                    ]
                )
            )
        )
        #expect(
            articleListItems == [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleSortMode,
                        title: "Sort Articles",
                        subtitle: "Choose how unread and article lists are ordered.",
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
                )
            ]
        )
        #expect(
            refreshItems.contains(
                .picker(
                    SettingsPickerItemPresentation(
                        id: .refreshInterval,
                        title: "Background Refresh",
                        subtitle: "Choose how often feeds should refresh when background refresh is available.",
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
            syncItems == [
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .useICloudSync,
                        title: "Enable iCloud Sync",
                        subtitle: "Applies on next launch. The app will rebuild its sync container and try to use iCloud for supported data.",
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
            advancedItems == [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .appearance,
                        title: "Appearance",
                        subtitle: "Choose between automatic light/dark handling, automatic light/black, or fixed appearance modes.",
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
    }

    @Test
    func settingsScreenInputBuilderNormalizesSnapshotIntoScreenSpecificInput() {
        let snapshot = AppSettingsSnapshot(
            defaultReaderMode: .reader,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .every6Hours,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            sortMode: .publishedAtAscending,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            interfaceThemeMode: .black
        )

        let input = SettingsScreenInputBuilder.build(
            from: snapshot,
            iCloudSyncStatus: .syncing
        )

        #expect(input.defaultReaderMode == .reader)
        #expect(input.markAsReadOnOpen == false)
        #expect(input.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(input.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(input.articleListSortOrder == .oldestFirst)
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
            SettingsScreenPresentationBuilder.buildSections(from: input).first(where: { $0.id == .sync })
        )
        let statusRow = try #require(syncSection.items.last)

        #expect(
            statusRow == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Sign in to iCloud with the Apple ID used on this device to enable sync. RSSReader does not require a separate account.",
                    valueTitle: "Sign In Required"
                )
            )
        )
        #expect(syncSection.footer?.contains("does not require a separate app account") == true)
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
            SettingsScreenPresentationBuilder.buildSections(from: restrictedInput).first(where: { $0.id == .sync })
        )
        let temporarilyUnavailableSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: temporarilyUnavailableInput).first(where: { $0.id == .sync })
        )
        let couldNotDetermineSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: couldNotDetermineInput).first(where: { $0.id == .sync })
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
            SettingsScreenPresentationBuilder.buildSections(from: input).first(where: { $0.id == .sync })
        )

        #expect(
            syncSection.items.first == .toggle(
                SettingsToggleItemPresentation(
                    id: .useICloudSync,
                    title: "Enable iCloud Sync",
                    subtitle: "Saved for the next launch. This session is still using local-only data because the current iCloud account is temporarily unavailable.",
                    isOn: true
                )
            )
        )
        #expect(
            syncSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Sync is enabled as a saved preference, but this app launch is still using the local-only store because the current iCloud account is temporarily unavailable. Relaunch after iCloud becomes available so the app can rebuild its sync container.",
                    valueTitle: "Temporarily Unavailable"
                )
            )
        )
        #expect(
            syncSection.footer?.contains("currently waiting for a later launch") == true
        )
    }
}
