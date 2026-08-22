import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Settings Screen / Controller / Side Effects")
@MainActor
struct SettingsScreenControllerSideEffectsTests {
    @Test
    func applyingUnreadSortOrderRequestsArticleListReload() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SettingsScreenController()
        let appState = AppState()
        controller.loadSettings(dependencies: harness.dependencies)
        let reloadIDBeforeChange = appState.articleListReloadID

        controller.handlePickerOptionSelection(
            itemID: .unreadArticleSortOrder,
            optionID: UnreadArticleSortOrder.oldestFirst.rawValue,
            dependencies: harness.dependencies
        )

        #expect(
            controller.applySettingsChanges(
                dependencies: harness.dependencies,
                appState: appState
            )
        )
        #expect(appState.articleListReloadID != reloadIDBeforeChange)
    }

    @Test
    func settingsScreenControllerClearsArticleImageCacheWithoutChangingSettings() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let settingsService = try #require(harness.dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let imageURL = try #require(URL(string: "https://example.com/article-image.png"))
        let initialSnapshot = try settingsService.fetchSettings()

        try await ArticleImageDiskCache.shared.removeAll()
        try await ArticleImageDiskCache.shared.insert(Data([1, 2, 3]), for: imageURL)
        ArticleImageMemoryCache.shared.insert(UIImage(), for: imageURL)
        controller.screenState.applyArticleImageCacheAvailability(true)

        await controller.handleButtonTap(
            itemID: .clearArticleImageCache,
            dependencies: harness.dependencies
        )

        #expect(ArticleImageMemoryCache.shared.hasImages == false)
        #expect(try await ArticleImageDiskCache.shared.isEmpty())
        #expect(controller.screenState.hasArticleImageCache == false)
        #expect(try settingsService.fetchSettings() == initialSnapshot)
    }

    @Test
    func settingsScreenControllerClearsFeedIconCacheAndRequestsIconResetWithoutChangingSettings() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feedIconCache = SettingsRecordingFeedIconCache(hasCachedDataValue: true)
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            feedIconCache: feedIconCache,
            modelContainer: harness.modelContainer,
            unreadAppIconBadgeService: NoOpUnreadAppIconBadgeService()
        )
        let settingsService = try #require(dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let appState = AppState()
        let resetIDBeforeClear = appState.feedIconCacheResetID
        let initialSnapshot = try settingsService.fetchSettings()

        await controller.refreshFeedIconCacheAvailability(dependencies: dependencies)
        #expect(controller.screenState.hasFeedIconCache)

        await controller.handleButtonTap(
            itemID: .clearFeedIconCache,
            dependencies: dependencies,
            appState: appState
        )

        #expect(await feedIconCache.removeAllCallCount() == 1)
        #expect(controller.screenState.hasFeedIconCache == false)
        #expect(appState.feedIconCacheResetID != resetIDBeforeClear)
        #expect(try settingsService.fetchSettings() == initialSnapshot)
    }

    @Test
    func settingsScreenControllerClearsFeedIconMemoryAndDiskOwners() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let memoryCache = FeedIconMemoryCache(countLimit: 2)
        let diskCache = FeedIconDiskCache(directoryURL: directoryURL, capacityLimit: 1_024)
        let feedIconCache = FeedIconCacheService(cache: memoryCache, diskCache: diskCache)
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            feedIconCache: feedIconCache,
            modelContainer: harness.modelContainer,
            unreadAppIconBadgeService: NoOpUnreadAppIconBadgeService()
        )
        let settingsService = try #require(dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let appState = AppState()
        let resetIDBeforeClear = appState.feedIconCacheResetID
        let initialSnapshot = try settingsService.fetchSettings()
        let memoryOnlyURL = try #require(URL(string: "https://example.com/memory-only-icon.png"))
        let diskOnlyURL = try #require(URL(string: "https://example.com/disk-only-icon.png"))

        await memoryCache.insert(Data("memory".utf8), for: memoryOnlyURL)
        try await diskCache.insert(Data("disk".utf8), for: diskOnlyURL)
        await controller.refreshFeedIconCacheAvailability(dependencies: dependencies)

        await controller.handleButtonTap(
            itemID: .clearFeedIconCache,
            dependencies: dependencies,
            appState: appState
        )

        #expect(await memoryCache.cachedEntryCount() == 0)
        #expect(try await diskCache.isEmpty())
        #expect(try await feedIconCache.hasCachedData() == false)
        #expect(controller.screenState.hasFeedIconCache == false)
        #expect(appState.feedIconCacheResetID != resetIDBeforeClear)
        #expect(try settingsService.fetchSettings() == initialSnapshot)
    }

    @Test
    func settingsScreenControllerPurgesArchivedArticlesAndReloadsListsWithoutChangingSettings() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let settingsService = try #require(harness.dependencies.appSettingsService)
        let feed = try harness.insertFeeds(urls: ["https://example.com/feed.xml"])[0]
        let archivedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "archived",
            url: "https://example.com/archived",
            title: "Archived",
            archivedAt: Date(timeIntervalSince1970: 1)
        )
        let starredArchivedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "starred-archived",
            url: "https://example.com/starred-archived",
            title: "Starred Archived",
            archivedAt: Date(timeIntervalSince1970: 2)
        )
        let currentArticle = try harness.insertArticle(
            feed: feed,
            externalID: "current",
            url: "https://example.com/current",
            title: "Current"
        )
        _ = try harness.articleStateService.toggleStarred(article: starredArchivedArticle)
        let controller = SettingsScreenController()
        let appState = AppState()
        let articleListReloadIDBeforePurge = appState.articleListReloadID
        let sidebarReloadIDBeforePurge = appState.sidebarReloadID
        let initialSnapshot = try settingsService.fetchSettings()

        controller.refreshArchivedArticlesAvailability(dependencies: harness.dependencies)
        #expect(controller.screenState.hasArchivedArticles)

        await controller.handleButtonTap(
            itemID: .purgeArchivedArticles,
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(try harness.articleRepository.fetchArticle(id: archivedArticle.id) == nil)
        #expect(try harness.articleRepository.fetchArticle(id: starredArchivedArticle.id) != nil)
        #expect(try harness.articleRepository.fetchArticle(id: currentArticle.id) != nil)
        #expect(controller.screenState.hasArchivedArticles == false)
        #expect(appState.articleListReloadID != articleListReloadIDBeforePurge)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforePurge)
        #expect(try settingsService.fetchSettings() == initialSnapshot)
    }

    @Test
    func settingsScreenControllerAppliesBadgePreferenceAndRefreshScheduleWithoutChangingUnrelatedSettings() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let badgeService = SettingsRecordingUnreadAppIconBadgeService()
        let scheduler = SettingsRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: scheduler,
            unreadAppIconBadgeService: badgeService
        )
        let settingsService = try #require(dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let initialSnapshot = AppSettingsSnapshot(
            articleOpeningMode: .safariView,
            refreshIntervalPreference: .manual,
            useiCloudSync: false,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: true,
            showUnreadCountBadge: false,
            unreadArticleSortMode: .publishedAtAscending,
            articleRetentionPolicy: .oneMonth,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            readerAdjacentNavigationControlsMode: .toolbarControlsOnly,
            interfaceThemeMode: .dark
        )
        _ = try settingsService.saveSettings(initialSnapshot, updatedAt: .distantPast)

        controller.loadSettings(dependencies: dependencies)
        controller.handleToggleValueChange(
            itemID: .showUnreadCountBadge,
            isOn: true,
            dependencies: dependencies
        )
        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.hourly.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        await waitForBadgePreferences([true], in: badgeService)
        let persistedSnapshot = try settingsService.fetchSettings()
        let replacedConfiguration = try #require(scheduler.lastReplacedConfiguration)

        #expect(badgeService.appliedPreferences == [true])
        #expect(replacedConfiguration.settingsSnapshot.refreshIntervalPreference == .hourly)
        #expect(replacedConfiguration.policy.minimumInterval == TimeInterval(60 * 60))
        #expect(persistedSnapshot.showUnreadCountBadge)
        #expect(persistedSnapshot.refreshIntervalPreference == .hourly)
        #expect(persistedSnapshot.articleOpeningMode == initialSnapshot.articleOpeningMode)
        #expect(persistedSnapshot.useiCloudSync == initialSnapshot.useiCloudSync)
        #expect(persistedSnapshot.markAsReadOnOpen == initialSnapshot.markAsReadOnOpen)
        #expect(persistedSnapshot.articleRetentionPolicy == initialSnapshot.articleRetentionPolicy)
        #expect(persistedSnapshot.interfaceThemeMode == initialSnapshot.interfaceThemeMode)
    }

    @Test
    func applyingStricterRetentionReloadsSidebarAndArticleListAndRefreshesBadge() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let badgeService = SettingsRecordingUnreadAppIconBadgeService()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            unreadAppIconBadgeService: badgeService
        )
        let settingsService = try #require(dependencies.appSettingsService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/settings-retention.xml"]).first)
        let now = Date.now
        let sourceDate = now.addingTimeInterval(-(14 * 24 * 60 * 60))
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "expired-current",
            url: "https://example.com/expired-current",
            title: "Expired Current",
            publishedAt: sourceDate,
            fetchedAt: sourceDate,
            createdAt: sourceDate
        )
        _ = try settingsService.updateSettings(
            AppSettingsPatch(articleRetentionPolicy: .oneMonth, updatedAt: .distantPast)
        )
        let controller = SettingsScreenController()
        let appState = AppState()
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        controller.loadSettings(dependencies: dependencies, appState: appState)
        controller.handlePickerOptionSelection(
            itemID: .articleRetentionPolicy,
            optionID: ArticleRetentionPolicy.oneWeek.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies, appState: appState))
        await waitForBadgeRefreshCount(1, in: badgeService)

        #expect(try harness.articleRepository.fetchArticle(id: article.id) == nil)
        #expect(appState.sidebarReloadID != initialSidebarReloadID)
        #expect(appState.articleListReloadID != initialArticleListReloadID)
        #expect(badgeService.refreshBadgeCountCallCount == 1)
    }

    @Test
    func settingsScreenControllerPersistsICloudSyncBootPreferenceTransitionWithoutChangingUnrelatedSettings() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let syncBootstrapPreferenceStore = SettingsRecordingSyncBootstrapPreferenceStore()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            syncBootstrapPreferenceStore: syncBootstrapPreferenceStore,
            unreadAppIconBadgeService: NoOpUnreadAppIconBadgeService()
        )
        let settingsService = try #require(dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let initialSnapshot = AppSettingsSnapshot(
            articleOpeningMode: .safariView,
            refreshIntervalPreference: .daily,
            useiCloudSync: false,
            markAsReadOnOpen: false,
            askBeforeMarkingAllAsRead: false,
            showUnreadCountBadge: true,
            unreadArticleSortMode: .publishedAtAscending,
            articleRetentionPolicy: .twoWeeks,
            articleBodyLinkOpeningPolicy: .externalBrowser,
            articleSourceLinkOpeningPolicy: .externalBrowser,
            readerAdjacentNavigationControlsMode: .swipesOnly,
            interfaceThemeMode: .black
        )
        _ = try settingsService.saveSettings(initialSnapshot, updatedAt: .distantPast)

        controller.loadSettings(dependencies: dependencies)
        controller.handleToggleValueChange(
            itemID: .useICloudSync,
            isOn: true,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        let persistedSnapshot = try settingsService.fetchSettings()

        #expect(syncBootstrapPreferenceStore.savedPreferences == [.enabled])
        #expect(syncBootstrapPreferenceStore.currentBootPreference() == .enabled)
        #expect(persistedSnapshot.useiCloudSync)
        #expect(persistedSnapshot.articleOpeningMode == initialSnapshot.articleOpeningMode)
        #expect(persistedSnapshot.refreshIntervalPreference == initialSnapshot.refreshIntervalPreference)
        #expect(persistedSnapshot.markAsReadOnOpen == initialSnapshot.markAsReadOnOpen)
        #expect(persistedSnapshot.askBeforeMarkingAllAsRead == initialSnapshot.askBeforeMarkingAllAsRead)
        #expect(persistedSnapshot.showUnreadCountBadge == initialSnapshot.showUnreadCountBadge)
        #expect(persistedSnapshot.articleRetentionPolicy == initialSnapshot.articleRetentionPolicy)
        #expect(persistedSnapshot.interfaceThemeMode == initialSnapshot.interfaceThemeMode)
    }
}

private actor SettingsRecordingFeedIconCache: FeedIconCaching {
    private var hasCachedDataValue: Bool
    private var removeAllCount = 0

    init(hasCachedDataValue: Bool = false) {
        self.hasCachedDataValue = hasCachedDataValue
    }

    func cachedImageData(for url: URL) async throws -> Data? {
        nil
    }

    func storeImageData(_ data: Data, for url: URL) async throws {
        hasCachedDataValue = true
    }

    func hasCachedData() async throws -> Bool {
        hasCachedDataValue
    }

    func removeAllCachedData() async throws {
        removeAllCount += 1
        hasCachedDataValue = false
    }

    func removeAllCallCount() -> Int {
        removeAllCount
    }
}

@MainActor
private final class SettingsRecordingUnreadAppIconBadgeService: UnreadAppIconBadgeServicing {
    private(set) var appliedPreferences: [Bool] = []
    private(set) var refreshBadgeCountCallCount = 0

    func refreshBadgeCount() async {
        refreshBadgeCountCallCount += 1
    }

    func applyBadgePreference(isEnabled: Bool) async {
        appliedPreferences.append(isEnabled)
    }
}

private final class SettingsRecordingSyncBootstrapPreferenceStore: AppSyncBootstrapPreferenceStoring {
    private var bootPreference: AppSyncBootPreference?
    private(set) var savedPreferences: [AppSyncBootPreference] = []

    func currentBootPreference() -> AppSyncBootPreference? {
        bootPreference
    }

    func saveBootPreference(_ preference: AppSyncBootPreference) {
        bootPreference = preference
        savedPreferences.append(preference)
    }
}

@MainActor
private func waitForBadgePreferences(
    _ expectedPreferences: [Bool],
    in badgeService: SettingsRecordingUnreadAppIconBadgeService
) async {
    for _ in 0..<20 {
        if badgeService.appliedPreferences == expectedPreferences {
            return
        }
        await Task.yield()
    }
}

@MainActor
private func waitForBadgeRefreshCount(
    _ expectedCount: Int,
    in badgeService: SettingsRecordingUnreadAppIconBadgeService
) async {
    for _ in 0..<20 {
        if badgeService.refreshBadgeCountCallCount == expectedCount {
            return
        }
        await Task.yield()
    }
}
