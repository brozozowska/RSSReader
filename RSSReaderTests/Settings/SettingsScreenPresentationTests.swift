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
                        subtitle: "This session is configured for sync, but CloudKit runtime wiring and account status are not implemented yet.",
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
        #expect(input.interfaceThemeMode == .black)
    }
}
