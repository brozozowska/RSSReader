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
            selectedSourcesFilterRawValue: SidebarArticleFilter.starred.rawValue,
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
                        title: SettingsLocalization.themePickerTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsLocalization.blackOptionTitle,
                        options: [
                            SettingsPickerOptionPresentation(id: "automaticLightDark", title: SettingsLocalization.automaticLightDarkOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "automaticLightBlack", title: SettingsLocalization.automaticLightBlackOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "light", title: SettingsLocalization.lightOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "dark", title: SettingsLocalization.darkOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "black", title: SettingsLocalization.blackOptionTitle, isSelected: true)
                        ]
                    )
                )
            ]
        )
        #expect(
            readingItems[0] == .picker(
                SettingsPickerItemPresentation(
                    id: .articleOpeningMode,
                    title: SettingsLocalization.openArticlesTitle,
                    subtitle: nil,
                    selectedValueTitle: SettingsLocalization.safariViewOptionTitle,
                    options: [
                        SettingsPickerOptionPresentation(id: "feedReader", title: SettingsLocalization.feedReaderOptionTitle, isSelected: false),
                        SettingsPickerOptionPresentation(id: "safariView", title: SettingsLocalization.safariViewOptionTitle, isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[1] == .picker(
                SettingsPickerItemPresentation(
                    id: .articleSourceLinkOpeningPolicy,
                    title: SettingsLocalization.openOriginalArticleTitle,
                    subtitle: nil,
                    selectedValueTitle: SettingsLocalization.externalBrowserOptionTitle,
                    options: [
                        SettingsPickerOptionPresentation(id: "inAppBrowser", title: SettingsLocalization.inAppBrowserOptionTitle, isSelected: false),
                        SettingsPickerOptionPresentation(id: "externalBrowser", title: SettingsLocalization.externalBrowserOptionTitle, isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[2] == .picker(
                SettingsPickerItemPresentation(
                    id: .articleBodyLinkOpeningPolicy,
                    title: SettingsLocalization.openArticleLinksTitle,
                    subtitle: nil,
                    selectedValueTitle: SettingsLocalization.externalBrowserOptionTitle,
                    options: [
                        SettingsPickerOptionPresentation(id: "inAppBrowser", title: SettingsLocalization.inAppBrowserOptionTitle, isSelected: false),
                        SettingsPickerOptionPresentation(id: "externalBrowser", title: SettingsLocalization.externalBrowserOptionTitle, isSelected: true)
                    ]
                )
            )
        )
        #expect(
            readingItems[3] == .picker(
                SettingsPickerItemPresentation(
                    id: .readerAdjacentNavigationControlsMode,
                    title: SettingsLocalization.adjacentNavigationTitle,
                    subtitle: nil,
                    selectedValueTitle: SettingsLocalization.swipesOptionTitle,
                    options: [
                        SettingsPickerOptionPresentation(id: "toolbarControlsOnly", title: SettingsLocalization.buttonsOptionTitle, isSelected: false),
                        SettingsPickerOptionPresentation(id: "swipesOnly", title: SettingsLocalization.swipesOptionTitle, isSelected: true),
                        SettingsPickerOptionPresentation(id: "swipesAndToolbarControls", title: SettingsLocalization.bothOptionTitle, isSelected: false)
                    ]
                )
            )
        )
        #expect(
            readingItems[4] == .toggle(
                SettingsToggleItemPresentation(
                    id: .markAsReadOnOpen,
                    title: SettingsLocalization.markReadOnOpenTitle,
                    subtitle: SettingsLocalization.markReadOnOpenSubtitle,
                    isOn: false
                )
            )
        )
        #expect(
            articleListItems == [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .unreadArticleSortOrder,
                        title: SettingsLocalization.sortUnreadArticlesTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsLocalization.newestFirstOptionTitle,
                        options: [
                            SettingsPickerOptionPresentation(id: "newestFirst", title: SettingsLocalization.newestFirstOptionTitle, isSelected: true),
                            SettingsPickerOptionPresentation(id: "oldestFirst", title: SettingsLocalization.oldestFirstOptionTitle, isSelected: false)
                        ]
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .askBeforeMarkingAllAsRead,
                        title: SettingsLocalization.askBeforeMarkingAllReadTitle,
                        subtitle: SettingsLocalization.askBeforeMarkingAllReadSubtitle,
                        isOn: false
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleRetentionPolicy,
                        title: SettingsLocalization.keepArchivedArticlesTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsLocalization.twoWeeksOptionTitle,
                        options: [
                            SettingsPickerOptionPresentation(id: "currentFeedOnly", title: SettingsLocalization.noneOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "twoDays", title: SettingsLocalization.twoDaysOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "oneWeek", title: SettingsLocalization.oneWeekOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "twoWeeks", title: SettingsLocalization.twoWeeksOptionTitle, isSelected: true),
                            SettingsPickerOptionPresentation(id: "oneMonth", title: SettingsLocalization.oneMonthOptionTitle, isSelected: false)
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
                        title: SettingsLocalization.backgroundRefreshTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsLocalization.dailyOptionTitle,
                        options: [
                            SettingsPickerOptionPresentation(id: "manual", title: SettingsLocalization.manualOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "every15Minutes", title: SettingsLocalization.every15MinutesOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "hourly", title: SettingsLocalization.hourlyOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "every6Hours", title: SettingsLocalization.every6HoursOptionTitle, isSelected: false),
                            SettingsPickerOptionPresentation(id: "daily", title: SettingsLocalization.dailyOptionTitle, isSelected: true)
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
                        title: SettingsLocalization.enableICloudSyncTitle,
                        subtitle: SettingsLocalization.iCloudSyncPreferenceEnabledSubtitle,
                        isOn: true
                    )
                ),
                .statusRow(
                    SettingsStatusRowItemPresentation(
                        id: .iCloudSyncStatus,
                        title: SettingsLocalization.currentStatusTitle,
                        subtitle: SettingsLocalization.syncStatusUnavailableSubtitle,
                        valueTitle: SettingsLocalization.syncStatusUnavailableTitle
                    )
                )
            ]
        )
        #expect(
            notificationsItems == [
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .showUnreadCountBadge,
                        title: SettingsLocalization.appIconBadgeTitle,
                        subtitle: SettingsLocalization.appIconBadgeSubtitle,
                        isOn: true
                    )
                )
            ]
        )
        #expect(
            sections[5].footer == SettingsLocalization.sourcePortabilitySectionFooter
        )
        #expect(
            sourcePortabilityItems == [
                .button(
                    SettingsButtonItemPresentation(
                        id: .importOPML,
                        title: SettingsLocalization.importOPMLTitle,
                        subtitle: SettingsLocalization.importOPMLSubtitle,
                        systemImage: "square.and.arrow.down",
                        role: .normal,
                        isEnabled: true
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .exportOPML,
                        title: SettingsLocalization.exportOPMLTitle,
                        subtitle: SettingsLocalization.exportOPMLSubtitle,
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
                        title: SettingsLocalization.clearArchivedArticlesTitle,
                        subtitle: SettingsLocalization.clearArchivedArticlesSubtitle,
                        systemImage: "archivebox",
                        role: .destructive,
                        isEnabled: false
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearArticleImageCache,
                        title: SettingsLocalization.clearArticleImageCacheTitle,
                        subtitle: SettingsLocalization.clearArticleImageCacheSubtitle,
                        systemImage: "photo.stack",
                        role: .destructive,
                        isEnabled: false
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearSourceIconCache,
                        title: SettingsLocalization.clearSourceIconCacheTitle,
                        subtitle: SettingsLocalization.clearSourceIconCacheSubtitle,
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
            selectedSourcesFilterRawValue: SidebarArticleFilter.starred.rawValue,
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
