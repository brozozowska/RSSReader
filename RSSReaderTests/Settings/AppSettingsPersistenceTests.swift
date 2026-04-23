import Foundation
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
}
