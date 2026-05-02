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

        _ = try repository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .hourly,
                updatedAt: .distantPast
            )
        )

        let result = await harness.dependencies.refreshFeedsForBackground()

        switch result {
        case .executed(let refreshResult):
            #expect(refreshResult.trigger == .background)
            #expect(refreshResult.batchResult.results.isEmpty == true)
        case .skippedManual, .failedToStart:
            Issue.record("Expected executed background refresh result")
        }
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
}
