import Foundation
import Testing
import UIKit
@testable import RSSReader

@Suite("Settings Screen / Controller / Side Effects")
@MainActor
struct SettingsScreenControllerSideEffectsTests {
    @Test
    func settingsScreenControllerClearsArticleImageCacheWithoutChangingSettings() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let settingsService = try #require(harness.dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let imageURL = try #require(URL(string: "https://example.com/article-image.png"))
        let initialSnapshot = try settingsService.fetchSettings()

        ArticleImageMemoryCache.shared.insert(UIImage(), for: imageURL)
        controller.screenState.applyArticleImageCacheAvailability(true)

        await controller.handleButtonTap(
            itemID: .clearArticleImageCache,
            dependencies: harness.dependencies
        )

        #expect(ArticleImageMemoryCache.shared.hasImages == false)
        #expect(controller.screenState.hasArticleImageCache == false)
        #expect(try settingsService.fetchSettings() == initialSnapshot)
    }

    @Test
    func settingsScreenControllerClearsSourceIconCacheAndRequestsIconResetWithoutChangingSettings() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let sourceIconCache = SettingsRecordingSourceIconCache(hasCachedDataValue: true)
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            sourceIconCache: sourceIconCache,
            modelContainer: harness.modelContainer,
            unreadAppIconBadgeService: NoOpUnreadAppIconBadgeService()
        )
        let settingsService = try #require(dependencies.appSettingsService)
        let controller = SettingsScreenController()
        let appState = AppState()
        let resetIDBeforeClear = appState.sourceIconCacheResetID
        let initialSnapshot = try settingsService.fetchSettings()

        await controller.refreshSourceIconCacheAvailability(dependencies: dependencies)
        #expect(controller.screenState.hasSourceIconCache)

        await controller.handleButtonTap(
            itemID: .clearSourceIconCache,
            dependencies: dependencies,
            appState: appState
        )

        #expect(await sourceIconCache.removeAllCallCount() == 1)
        #expect(controller.screenState.hasSourceIconCache == false)
        #expect(appState.sourceIconCacheResetID != resetIDBeforeClear)
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

private actor SettingsRecordingSourceIconCache: SourceIconCaching {
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

    func imageData(for url: URL) async throws -> Data {
        Data()
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

    func refreshBadgeCount() async {}

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
