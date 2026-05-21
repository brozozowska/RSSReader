import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Settings / Persistence")
@MainActor
struct AppSettingsPersistenceTests {
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
        #expect(settings.sortMode == .publishedAtAscending)
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
            selectedSourcesFilterRawValue: SourcesFilter.unread.rawValue,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerSettings = AppSettings(
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        modelContext.insert(olderSettings)
        modelContext.insert(newerSettings)
        try modelContext.save()

        let repository = try #require(harness.dependencies.appSettingsRepository)
        let canonicalSettings = try repository.fetchOrCreate()
        let persistedSettings = try modelContext.fetch(FetchDescriptor<AppSettings>())

        #expect(canonicalSettings.selectedSourcesFilterRawValue == SourcesFilter.starred.rawValue)
        #expect(persistedSettings.count == 1)
        #expect(persistedSettings.first?.singletonKey == AppSettings.singletonKeyValue)
    }
}
