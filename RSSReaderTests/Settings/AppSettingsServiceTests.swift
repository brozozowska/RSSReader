import Foundation
import Testing
@testable import RSSReader

@Suite("Settings / Services")
@MainActor
struct AppSettingsServiceTests {
    @Test
    func appSettingsServiceFetchesSnapshotFromRepository() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)

        _ = try repository.update(
            AppSettingsUpdate(
                articleOpeningMode: .safariView,
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                refreshIntervalPreference: .hourly,
                useiCloudSync: true,
                markAsReadOnOpen: false,
                askBeforeMarkingAllAsRead: false,
                showUnreadCountBadge: true,
                unreadArticleSortMode: .publishedAtAscending,
                articleRetentionPolicy: .oneWeek,
                articleBodyLinkOpeningPolicy: .externalBrowser,
                articleSourceLinkOpeningPolicy: .externalBrowser,
                readerAdjacentNavigationControlsMode: .swipesOnly,
                interfaceThemeMode: .black,
                updatedAt: .distantPast
            )
        )

        let snapshot = try service.fetchSettings()

        #expect(
            snapshot == AppSettingsSnapshot(
                articleOpeningMode: .safariView,
                selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
                refreshIntervalPreference: .hourly,
                useiCloudSync: true,
                markAsReadOnOpen: false,
                askBeforeMarkingAllAsRead: false,
                showUnreadCountBadge: true,
                unreadArticleSortMode: .publishedAtAscending,
                articleRetentionPolicy: .oneWeek,
                articleBodyLinkOpeningPolicy: .externalBrowser,
                articleSourceLinkOpeningPolicy: .externalBrowser,
                readerAdjacentNavigationControlsMode: .swipesOnly,
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
            articleOpeningMode: .safariView,
            selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
            refreshIntervalPreference: .every6Hours,
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

        let savedSnapshot = try service.saveSettings(
            editedSettings,
            updatedAt: .distantPast
        )
        let persistedSettings = try repository.fetchOrCreate()

        #expect(savedSnapshot == editedSettings)
        #expect(persistedSettings.articleOpeningMode == .safariView)
        #expect(persistedSettings.selectedSourcesFilterRawValue == SourcesFilter.unread.rawValue)
        #expect(persistedSettings.refreshIntervalPreference == .every6Hours)
        #expect(persistedSettings.useiCloudSync)
        #expect(persistedSettings.markAsReadOnOpen == false)
        #expect(persistedSettings.askBeforeMarkingAllAsRead == false)
        #expect(persistedSettings.showUnreadCountBadge)
        #expect(persistedSettings.unreadSortMode == .publishedAtDescending)
        #expect(persistedSettings.articleRetentionPolicy == .twoWeeks)
        #expect(persistedSettings.articleBodyLinkOpeningPolicy == .externalBrowser)
        #expect(persistedSettings.articleSourceLinkOpeningPolicy == .externalBrowser)
        #expect(persistedSettings.readerAdjacentNavigationControlsMode == .swipesOnly)
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
    func appDependenciesSkipsBackgroundRefreshWhenPreferenceIsManual() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .manual,
                updatedAt: .distantPast
            )
        )

        let result = await harness.dependencies.appActions.refreshFeedsForBackground()

        switch result {
        case .skippedManual(let configuration):
            #expect(configuration.policy.preference == .manual)
        case .executed, .failedToStart:
            Issue.record("Expected skipped manual background refresh result")
        }
    }

    @Test
    func appDependenciesRunsBackgroundRefreshWhenPreferenceIsAutomatic() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)

        _ = try repository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .hourly,
                updatedAt: .distantPast
            )
        )

        let result = await harness.dependencies.appActions.refreshFeedsForBackground()

        switch result {
        case .executed(let refreshResult):
            #expect(refreshResult.trigger == .background)
            #expect(refreshResult.batchResult.results.isEmpty == true)
            #expect(try service.fetchSettings().lastSourcesRefreshAt == nil)
        case .skippedManual, .failedToStart:
            Issue.record("Expected executed background refresh result")
        }
    }

    @Test
    func appDependenciesPersistsLastSourcesRefreshAfterManualAllSourcesRefresh() async throws {
        let feedURL = "https://example.com/manual-all-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Manual All Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Manual Refresh Article",
                            itemLink: "https://example.com/articles/manual-refresh",
                            itemGUID: "manual-refresh-article",
                            itemDescription: "Manual refresh article",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let service = try #require(harness.dependencies.appSettingsService)
        let feed = Feed(url: feedURL, title: "Manual All Feed")
        try harness.feedRepository.insert(feed)

        let result = try #require(await harness.dependencies.appActions.refreshAllFeeds())
        let snapshot = try service.fetchSettings()

        #expect(result.summary.fetchedCount == 1)
        #expect(snapshot.lastSourcesRefreshAt == result.finishedAt)
    }

    @Test
    func backgroundRefreshMaterializesArticlesInSharedLocalCacheUsedByQueryServices() async throws {
        let feedURL = "https://example.com/background-feed.xml"
        let articleExternalID = "background-article-1"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Background Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Materialized In Shared Cache",
                            itemLink: "https://example.com/articles/background-1",
                            itemGUID: articleExternalID,
                            itemDescription: "Background refresh article",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)
        let articleQueryService = try #require(harness.dependencies.articleQueryService)
        let feed = Feed(
            url: feedURL,
            title: "Background Feed"
        )
        try harness.feedRepository.insert(feed)

        _ = try repository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .hourly,
                updatedAt: .distantPast
            )
        )

        let result = await harness.dependencies.appActions.refreshFeedsForBackground()

        let executedResult: BackgroundFeedRefreshResult
        switch result {
        case .executed(let refreshResult):
            executedResult = refreshResult
        case .skippedManual, .failedToStart:
            Issue.record("Expected executed background refresh result")
            return
        }

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let inboxItems = try articleQueryService.fetchInboxListItems(
            sortMode: .publishedAtDescending,
            filter: .all
        )
        let visibleItem = try #require(inboxItems.first)

        #expect(executedResult.trigger == .background)
        #expect(executedResult.summary.totalFeedCount == 1)
        #expect(executedResult.summary.fetchedCount == 1)
        #expect(try service.fetchSettings().lastSourcesRefreshAt == executedResult.batchResult.finishedAt)
        #expect(persistedArticles.count == 1)
        #expect(persistedArticles.first?.title == "Materialized In Shared Cache")
        #expect(inboxItems.count == 1)
        #expect(visibleItem.feedID == feed.id)
        #expect(visibleItem.title == "Materialized In Shared Cache")
        #expect(visibleItem.articleExternalID == persistedArticles.first?.externalID)
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
    func appSettingsServiceUpdatesArticleRetentionPolicyThroughPatch() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let service = try #require(harness.dependencies.appSettingsService)

        let updatedSnapshot = try service.updateSettings(
            AppSettingsPatch(
                articleRetentionPolicy: .oneMonth,
                updatedAt: .distantPast
            )
        )
        let persistedSettings = try repository.fetchOrCreate()

        #expect(updatedSnapshot.articleRetentionPolicy == .oneMonth)
        #expect(persistedSettings.articleRetentionPolicy == .oneMonth)
    }

    @Test
    func applyingArticleRetentionSettingRunsCleanup() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let controller = SettingsScreenController()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/settings-retention.xml"]).first)
        let now = Date()
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "settings-retention-expired",
            url: "https://example.com/articles/settings-retention-expired",
            title: "Settings Retention Expired",
            archivedAt: now.addingTimeInterval(-(8 * 24 * 60 * 60))
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                articleRetentionPolicy: .oneMonth,
                updatedAt: .distantPast
            )
        )
        controller.loadSettings(dependencies: harness.dependencies)

        controller.handlePickerOptionSelection(
            itemID: .articleRetentionPolicy,
            optionID: ArticleRetentionPolicy.currentFeedOnly.rawValue,
            dependencies: harness.dependencies
        )
        let didApplyChanges = controller.applySettingsChanges(dependencies: harness.dependencies)
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(didApplyChanges)
        #expect(remainingArticles.isEmpty)
    }
}
