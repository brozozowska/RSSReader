import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Settings / Persistence")
@MainActor
struct AppSettingsPersistenceTests {
    @Test
    func sidebarArticleFilterPersistencePolicyRestoresPersistedFilterFromSettingsRawValue() {
        let settings = AppSettings(selectedSourcesFilterRawValue: SidebarArticleFilter.starred.rawValue)

        let restoredFilter = SidebarArticleFilterPersistencePolicy.restoredFilter(
            from: settings.selectedSourcesFilterRawValue
        )

        #expect(restoredFilter == .starred)
    }

    @Test
    func sidebarArticleFilterPersistencePolicyFallsBackToAllItemsWhenRawValueIsMissing() {
        let settings = AppSettings(selectedSourcesFilterRawValue: nil)

        #expect(
            SidebarArticleFilterPersistencePolicy.restoredFilter(
                from: settings.selectedSourcesFilterRawValue
            ) == .allItems
        )
    }

    @Test
    func sidebarArticleFilterPersistencePolicyBuildsSettingsPatchForSelectedFilter() {
        let starredUpdate = SidebarArticleFilterPersistencePolicy.makeSettingsPatch(
            for: .starred,
            updatedAt: .distantPast
        )
        let unreadUpdate = SidebarArticleFilterPersistencePolicy.makeSettingsPatch(
            for: .unread,
            updatedAt: .distantPast
        )

        #expect(starredUpdate.selectedSourcesFilterRawValue == SidebarArticleFilter.starred.rawValue)
        #expect(unreadUpdate.selectedSourcesFilterRawValue == SidebarArticleFilter.unread.rawValue)
    }

    @Test
    func appSettingsDefaultsUseSelectedSourcesFilterRawValueAsPersistedSidebarArticleFilterState() {
        let settings = AppSettings()

        #expect(settings.selectedSourcesFilterRawValue == SidebarArticleFilter.allItems.rawValue)
        #expect(settings.askBeforeMarkingAllAsRead)
        #expect(settings.unreadSortMode == .publishedAtDescending)
        #expect(settings.articleBodyLinkOpeningPolicy == .inAppBrowser)
        #expect(settings.articleSourceLinkOpeningPolicy == .inAppBrowser)
        #expect(settings.readerAdjacentNavigationControlsMode == .swipesAndToolbarControls)
        #expect(settings.interfaceThemeMode == .automaticLightDark)
        #expect(settings.showUnreadCountBadge == false)
    }

    @Test
    func appSettingsRepositoryPersistsSelectedSourcesFilterRawValue() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                selectedSourcesFilterRawValue: SidebarArticleFilter.starred.rawValue,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.selectedSourcesFilterRawValue == SidebarArticleFilter.starred.rawValue)
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
    func appSettingsRepositoryPersistsReaderAdjacentNavigationControlsMode() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                readerAdjacentNavigationControlsMode: .toolbarControlsOnly,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.readerAdjacentNavigationControlsMode == .toolbarControlsOnly)
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
    func appSettingsRepositoryPersistsUnreadCountBadgePreference() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)

        _ = try repository.update(
            AppSettingsUpdate(
                showUnreadCountBadge: true,
                updatedAt: .distantPast
            )
        )

        let settings = try repository.fetchOrCreate()

        #expect(settings.showUnreadCountBadge)
    }

    @Test
    func appSettingsRepositoryCollapsesDuplicateSingletonRowsWithoutSchemaLevelUniqueness() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let modelContext = harness.modelContainer.mainContext
        let olderSettings = AppSettings(
            selectedSourcesFilterRawValue: SidebarArticleFilter.unread.rawValue,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerSettings = AppSettings(
            selectedSourcesFilterRawValue: SidebarArticleFilter.starred.rawValue,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        modelContext.insert(olderSettings)
        modelContext.insert(newerSettings)
        try modelContext.save()

        let repository = try #require(harness.dependencies.appSettingsRepository)
        let canonicalSettings = try repository.fetchOrCreate()
        let persistedSettings = try modelContext.fetch(FetchDescriptor<AppSettings>())

        #expect(canonicalSettings.selectedSourcesFilterRawValue == SidebarArticleFilter.starred.rawValue)
        #expect(persistedSettings.count == 1)
        #expect(persistedSettings.first?.singletonKey == AppSettings.singletonKeyValue)
    }
}
