import Foundation
import SwiftUI
import SwiftData
import Testing
@testable import RSSReader

@MainActor
struct RSSReaderTests {
    @Test
    func sourcesFilterPersistencePolicyRestoresPersistedFilterFromSettingsRawValue() {
        let settings = AppSettings(selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue)

        let restoredFilter = SourcesFilterPersistencePolicy.restoredFilter(
            from: settings.selectedSourcesFilterRawValue
        )

        #expect(restoredFilter == .starred)
    }

    @Test
    func sourcesFilterPersistencePolicyFallsBackToAllItemsWhenRawValueIsMissing() {
        let settings = AppSettings(selectedSourcesFilterRawValue: nil)

        #expect(
            SourcesFilterPersistencePolicy.restoredFilter(
                from: settings.selectedSourcesFilterRawValue
            ) == .allItems
        )
    }

    @Test
    func sourcesFilterPersistencePolicyBuildsSettingsPatchForSelectedFilter() {
        let starredUpdate = SourcesFilterPersistencePolicy.makeSettingsPatch(
            for: .starred,
            updatedAt: .distantPast
        )
        let unreadUpdate = SourcesFilterPersistencePolicy.makeSettingsPatch(
            for: .unread,
            updatedAt: .distantPast
        )

        #expect(starredUpdate.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
        #expect(unreadUpdate.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
    }

    @Test
    func appSettingsDefaultsUseSelectedSourcesFilterRawValueAsPrimarySourceFilterState() {
        let settings = AppSettings()

        #expect(settings.selectedSourcesFilterRawValue == SourcesFilter.allItems.rawValue)
        #expect(settings.askBeforeMarkingAllAsRead)
        #expect(settings.articleBodyLinkOpeningPolicy == .inAppBrowser)
        #expect(settings.articleSourceLinkOpeningPolicy == .inAppBrowser)
        #expect(settings.interfaceThemeMode == .automaticLightDark)
    }

    @Test
    func appSettingsRepositoryPersistsSelectedSourcesFilterRawValue() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
    }

    @Test
    func appSettingsRepositoryPersistsAskBeforeMarkingAllAsRead() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: false,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.askBeforeMarkingAllAsRead == false)
    }

    @Test
    func appSettingsRepositoryPersistsArticleBodyLinkOpeningPolicy() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                articleBodyLinkOpeningPolicy: .externalBrowser,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.articleBodyLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func appSettingsRepositoryPersistsArticleSourceLinkOpeningPolicy() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                articleSourceLinkOpeningPolicy: .externalBrowser,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.articleSourceLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func appSettingsRepositoryPersistsInterfaceThemeMode() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                interfaceThemeMode: .black,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.interfaceThemeMode == .black)
    }

    @Test
    func appDependenciesExposeSeparateFolderRepositoryWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.folderRepository != nil)
    }

    @Test
    func appDependenciesExposeSourceManagementServiceWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.sourceManagementService != nil)
    }

    @Test
    func folderRepositoryPersistsInsertedFoldersAndReturnsSortedList() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.folderRepository)

        _ = try repository.insert(Folder(name: "Archive", sortOrder: 2))
        _ = try repository.insert(Folder(name: "News", sortOrder: 0))
        _ = try repository.insert(Folder(name: "Tech", sortOrder: 1))

        let folders = try repository.fetchAllFolders()
        let techFolder = try repository.fetchFolder(name: "Tech")

        #expect(folders.map(\.name) == ["News", "Tech", "Archive"])
        #expect(folders.map(\.sortOrder) == [0, 1, 2])
        #expect(techFolder?.sortOrder == 1)
    }

    @Test
    func feedRepositoryUpdatesFolderAssignmentThroughExplicitPersistencePath() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let techFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/feeds/folder-assignment.xml",
                title: "Folder Assignment Feed",
                kind: .rss
            )
        )

        let techAssignmentDate = Date(timeIntervalSince1970: 1_705_000_000)
        let newsAssignmentDate = techAssignmentDate.addingTimeInterval(60)
        let ungroupedAssignmentDate = newsAssignmentDate.addingTimeInterval(60)

        let techAssignedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: techFolder,
                updatedAt: techAssignmentDate
            )
        )
        let techPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(techAssignedFeed?.folder?.id == techFolder.id)
        #expect(techAssignedFeed?.updatedAt == techAssignmentDate)
        #expect(techPersistedFeed?.folder?.id == techFolder.id)

        let newsAssignedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: newsFolder,
                updatedAt: newsAssignmentDate
            )
        )
        let newsPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(newsAssignedFeed?.folder?.id == newsFolder.id)
        #expect(newsAssignedFeed?.updatedAt == newsAssignmentDate)
        #expect(newsPersistedFeed?.folder?.id == newsFolder.id)

        let ungroupedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: nil,
                updatedAt: ungroupedAssignmentDate
            )
        )
        let ungroupedPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(ungroupedFeed?.folder == nil)
        #expect(ungroupedFeed?.updatedAt == ungroupedAssignmentDate)
        #expect(ungroupedPersistedFeed?.folder == nil)
    }

    @Test
    func sourceManagementServicePreviewsFeedMetadataThroughFetcherAndParser() async throws {
        let feedURL = "https://example.com/source-management-preview.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Preview Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Preview Article",
                            itemLink: "https://example.com/articles/preview",
                            itemGUID: "preview-article",
                            itemDescription: "Preview description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let service = try #require(harness.dependencies.sourceManagementService)

        let preview = try await service.previewFeed(urlString: feedURL)

        #expect(preview.requestedURL == feedURL)
        #expect(preview.resolvedFeedURL == feedURL)
        #expect(preview.title == "Preview Feed")
        #expect(preview.siteURL == "https://example.com/")
        #expect(preview.kind == .rss)
        #expect(preview.existingFeedID == nil)
        #expect(preview.rejectedEntryCount == 0)
    }

    @Test
    func sourceManagementServiceCreatesFolderWithNextSortOrder() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.sourceManagementService)

        let firstFolder = try service.createFolder(
            SourceManagementCreateFolderCommand(name: "News")
        )
        let secondFolder = try service.createFolder(
            SourceManagementCreateFolderCommand(name: "Tech")
        )

        let folders = try harness.folderRepository.fetchAllFolders()

        #expect(firstFolder.sortOrder == 0)
        #expect(secondFolder.sortOrder == 1)
        #expect(folders.map(\.name) == ["News", "Tech"])
        #expect(folders.map(\.sortOrder) == [0, 1])
    }

    @Test
    func sourceManagementServiceCreatesAndMovesFeedWithoutScreenLevelPersistenceAccess() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.sourceManagementService)
        let techFolder = try service.createFolder(SourceManagementCreateFolderCommand(name: "Tech"))
        let newsFolder = try service.createFolder(SourceManagementCreateFolderCommand(name: "News"))
        let preview = SourceManagementFeedPreview(
            requestedURL: "https://example.com/feed.xml",
            resolvedFeedURL: "https://example.com/feed.xml",
            title: "Example Feed",
            subtitle: "Source management preview",
            siteURL: "https://example.com/",
            iconURL: "https://example.com/icon.png",
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )

        let createdFeed = try service.createFeed(
            SourceManagementCreateFeedCommand(
                preview: preview,
                folderPlacement: .folder(techFolder.id)
            )
        )
        let createdPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        var persistedFeed = try #require(createdPersistedFeed)
        #expect(persistedFeed.folder?.name == "Tech")

        let movedFeed = try service.moveFeed(
            SourceManagementMoveFeedCommand(
                feedID: createdFeed.id,
                folderPlacement: .folder(newsFolder.id)
            )
        )
        #expect(movedFeed.folderName == "News")

        let movedPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        persistedFeed = try #require(movedPersistedFeed)
        #expect(persistedFeed.folder?.name == "News")

        let ungroupedFeed = try service.moveFeed(
            SourceManagementMoveFeedCommand(
                feedID: createdFeed.id,
                folderPlacement: .ungrouped
            )
        )
        #expect(ungroupedFeed.folderID == nil)
        #expect(ungroupedFeed.folderName == nil)

        let ungroupedPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        persistedFeed = try #require(ungroupedPersistedFeed)
        #expect(persistedFeed.folder == nil)
    }

    @Test
    func appSettingsServiceFetchesSnapshotFromRepository() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)

        _ = try repository.update(
            AppSettingsUpdate(
                defaultReaderMode: .browser,
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                refreshIntervalPreference: .hourly,
                useiCloudSync: true,
                markAsReadOnOpen: false,
                askBeforeMarkingAllAsRead: false,
                sortMode: .publishedAtAscending,
                articleBodyLinkOpeningPolicy: .externalBrowser,
                articleSourceLinkOpeningPolicy: .externalBrowser,
                interfaceThemeMode: .black,
                updatedAt: .distantPast
            )
        )

        let snapshot = try service.fetchSettings()

        #expect(
            snapshot == AppSettingsSnapshot(
                defaultReaderMode: .browser,
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                refreshIntervalPreference: .hourly,
                useiCloudSync: true,
                markAsReadOnOpen: false,
                askBeforeMarkingAllAsRead: false,
                sortMode: .publishedAtAscending,
                articleBodyLinkOpeningPolicy: .externalBrowser,
                articleSourceLinkOpeningPolicy: .externalBrowser,
                interfaceThemeMode: .black
            )
        )
    }

    @Test
    func appSettingsServiceSavesEditedSnapshot() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)
        let editedSettings = AppSettingsSnapshot(
            defaultReaderMode: .reader,
            selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
            refreshIntervalPreference: .every6Hours,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            sortMode: .publishedAtDescending,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            interfaceThemeMode: .black
        )

        let savedSnapshot = try service.saveSettings(
            editedSettings,
            updatedAt: .distantPast
        )
        let persistedSettings = try repository.fetchOrCreate()

        #expect(savedSnapshot == editedSettings)
        #expect(persistedSettings.defaultReaderMode == .reader)
        #expect(persistedSettings.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
        #expect(persistedSettings.refreshIntervalPreference == .every6Hours)
        #expect(persistedSettings.useiCloudSync)
        #expect(persistedSettings.markAsReadOnOpen == false)
        #expect(persistedSettings.askBeforeMarkingAllAsRead == false)
        #expect(persistedSettings.sortMode == .publishedAtDescending)
        #expect(persistedSettings.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(persistedSettings.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(persistedSettings.interfaceThemeMode == .black)
    }

    @Test
    func backgroundRefreshServiceBuildsConfigurationFromPersistedRefreshPreference() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.backgroundRefreshService)

        _ = try repository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .every6Hours,
                updatedAt: .distantPast
            )
        )

        let configuration = try service.loadConfiguration()

        #expect(configuration.settingsSnapshot.refreshIntervalPreference == .every6Hours)
        #expect(configuration.policy.preference == .every6Hours)
        #expect(configuration.policy.isAutomaticRefreshEnabled)
        #expect(configuration.policy.minimumInterval == 21_600.0)
    }

    @Test
    func backgroundRefreshServiceUpdatesRefreshPreferenceThroughAppSettings() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.backgroundRefreshService)

        let updatedConfiguration = try service.updatePreference(
            .daily,
            updatedAt: .distantPast
        )
        let persistedSettings = try repository.fetchOrCreate()

        #expect(updatedConfiguration.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(updatedConfiguration.policy.preference == .daily)
        #expect(updatedConfiguration.policy.minimumInterval == 86_400.0)
        #expect(persistedSettings.refreshIntervalPreference == .daily)
    }

    @Test
    func iCloudSyncStatusServiceMapsPersistedUserIntentToRuntimeStatus() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.iCloudSyncStatusService)

        #expect(try service.currentStatus() == .disabled)

        _ = try repository.update(
            AppSettingsUpdate(
                useiCloudSync: true,
                updatedAt: .distantPast
            )
        )

        #expect(try service.currentStatus() == .statusUnavailable)
    }

    @Test
    func appDependenciesSkipsBackgroundRefreshWhenPreferenceIsManual() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .manual,
                updatedAt: .distantPast
            )
        )

        let result = await harness.dependencies.refreshFeedsForBackground()

        #expect(result == nil)
    }

    @Test
    func appDependenciesRunsBackgroundRefreshWhenPreferenceIsAutomatic() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .hourly,
                updatedAt: .distantPast
            )
        )

        let result = await harness.dependencies.refreshFeedsForBackground()

        #expect(result?.trigger == .background)
        #expect(result?.batchResult.results.isEmpty == true)
    }

    @Test
    func appSettingsServiceUpdatesSelectedSourcesFilterRawValueThroughPatch() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)

        let updatedSnapshot = try service.updateSettings(
            AppSettingsPatch(
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                updatedAt: .distantPast
            )
        )
        let persistedSettings = try repository.fetchOrCreate()

        #expect(updatedSnapshot.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
        #expect(persistedSettings.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
    }

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
                .statusRow(
                    SettingsStatusRowItemPresentation(
                        id: .iCloudSyncStatus,
                        title: "iCloud Sync",
                        subtitle: "Sync is enabled, but CloudKit wiring and app-level account status are not implemented yet.",
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
    func settingsScreenStateBuildsLoadedViewStateFromSnapshot() {
        let snapshot = AppSettingsSnapshot(
            defaultReaderMode: .browser,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .hourly,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            sortMode: .publishedAtAscending
        )
        var state = SettingsScreenState()

        state.applyLoadedSnapshot(snapshot)
        let viewState = state.derivedViewState()

        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.sections.map(\.id) == [.reading, .articleList, .refresh, .sync, .advanced])
        #expect(state.settingsInput.defaultReaderMode == .browser)
        #expect(state.settingsInput.articleListSortOrder == .oldestFirst)
        #expect(state.settingsInput.iCloudSyncStatus == .disabled)
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
        #expect(input.iCloudSyncStatus == .syncing)
        #expect(input.interfaceThemeMode == .black)
    }

    @Test
    func settingsScreenStatePresentsDefaultReaderModePickerFromLoadedSections() {
        var state = SettingsScreenState.previewLoaded(
            snapshot: AppSettingsSnapshot(defaultReaderMode: .reader)
        )

        state.presentPicker(for: .defaultReaderMode)

        let presentedPicker = state.derivedViewState().presentedPicker
        #expect(presentedPicker?.id == .defaultReaderMode)
        #expect(presentedPicker?.selectedValueTitle == "Reader Mode")
        #expect(presentedPicker?.options.count == ReaderMode.allCases.count)
    }

    @Test
    func settingsScreenControllerDoesNotTreatSyncStatusRowAsInteractiveItem() {
        let controller = SettingsScreenController(
            previewScreenState: .previewLoaded(snapshot: AppSettingsSnapshot())
        )

        controller.handleItemSelection(.iCloudSyncStatus)

        #expect(controller.viewState().presentedPicker == nil)
    }

    @Test
    func settingsScreenControllerLoadsSettingsSnapshotFromService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.appSettingsService)
        _ = try service.saveSettings(
            AppSettingsSnapshot(
                defaultReaderMode: .reader,
                selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
            refreshIntervalPreference: .every15Minutes,
            useiCloudSync: false,
            markAsReadOnOpen: true,
            askBeforeMarkingAllAsRead: false,
            sortMode: .publishedAtDescending,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            interfaceThemeMode: .black
        ),
            updatedAt: .distantPast
        )
        let controller = SettingsScreenController()
        let appState = AppState()

        controller.loadSettings(dependencies: harness.dependencies, appState: appState)

        let viewState = controller.viewState()
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.sections.isEmpty == false)
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .reader)
        #expect(controller.screenState.settingsSnapshot.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
        #expect(controller.screenState.settingsSnapshot.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(controller.screenState.settingsSnapshot.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(controller.screenState.settingsSnapshot.interfaceThemeMode == .black)
        #expect(controller.screenState.iCloudSyncStatus == .disabled)
        #expect(appState.interfaceThemeMode == .black)
    }

    @Test
    func settingsScreenControllerPrefersAppLevelICloudSyncStatusOverPersistedFlag() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()
        let appState = AppState()

        _ = try repository.update(
            AppSettingsUpdate(
                useiCloudSync: true,
                updatedAt: .distantPast
            )
        )
        appState.applyICloudSyncStatus(.syncing)

        controller.loadSettings(dependencies: harness.dependencies, appState: appState)

        let syncSection = try #require(
            controller.viewState().sections.first(where: { $0.id == .sync })
        )
        let syncItem = try #require(syncSection.items.first)

        #expect(controller.screenState.iCloudSyncStatus == .syncing)
        #expect(appState.iCloudSyncStatus == .syncing)
        #expect(
            syncItem == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "iCloud Sync",
                    subtitle: "Changes are currently syncing with iCloud.",
                    valueTitle: "Syncing"
                )
            )
        )
    }

    @Test
    func settingsScreenControllerPersistsUpdatedDefaultReaderModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.defaultReaderMode)

        #expect(controller.viewState().presentedPicker?.id == .defaultReaderMode)

        controller.handlePickerOptionSelection(
            itemID: .defaultReaderMode,
            optionID: ReaderMode.browser.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.defaultReaderMode == .browser)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.defaultReaderMode == .browser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleSortModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.articleSortMode)

        #expect(controller.viewState().presentedPicker?.id == .articleSortMode)

        controller.handlePickerOptionSelection(
            itemID: .articleSortMode,
            optionID: ArticleListSortOrder.oldestFirst.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.sortMode == .publishedAtAscending)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.sortMode == .publishedAtAscending)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedMarkAsReadOnOpenThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        #expect(controller.screenState.settingsSnapshot.markAsReadOnOpen)

        controller.handleToggleValueChange(
            itemID: .markAsReadOnOpen,
            isOn: false,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.markAsReadOnOpen == false)
        #expect(persistedSettings.markAsReadOnOpen == false)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedAskBeforeMarkingAllAsReadThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead)

        controller.handleToggleValueChange(
            itemID: .askBeforeMarkingAllAsRead,
            isOn: false,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.askBeforeMarkingAllAsRead == false)
        #expect(persistedSettings.askBeforeMarkingAllAsRead == false)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleBodyLinkOpeningPolicyThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.articleBodyLinkOpeningPolicy)

        #expect(controller.viewState().presentedPicker?.id == .articleBodyLinkOpeningPolicy)

        controller.handlePickerOptionSelection(
            itemID: .articleBodyLinkOpeningPolicy,
            optionID: ArticleBodyLinkOpeningPolicy.externalBrowser.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.articleBodyLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedArticleSourceLinkOpeningPolicyThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.articleSourceLinkOpeningPolicy)

        #expect(controller.viewState().presentedPicker?.id == .articleSourceLinkOpeningPolicy)

        controller.handlePickerOptionSelection(
            itemID: .articleSourceLinkOpeningPolicy,
            optionID: ArticleSourceLinkOpeningPolicy.externalBrowser.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.articleSourceLinkOpeningPolicy == .externalBrowser)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedRefreshIntervalThroughBackgroundRefreshService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: harness.dependencies)
        controller.handleItemSelection(.refreshInterval)

        #expect(controller.viewState().presentedPicker?.id == .refreshInterval)

        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.daily.rawValue,
            dependencies: harness.dependencies
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.refreshIntervalPreference == .daily)
    }

    @Test
    func settingsScreenControllerPersistsUpdatedInterfaceThemeModeThroughSettingsService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()
        let appState = AppState()

        controller.loadSettings(dependencies: harness.dependencies, appState: appState)
        controller.handleItemSelection(.appearance)

        #expect(controller.viewState().presentedPicker?.id == .appearance)

        controller.handlePickerOptionSelection(
            itemID: .appearance,
            optionID: InterfaceThemeMode.black.rawValue,
            dependencies: harness.dependencies,
            appState: appState
        )

        let persistedSettings = try repository.fetchOrCreate()
        #expect(controller.screenState.settingsSnapshot.interfaceThemeMode == .black)
        #expect(controller.viewState().presentedPicker == nil)
        #expect(persistedSettings.interfaceThemeMode == .black)
        #expect(appState.interfaceThemeMode == .black)
    }

    @Test
    func appThemeApplicationPolicyResolvesAutomaticModesAgainstSystemColorScheme() {
        let automaticDarkPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .automaticLightDark,
            systemColorScheme: .dark
        )
        let automaticBlackPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .automaticLightBlack,
            systemColorScheme: .dark
        )
        let automaticLightPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .automaticLightBlack,
            systemColorScheme: .light
        )

        #expect(automaticDarkPolicy.preferredColorScheme == nil)
        #expect(automaticDarkPolicy.resolvedTheme == .dark)
        #expect(automaticBlackPolicy.preferredColorScheme == nil)
        #expect(automaticBlackPolicy.resolvedTheme == .black)
        #expect(automaticLightPolicy.resolvedTheme == .light)
    }

    @Test
    func appThemeApplicationPolicyUsesExplicitThemeModeForResolvedThemeAndPreferredColorScheme() {
        let lightPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .light,
            systemColorScheme: .dark
        )
        let darkPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .dark,
            systemColorScheme: .light
        )
        let blackPolicy = AppThemeApplicationPolicy(
            interfaceThemeMode: .black,
            systemColorScheme: .light
        )

        #expect(lightPolicy.preferredColorScheme == .light)
        #expect(lightPolicy.resolvedTheme == .light)
        #expect(darkPolicy.preferredColorScheme == .dark)
        #expect(darkPolicy.resolvedTheme == .dark)
        #expect(blackPolicy.preferredColorScheme == .dark)
        #expect(blackPolicy.resolvedTheme == .black)
    }

    @Test
    func settingsScreenControllerBuildsFailureStateWhenSettingsServiceIsUnavailable() {
        let controller = SettingsScreenController()
        let dependencies = AppDependencies.makeDefault()

        controller.loadSettings(dependencies: dependencies)

        #expect(controller.viewState().sections.isEmpty)
        #expect(
            controller.viewState().placeholder == SettingsScreenPlaceholderState(
                title: "Unable to Load Settings",
                systemImage: "exclamationmark.triangle",
                description: "Settings are unavailable in the current app environment.",
                actionTitle: "Retry"
            )
        )
    }

    @Test
    func folderSelectionInheritsActiveSourcesFilterForSelectedFolder() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/news-feed.xml",
                "https://example.com/tech-feed.xml"
            ]
        )
        let newsFeed = try #require(feeds.first)
        let techFeed = try #require(feeds.last)
        let newsFolder = Folder(name: "News")
        newsFeed.folder = newsFolder
        try harness.saveModelContext()

        let unreadNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-unread",
            url: "https://example.com/news/unread",
            title: "Unread News"
        )
        let starredNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-starred",
            url: "https://example.com/news/starred",
            title: "Starred News"
        )
        let readNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-read",
            url: "https://example.com/news/read",
            title: "Read News"
        )
        let starredTechArticle = try harness.insertArticle(
            feed: techFeed,
            externalID: "tech-starred",
            url: "https://example.com/tech/starred",
            title: "Starred Tech"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredNewsArticle, at: .now)
        _ = try stateService.markAsRead(article: starredNewsArticle, at: .now)
        _ = try stateService.markAsRead(article: readNewsArticle, at: .now)
        _ = try stateService.toggleStarred(article: starredTechArticle, at: .now)

        let unreadItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .unread
        )
        let resolvedUnreadItems = try #require(unreadItems)

        let starredItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .starred
        )
        let resolvedStarredItems = try #require(starredItems)

        let allItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .all
        )
        let resolvedAllItems = try #require(allItems)

        #expect(resolvedUnreadItems.map(\.id) == [unreadNewsArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredNewsArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [readNewsArticle.id, starredNewsArticle.id, unreadNewsArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == newsFeed.id })
    }

    @Test
    func feedSelectionInheritsActiveSourcesFilterForSelectedSource() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/source-feed.xml"]).first)

        let unreadArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-unread",
            url: "https://example.com/source/unread",
            title: "Unread Source"
        )
        let starredArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-starred",
            url: "https://example.com/source/starred",
            title: "Starred Source"
        )
        let readArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-read",
            url: "https://example.com/source/read",
            title: "Read Source"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(article: readArticle, at: .now)

        let unreadItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .unread
        )
        let resolvedUnreadItems = try #require(unreadItems)

        let starredItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .starred
        )
        let resolvedStarredItems = try #require(starredItems)

        let allItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .all
        )
        let resolvedAllItems = try #require(allItems)

        #expect(resolvedUnreadItems.map(\.id) == [unreadArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [readArticle.id, starredArticle.id, unreadArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == feed.id })
    }

    @Test
    func sourcesFilterArticleListFilterResolverMapsSourcesFilterToExpectedArticleFilter() {
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .allItems) == .all)
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .unread) == .unread)
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .starred) == .starred)
    }

    @Test
    func sourcesSmartViewsShowOnlyActiveFilterRow() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: true) == [.allItems])
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: true) == [.unread])
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: true) == [.starred])
    }

    @Test
    func sourcesSmartViewsAreHiddenWhenThereAreNoFeeds() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: false).isEmpty)
    }

    @Test
    func sourcesSelectionBehaviorKeepsCurrentFeedSelectionWhenItRemainsVisible() {
        let visibleFeedID = UUID()

        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .feed(visibleFeedID),
            filter: .starred,
            visibleFeedIDs: [visibleFeedID],
            visibleFolderNames: []
        )

        #expect(selection == .feed(visibleFeedID))
    }

    @Test
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFeedBecomesHidden() {
        let hiddenFeedID = UUID()

        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .feed(hiddenFeedID),
            filter: .unread,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .unread)
    }

    @Test
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentSmartSelectionDoesNotMatchFilter() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .inbox,
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    @Test
    func sourcesSelectionBehaviorKeepsNoSelectionWhenThereIsNoCurrentSelection() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: nil,
            filter: .allItems,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == nil)
    }

    @Test
    func sourcesSelectionBehaviorKeepsCurrentFolderSelectionWhenItRemainsVisible() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .unread,
            visibleFeedIDs: [],
            visibleFolderNames: ["News"]
        )

        #expect(selection == .folder("News"))
    }

    @Test
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFolderBecomesHidden() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    @Test
    func sourcesSidebarShowsOnlyFeedsWithStarredArticlesWhenStarredFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .starred,
            starredFeedIDs: [feedTwoID]
        )

        #expect(filteredFeeds.map(\.id) == [feedTwoID])
    }

    @Test
    func sourcesSidebarKeepsAllFeedsVisibleForAllItemsFilter() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let allItemsFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .allItems,
            starredFeedIDs: [feedTwoID]
        )

        #expect(allItemsFeeds.map(\.id) == feeds.map(\.id))
        #expect(allItemsFeeds.map(\.unreadCount) == feeds.map(\.unreadCount))
    }

    @Test
    func sourcesSidebarShowsOnlyFeedsWithUnreadArticlesWhenUnreadFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .unread,
            starredFeedIDs: []
        )

        #expect(filteredFeeds.map(\.id) == [feedOneID])
    }

    @Test
    func sourcesSidebarHidesFoldersSectionWhenFilteredFeedsDoNotContainFolders() {
        let ungroupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Ungrouped Feed"),
            unreadCount: 1
        )

        let groups = FolderSidebarGroup.groups(from: [ungroupedFeed])

        #expect(groups.isEmpty)
    }

    @Test
    func sourcesSidebarHidesUngroupedSectionWhenFilteredFeedsDoNotContainUngroupedSources() {
        let folder = Folder(name: "News")
        let groupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Grouped Feed", folder: folder),
            unreadCount: 1
        )

        let ungroupedFeeds = SidebarUngroupedFeeds.visibleFeeds(from: [groupedFeed])

        #expect(ungroupedFeeds.isEmpty)
    }

    @Test
    func shellActionEntryPointsUpdateSelectionAndFilterInAppState() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)
        harness.dependencies.applySourcesFilter(.unread, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.selectedSourcesFilter == .unread)

        harness.dependencies.showInbox(using: appState)

        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)

        harness.dependencies.showFolder(named: "News", using: appState)

        #expect(appState.selectedSidebarSelection == .folder("News"))
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)

        harness.dependencies.showUnread(using: appState)
        #expect(appState.selectedSidebarSelection == .unread)

        harness.dependencies.showStarred(using: appState)
        #expect(appState.selectedSidebarSelection == .starred)
    }

    @Test
    func settingsPresentationStateLivesInAppStateAndDoesNotResetReadingShellContext() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)

        harness.dependencies.showSettings(using: appState)

        #expect(appState.isPresentingSettingsScreen)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))

        harness.dependencies.dismissSettings(using: appState)

        #expect(appState.isPresentingSettingsScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
    }

    @Test
    func sourceManagementPresentationStateUsesSeparateModalFlowAndDoesNotResetReadingShellContext() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)

        harness.dependencies.showSourceManagement(using: appState)

        #expect(appState.isPresentingSourceManagementScreen)
        #expect(appState.isPresentingSettingsScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))

        harness.dependencies.dismissSourceManagement(using: appState)

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.isPresentingSettingsScreen == false)
        #expect(appState.sourceManagementLaunchContext == .entry)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
    }

    @Test
    func sourceManagementPresentationStateTracksSidebarEditLaunchContextWithoutResettingReadingShellContext() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)
        harness.dependencies.showFeedEditor(id: feedID, using: appState)

        #expect(appState.isPresentingSourceManagementScreen)
        #expect(appState.sourceManagementLaunchContext == .editFeed(feedID))
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))

        harness.dependencies.dismissSourceManagement(using: appState)

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.sourceManagementLaunchContext == .entry)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
    }

    @Test
    func sourceManagementScreenStateBuildsSeparatedEntrySections() {
        let state = SourceManagementScreenState.makePreviewFixture()
        let viewState = state.derivedViewState()

        #expect(viewState.summary.title == "Choose the source task you want to start.")
        #expect(viewState.sections.map(\.id) == [.startNew, .organizeExisting])
        #expect(viewState.sections.first?.items.map(\.id) == [.addFeed, .createFolder])
        #expect(viewState.sections.last?.items.map(\.id) == [.moveSource])
    }

    @Test
    func sourceManagementScreenStateBuildsAddFeedPresentationWithPreviewAndConfirmationState() {
        var state = SourceManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let techFolderID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        state.applyAddFeedFolderContext(
            folders: [
                SourceManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 5
                ),
                SourceManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 3
                )
            ]
        )
        state.presentScenario(.addFeed)

        guard case .addFeed(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation")
            return
        }

        #expect(initialDestination.validationMessage == "Enter a feed URL to continue.")
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.updateAddFeedURLInput("example")

        guard case .addFeed(let invalidDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after invalid URL input")
            return
        }

        #expect(invalidDestination.validationMessage == "Enter a valid http or https URL.")
        #expect(invalidDestination.isPrimaryActionEnabled == false)

        state.updateAddFeedURLInput(" https://example.com/feed.xml ")

        guard case .addFeed(let validDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after URL input")
            return
        }

        #expect(validDestination.validationMessage == nil)
        #expect(validDestination.normalizedURL == "https://example.com/feed.xml")
        #expect(validDestination.isPrimaryActionEnabled)

        let preview = SourceManagementFeedPreview(
            requestedURL: "https://example.com/feed.xml",
            resolvedFeedURL: "https://example.com/feed.xml",
            title: "Example Feed",
            subtitle: "Preview subtitle",
            siteURL: "https://example.com/",
            iconURL: "https://example.com/icon.png",
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )
        let requestURL = state.beginAddFeedPreviewLoading()
        state.applyLoadedAddFeedPreview(preview, requestURL: requestURL ?? "")

        guard case .addFeed(let previewDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview loading")
            return
        }

        #expect(previewDestination.primaryActionTitle == "Confirm Feed")
        #expect(previewDestination.isPrimaryActionEnabled)
        #expect(previewDestination.preview?.title == "Example Feed")
        #expect(previewDestination.preview?.kindTitle == "RSS")
        #expect(previewDestination.placementOptions.map(\.title) == ["Ungrouped", "News", "Tech"])
        #expect(previewDestination.placementOptions.first?.isSelected == true)
        #expect(previewDestination.createFolderActionTitle == "Create New Folder")

        state.selectAddFeedFolderPlacement(.folder(techFolderID))

        state.confirmAddFeedPreview()

        guard case .addFeed(let confirmedDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after confirmation")
            return
        }

        #expect(confirmedDestination.primaryActionTitle == "Add Feed")
        #expect(confirmedDestination.isPrimaryActionEnabled)
        #expect(confirmedDestination.status?.kind == .success)
        #expect(confirmedDestination.placementOptions.last?.isSelected == true)
        #expect(confirmedDestination.status?.detail?.contains("Tech") == true)

        let createCommand = state.beginAddFeedCreation()
        #expect(createCommand?.folderPlacement == .folder(techFolderID))
        state.applyCreatedAddFeed(
            SourceManagementFeedSummary(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                url: "https://example.com/feed.xml",
                title: "Example Feed",
                folderID: techFolderID,
                folderName: "Tech"
            )
        )

        guard case .addFeed(let createdDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after feed creation")
            return
        }

        #expect(createdDestination.primaryActionTitle == "Feed Added")
        #expect(createdDestination.isPrimaryActionEnabled == false)
        #expect(createdDestination.status?.title == "Feed added")
    }

    @Test
    func sourceManagementScreenStateBuildsCreateFolderPresentationWithValidationAndPlacement() {
        var state = SourceManagementScreenState.makePreviewFixture()
        state.applyCreateFolderContext(
            folders: [
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 5
                ),
                SourceManagementFolderSummary(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 3
                )
            ]
        )
        state.presentScenario(.createFolder)

        guard case .createFolder(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation")
            return
        }

        #expect(initialDestination.existingFolders.map(\.name) == ["News", "Tech"])
        #expect(initialDestination.placementDescription.contains("#3"))
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.updateCreateFolderNameInput("News")

        guard case .createFolder(let duplicateDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after duplicate input")
            return
        }

        #expect(duplicateDestination.validationMessage == "A folder with this name already exists.")
        #expect(duplicateDestination.isPrimaryActionEnabled == false)

        state.updateCreateFolderNameInput("Research")

        guard case .createFolder(let validDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after valid input")
            return
        }

        #expect(validDestination.validationMessage == nil)
        #expect(validDestination.isPrimaryActionEnabled)
    }

    @Test
    func sourceManagementScreenControllerLoadsFeedPreviewThroughSourceManagementService() async throws {
        let feedURL = "https://example.com/preview-controller.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Controller Preview Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Preview Article",
                            itemLink: "https://example.com/articles/preview",
                            itemGUID: "controller-preview-article",
                            itemDescription: "Preview description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(" \(feedURL) ")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview loading")
            return
        }

        #expect(destination.preview?.title == "Controller Preview Feed")
        #expect(destination.preview?.siteURL == "https://example.com/")
        #expect(destination.preview?.kindTitle == "RSS")
        #expect(destination.primaryActionTitle == "Confirm Feed")
        #expect(destination.isPrimaryActionEnabled)

        let recordedRequests = await harness.httpClient.recordedRequests()
        #expect(recordedRequests.map(\.url.absoluteString) == [feedURL])

        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let confirmedDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview confirmation")
            return
        }

        #expect(confirmedDestination.primaryActionTitle == "Add Feed")
        #expect(confirmedDestination.status?.kind == .success)
    }

    @Test
    func sourceManagementScreenControllerCreatesFeedThroughServiceAfterConfirmedPreview() async throws {
        let feedURL = "https://example.com/create-from-preview.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Created Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Created Article",
                            itemLink: "https://example.com/articles/created",
                            itemGUID: "created-article",
                            itemDescription: "Created description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let folder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(" \(feedURL) ")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)
        controller.handleAddFeedFolderPlacementSelection(.folder(folder.id))
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let createdDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after feed creation")
            return
        }

        let persistedFeed = try harness.feedRepository.fetchFeed(url: feedURL)

        #expect(createdDestination.primaryActionTitle == "Feed Added")
        #expect(createdDestination.isPrimaryActionEnabled == false)
        #expect(createdDestination.status?.title == "Feed added")
        #expect(createdDestination.status?.detail == "Created Feed was saved in Tech.")
        #expect(persistedFeed?.url == feedURL)
        #expect(persistedFeed?.title == "Created Feed")
        #expect(persistedFeed?.siteURL == "https://example.com/")
        #expect(persistedFeed?.kind == .rss)
        #expect(persistedFeed?.folder?.id == folder.id)
    }

    @Test
    func sourceManagementScreenControllerCreatesFeedRefreshesItAndDismissesSourceManagementFlow() async throws {
        let feedURL = "https://example.com/create-and-refresh.xml"
        let responseStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: Self.validRSSFeedXML(
                channelTitle: "Created And Refreshed Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "First Refreshed Article",
                itemLink: "https://example.com/articles/first-refreshed",
                itemGUID: "first-refreshed-article",
                itemDescription: "Refreshed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [responseStep, responseStep]
            )
        )
        let appState = AppState()
        let controller = SourceManagementScreenController()
        let articleReloadIDBeforeCreation = appState.articleListReloadID
        let sidebarReloadIDBeforeCreation = appState.sourcesSidebarReloadID

        harness.dependencies.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(url: feedURL))
        let articles = try harness.articleRepository.fetchArticles(feedID: persistedFeed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(persistedFeed.id))
        #expect(appState.articleListReloadID != articleReloadIDBeforeCreation)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCreation)
        #expect(persistedFeed.lastFetchedAt != nil)
        #expect(persistedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "First Refreshed Article")
        #expect(requests.map(\.url.absoluteString) == [feedURL, feedURL])
    }

    @Test
    func sourceManagementScreenControllerEditsFeedFromSidebarLaunchContextAndRefreshesUpdatedSource() async throws {
        let initialURL = "https://example.com/original-feed.xml"
        let updatedURL = "https://example.com/updated-feed.xml"
        let previewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: Self.validRSSFeedXML(
                channelTitle: "Updated Feed Title",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Updated Feed Article",
                itemLink: "https://example.com/articles/updated-feed",
                itemGUID: "updated-feed-article",
                itemDescription: "Updated feed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: [previewStep, previewStep])
        )
        let originalFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let updatedFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: initialURL,
                title: "Original Feed",
                kind: .rss,
                folder: originalFolder
            )
        )
        let appState = AppState()
        let controller = SourceManagementScreenController()

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.showFeedEditor(id: feed.id, using: appState)
        controller.handleLaunchContext(.editFeed(feed.id), dependencies: harness.dependencies)

        guard case .addFeed(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation for feed editor launch context")
            return
        }

        #expect(initialDestination.title == "Edit Feed")
        #expect(initialDestination.urlInput == initialURL)
        #expect(initialDestination.placementOptions.first(where: { $0.title == "News" })?.isSelected == true)

        controller.handleAddFeedURLChange(updatedURL)
        controller.handleAddFeedFolderPlacementSelection(.folder(updatedFolder.id))
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(persistedFeed.url == updatedURL)
        #expect(persistedFeed.title == "Updated Feed Title")
        #expect(persistedFeed.folder?.id == updatedFolder.id)
        #expect(persistedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Updated Feed Article")
        #expect(requests.map(\.url.absoluteString) == [updatedURL, updatedURL])
    }

    @Test
    func sourceManagementScreenControllerEditsFolderFromSidebarLaunchContextAndRetargetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let controller = SourceManagementScreenController()
        let sidebarReloadIDBeforeEdit = appState.sourcesSidebarReloadID

        harness.dependencies.showFolder(named: "News", using: appState)
        harness.dependencies.showFolderEditor(named: "News", using: appState)
        controller.handleLaunchContext(.editFolder(folder.id), dependencies: harness.dependencies)

        guard case .createFolder(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation for folder editor launch context")
            return
        }

        #expect(initialDestination.title == "Edit Folder")
        #expect(initialDestination.nameInput == "News")

        controller.handleCreateFolderNameChange("World News")
        controller.submitCreateFolder(dependencies: harness.dependencies, appState: appState)

        let renamedFolder = try #require(try harness.folderRepository.fetchFolder(id: folder.id))

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeEdit)
        #expect(renamedFolder.name == "World News")
        #expect(renamedFolder.sortOrder == 0)
    }

    @Test
    func sourceManagementScreenControllerShowsDuplicateFeedWarningWhenPreviewMatchesExistingSource() async throws {
        let feedURL = "https://example.com/existing-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Existing Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Existing Article",
                            itemLink: "https://example.com/articles/existing",
                            itemGUID: "existing-article",
                            itemDescription: "Existing description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        _ = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Existing Feed",
                kind: .rss
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after duplicate preview loading")
            return
        }

        #expect(destination.preview?.title == "Existing Feed")
        #expect(destination.preview?.existingFeedNotice == "This source already exists in the library.")
        #expect(destination.status?.kind == .warning)
        #expect(destination.status?.title == "This feed is already in the library")
        #expect(destination.primaryActionTitle == "Already Added")
        #expect(destination.isPrimaryActionEnabled == false)
    }

    @Test
    func sourceManagementScreenControllerShowsNetworkFailureStatusWhenPreviewRequestFails() async throws {
        let feedURL = "https://example.com/network-failure.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .urlError(.notConnectedToInternet)
                ]
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after network failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == "Network error while loading preview")
        #expect(destination.status?.detail == "Check the internet connection and try loading the preview again.")
        #expect(destination.primaryActionTitle == "Preview Feed")
        #expect(destination.isPrimaryActionEnabled)
    }

    @Test
    func sourceManagementScreenControllerShowsUnsupportedFeedStatusWhenPreviewResponseIsNotAFeed() async throws {
        let feedURL = "https://example.com/not-a-feed"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "text/html; charset=utf-8"],
                        body: "<html><body>Not a feed</body></html>"
                    )
                ]
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after unsupported-feed failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == "Source is not a supported feed")
        #expect(destination.status?.detail == "The URL responded with text/html; charset=utf-8, not a supported RSS or Atom feed.")
        #expect(destination.primaryActionTitle == "Preview Feed")
        #expect(destination.isPrimaryActionEnabled)
    }

    @Test
    func sourceManagementScreenStateBuildsMoveSourcePresentationWithFeedAndPlacementSelection() {
        var state = SourceManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let techFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        state.applyMoveSourceContext(
            feeds: [
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    url: "https://example.com/apple.xml",
                    title: "Apple Feed",
                    folderID: newsFolderID,
                    folderName: "News"
                ),
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                    url: "https://example.com/beta.xml",
                    title: "Beta Feed",
                    folderID: nil,
                    folderName: nil
                )
            ],
            folders: [
                SourceManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 2
                ),
                SourceManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 6
                )
            ]
        )
        state.presentScenario(.moveSource)

        guard case .moveSource(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation")
            return
        }

        #expect(initialDestination.feeds.map(\.title) == ["Apple Feed", "Beta Feed"])
        #expect(initialDestination.feeds.first?.isSelected == true)
        #expect(initialDestination.placementOptions.map(\.title) == ["Ungrouped", "News", "Tech"])
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.selectMoveSourcePlacement(.folder(techFolderID))

        guard case .moveSource(let changedDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation after placement change")
            return
        }

        #expect(changedDestination.isPrimaryActionEnabled)
        #expect(changedDestination.placementOptions.last?.isSelected == true)
    }

    @Test
    func sourceManagementScreenControllerMovesFeedThroughServiceAndRefreshesDestination() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let techFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/move-me.xml",
                title: "Move Me",
                kind: .rss,
                folder: newsFolder
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.moveSource, dependencies: harness.dependencies)

        guard case .moveSource(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation")
            return
        }

        #expect(initialDestination.feeds.map(\.title) == ["Move Me"])
        #expect(initialDestination.feeds.first?.currentPlacementTitle == "News")
        #expect(initialDestination.isPrimaryActionEnabled == false)

        controller.handleMoveSourcePlacementSelection(.folder(techFolder.id))
        controller.submitMoveSource(dependencies: harness.dependencies)

        guard case .moveSource(let movedDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation after move")
            return
        }

        let persistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(movedDestination.feedback?.kind == .success)
        #expect(movedDestination.feedback?.detail?.contains("Tech") == true)
        #expect(movedDestination.feeds.first?.currentPlacementTitle == "Tech")
        #expect(movedDestination.isPrimaryActionEnabled == false)
        #expect(persistedFeed?.folder?.id == techFolder.id)
    }

    @Test
    func sourceManagementScreenControllerMovesFeedDismissesModalAndReloadsAffectedSelectionInAppFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let techFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/app-move.xml",
                title: "App Move",
                kind: .rss,
                folder: newsFolder
            )
        )
        let controller = SourceManagementScreenController()
        let appState = AppState()

        harness.dependencies.showFolder(named: "News", using: appState)
        let articleReloadIDBeforeMove = appState.articleListReloadID
        let sidebarReloadIDBeforeMove = appState.sourcesSidebarReloadID

        harness.dependencies.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.moveSource, dependencies: harness.dependencies)
        controller.handleMoveSourcePlacementSelection(.folder(techFolder.id))
        controller.submitMoveSource(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeMove)
        #expect(appState.articleListReloadID != articleReloadIDBeforeMove)
        #expect(persistedFeed?.folder?.id == techFolder.id)
    }

    @Test
    func sourceManagementScreenControllerReturnsToAddFeedWithNewFolderSelectedAfterInlineFolderCreation() async throws {
        let feedURL = "https://example.com/feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Example Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Example Article",
                            itemLink: "https://example.com/articles/example",
                            itemGUID: "example-article",
                            itemDescription: "Example description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        _ = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(feedURL)
        controller.startCreateFolderFromAddFeed(dependencies: harness.dependencies)

        guard case .createFolder(let createFolderDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination when starting from add-feed flow")
            return
        }

        #expect(createFolderDestination.existingFolders.map(\.name) == ["News"])

        controller.handleCreateFolderNameChange("Research")
        controller.submitCreateFolder(dependencies: harness.dependencies)

        guard case .addFeed(let addFeedDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination after inline folder creation")
            return
        }

        #expect(addFeedDestination.urlInput == feedURL)
        #expect(addFeedDestination.primaryActionTitle == "Preview Feed")
        #expect(addFeedDestination.placementOptions.isEmpty)

        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let previewDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after loading preview")
            return
        }

        #expect(previewDestination.placementOptions.map(\.title) == ["Ungrouped", "News", "Research"])
        #expect(previewDestination.placementOptions.last?.isSelected == true)
    }

    @Test
    func sourceManagementScreenControllerCreatesFolderThroughServiceAndRefreshesDestination() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SourceManagementScreenController()

        _ = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))

        controller.handleScenarioSelection(.createFolder, dependencies: harness.dependencies)

        guard case .createFolder(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation")
            return
        }

        #expect(initialDestination.existingFolders.map(\.name) == ["News"])
        #expect(initialDestination.isPrimaryActionEnabled == false)

        controller.handleCreateFolderNameChange("Research")

        guard case .createFolder(let draftDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after input")
            return
        }

        #expect(draftDestination.validationMessage == nil)
        #expect(draftDestination.isPrimaryActionEnabled)

        controller.submitCreateFolder(dependencies: harness.dependencies)

        guard case .createFolder(let createdDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after submission")
            return
        }

        #expect(createdDestination.nameInput.isEmpty)
        #expect(createdDestination.existingFolders.map(\.name) == ["News", "Research"])
        #expect(createdDestination.placementDescription.contains("#3"))
        #expect(createdDestination.feedback?.kind == .success)

        let folders = try harness.folderRepository.fetchAllFolders()
        #expect(folders.map(\.name) == ["News", "Research"])
        #expect(folders.map(\.sortOrder) == [0, 1])
    }

    @Test
    func sourceManagementScreenControllerCreatesFolderRequestsSidebarReloadInAppFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SourceManagementScreenController()
        let appState = AppState()
        let sidebarReloadIDBeforeCreation = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCreation = appState.articleListReloadID

        harness.dependencies.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.createFolder, dependencies: harness.dependencies)
        controller.handleCreateFolderNameChange("Research")
        controller.submitCreateFolder(
            dependencies: harness.dependencies,
            appState: appState
        )

        guard case .createFolder(let createdDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after app-level creation")
            return
        }

        #expect(appState.isPresentingSourceManagementScreen)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCreation)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCreation)
        #expect(createdDestination.feedback?.title == "Folder created")
        #expect(createdDestination.feedback?.detail?.contains("now appears") == true)
        #expect(try harness.folderRepository.fetchFolder(name: "Research") != nil)
    }

    @Test
    func shellActionEntryPointsOpenAndCloseArticleWebViewViaDependencies() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/shell-web.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "shell-web-article",
            url: "https://example.com/articles/1",
            title: "Shell Web Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/1/canonical"
        try harness.saveModelContext()
        let readerArticle = try harness.dependencies.articleQueryService?.fetchReaderArticle(id: articleModel.id)
        let article = try #require(readerArticle)

        harness.dependencies.selectArticle(id: article.id, using: appState)
        harness.dependencies.openArticleInWebView(article, using: appState)

        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!))

        harness.dependencies.closePresentedArticleWebView(using: appState)

        #expect(appState.selectedDetailRoute == .article(article.id))
        #expect(appState.presentedWebViewRoute == nil)
    }

    @Test
    func shellActionEntryPointsSelectArticleOpensWebViewWhenDefaultReaderModeIsBrowser() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/default-reader-mode.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "default-browser-article",
            url: "https://example.com/articles/browser-mode",
            title: "Default Browser Mode Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/browser-mode/canonical"
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(defaultReaderMode: .browser)
        )
        try harness.saveModelContext()

        harness.dependencies.selectArticle(id: articleModel.id, using: appState)

        #expect(appState.selectedArticleID == articleModel.id)
        #expect(
            appState.selectedDetailRoute == .webView(
                ArticleWebViewRoute(
                    articleID: articleModel.id,
                    url: URL(string: "https://example.com/articles/browser-mode/canonical")!
                )
            )
        )
        #expect(
            appState.presentedWebViewRoute == ArticleWebViewRoute(
                articleID: articleModel.id,
                url: URL(string: "https://example.com/articles/browser-mode/canonical")!
            )
        )
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSourceTriggersReloadAfterFeedRefresh() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/shell-refresh-current.xml": .response(
                    statusCode: 304,
                    headers: ["ETag": "\"etag-shell-current\""],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/shell-refresh-current.xml"]).first)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let reloadIDAfterSourceSelection = appState.articleListReloadID

        let result = await harness.dependencies.refreshCurrentSource(using: appState)

        #expect(result?.status == .notModified)
        #expect(appState.articleListReloadID != reloadIDAfterSourceSelection)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshAfterAddingFeedRefreshesNewSourceSelectsItAndClosesModalFlow() async throws {
        let feedURL = "https://example.com/shell-refresh-added.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Shell Refreshed Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Shell Refreshed Article",
                            itemLink: "https://example.com/articles/shell-refreshed",
                            itemGUID: "shell-refreshed-article",
                            itemDescription: "Shell refreshed description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let appState = AppState()
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Shell Feed",
                kind: .rss
            )
        )

        harness.dependencies.showSourceManagement(using: appState)

        let result = await harness.dependencies.refreshAfterAddingFeed(id: feed.id, using: appState)
        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result?.status == .fetched)
        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Shell Refreshed Article")
    }

    @Test
    func shellActionCompletionHelpersCreateFolderReloadsSidebarAndKeepsModalFlowOpen() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()

        harness.dependencies.showInbox(using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishCreatingFolder(named: "Research", using: appState)

        #expect(appState.isPresentingSourceManagementScreen)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersMoveSourceReloadsSelectedFeedAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-move.xml",
                title: "Helper Move",
                kind: .rss
            )
        )

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishMovingSource(
            feedID: feed.id,
            previousFolderName: "News",
            updatedFolderName: "Tech",
            using: appState
        )

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersEditFolderRetargetsSelectionAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()

        harness.dependencies.showFolder(named: "News", using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishFolderEditing(
            previousName: "News",
            updatedFolderName: "World News",
            using: appState
        )

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersSaveFeedRefreshesSelectionAndDismissesModalFlow() async throws {
        let feedURL = "https://example.com/helper-save.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Helper Saved Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Helper Saved Article",
                            itemLink: "https://example.com/articles/helper-saved",
                            itemGUID: "helper-saved-article",
                            itemDescription: "Helper saved description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Helper Feed",
                kind: .rss
            )
        )

        harness.dependencies.showInbox(using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        let result = await harness.dependencies.finishSavingFeed(id: feed.id, using: appState)
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result?.status == .fetched)
        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Helper Saved Article")
    }

    @Test
    func shellActionCompletionHelpersUnsubscribeFeedKeepsCurrentSelectionWhenAnotherSourceIsRemoved() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let selectedFeed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-selected.xml",
                title: "Selected Feed",
                kind: .rss
            )
        )
        let removedFeedID = UUID()

        harness.dependencies.showFeed(id: selectedFeed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishUnsubscribingFeed(id: removedFeedID, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(selectedFeed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersDeleteFolderKeepsCurrentSelectionWhenAnotherFolderIsRemoved() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-delete-folder.xml",
                title: "Current Feed",
                kind: .rss
            )
        )

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishDeletingFolder(named: "Archived", using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionEntryPointsUnsubscribeFeedRemovesSourceAndResetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/unsubscribe.xml",
                title: "Unsubscribe Me",
                kind: .rss
            )
        )
        let sidebarReloadIDBeforeDelete = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.unsubscribeFeed(id: feed.id, using: appState)

        #expect(try harness.feedRepository.fetchFeed(id: feed.id) == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeDelete)
        #expect(appState.articleListReloadID != articleReloadIDBeforeDelete)
    }

    @Test
    func shellActionEntryPointsDeleteFolderUngroupsFeedsAndResetsFolderSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/folder-delete.xml",
                title: "Folder Feed",
                kind: .rss,
                folder: folder
            )
        )
        let sidebarReloadIDBeforeDelete = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.showFolder(named: "Tech", using: appState)
        harness.dependencies.deleteFolder(named: "Tech", using: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))

        #expect(try harness.folderRepository.fetchFolder(name: "Tech") == nil)
        #expect(persistedFeed.folder == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeDelete)
        #expect(appState.articleListReloadID != articleReloadIDBeforeDelete)
    }

    @Test
    func shellActionEntryPointsRefreshVisibleSourcesTriggersReloadAfterBatchRefresh() async throws {
        let urls = [
            "https://example.com/shell-refresh-all-1.xml",
            "https://example.com/shell-refresh-all-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        let result = await harness.dependencies.refreshVisibleSources(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesOnlyFolderFeeds() async throws {
        let urls = [
            "https://example.com/folder-refresh-1.xml",
            "https://example.com/folder-refresh-2.xml",
            "https://example.com/folder-refresh-3.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-2\""],
                body: ""
            ),
            urls[2]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-3\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: urls)
        let techFolder = Folder(name: "Tech")
        feeds[0].folder = techFolder
        feeds[1].folder = techFolder
        try harness.saveModelContext()
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID

        harness.dependencies.showFolder(named: "Tech", using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesAllFeedsForInbox() async throws {
        let urls = [
            "https://example.com/inbox-refresh-1.xml",
            "https://example.com/inbox-refresh-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)

        harness.dependencies.showInbox(using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
    }

    @Test
    func feedNormalizationKeepsFaviconLikeIconURLAndNormalizesIt() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com",
                iconURL: "HTTPS://CDN.EXAMPLE.COM/Favicon-32x32.png?cache=1#fragment"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/")
        #expect(normalized.metadata.iconURL == "https://cdn.example.com/Favicon-32x32.png?cache=1")
    }

    @Test
    func feedNormalizationRewritesLogoAssetToSiteFaviconWhenSiteURLIsKnown() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "https://example.com/news/",
                iconURL: "https://cdn.example.com/assets/header-logo.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func feedNormalizationKeepsOriginalIconURLWhenItCannotBuildSiteFaviconFallback() {
        let feed = ParsedFeedDTO(
            kind: .atom,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                iconURL: "https://cdn.example.com/assets/banner-logo.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://cdn.example.com/assets/banner-logo.png")
    }

    @Test
    func feedNormalizationUsesSiteFaviconWhenFeedDidNotProvideIconURL() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com/news"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/news")
        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func sourceIconCacheReturnsCachedDataWithoutSecondNetworkRequest() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary"
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient)

        let firstLoad = try await service.imageData(for: iconURL)
        let secondLoad = try await service.imageData(for: iconURL)

        #expect(firstLoad == Data("icon-binary".utf8))
        #expect(secondLoad == firstLoad)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test
    func sourceIconCacheSharesInFlightRequestBetweenConcurrentConsumers() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary",
                    delayNanoseconds: 50_000_000
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient)

        async let firstLoad = service.imageData(for: iconURL)
        async let secondLoad = service.imageData(for: iconURL)
        let (firstResult, secondResult) = try await (firstLoad, secondLoad)

        #expect(firstResult == secondResult)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
        #expect(await httpClient.maxConcurrentExecutions() == 1)
    }
}
