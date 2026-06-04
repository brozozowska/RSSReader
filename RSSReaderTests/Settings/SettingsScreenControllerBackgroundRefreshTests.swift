import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller / Background Refresh")
@MainActor
struct SettingsScreenControllerBackgroundRefreshTests {
    @Test
    func settingsScreenControllerPersistsUpdatedRefreshIntervalThroughBackgroundRefreshService() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let scheduler = SettingsRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: scheduler
        )
        let controller = SettingsScreenController()

        controller.loadSettings(dependencies: dependencies)
        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.daily.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        let replacedConfiguration = try #require(scheduler.lastReplacedConfiguration)
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(persistedSettings.refreshIntervalPreference == .daily)
        #expect(replacedConfiguration.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(replacedConfiguration.policy.minimumInterval == TimeInterval(24 * 60 * 60))
    }

    @Test
    func settingsScreenControllerCancelsBackgroundRefreshScheduleWhenRefreshPreferenceBecomesManual() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let scheduler = SettingsRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: scheduler
        )
        let controller = SettingsScreenController()
        let appSettingsService = try #require(dependencies.appSettingsService)

        _ = try appSettingsService.saveSettings(
            AppSettingsSnapshot(refreshIntervalPreference: .hourly),
            updatedAt: .distantPast
        )

        controller.loadSettings(dependencies: dependencies)
        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.manual.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        let replacedConfiguration = try #require(scheduler.lastReplacedConfiguration)
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .manual)
        #expect(persistedSettings.refreshIntervalPreference == .manual)
        #expect(replacedConfiguration.settingsSnapshot.refreshIntervalPreference == .manual)
        #expect(replacedConfiguration.policy.minimumInterval == nil)
    }

    @Test
    func settingsScreenControllerLogsTypedBackgroundRefreshScheduleFailureAfterRefreshIntervalUpdate() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let logger = RecordingLogger()
        let scheduler = SettingsRecordingBackgroundRefreshScheduler(
            replaceError: NSError(
                domain: BGTaskScheduler.Error.errorDomain,
                code: BGTaskScheduler.Error.Code.notPermitted.rawValue
            )
        )
        let dependencies = AppDependencies(
            logger: logger,
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: scheduler
        )
        let controller = SettingsScreenController()
        let repository = try #require(dependencies.appSettingsRepository)

        controller.loadSettings(dependencies: dependencies)
        controller.handlePickerOptionSelection(
            itemID: .refreshInterval,
            optionID: RefreshPreference.daily.rawValue,
            dependencies: dependencies
        )

        #expect(controller.applySettingsChanges(dependencies: dependencies))
        let persistedSettings = try repository.fetchOrCreate()
        #expect(persistedSettings.refreshIntervalPreference == .daily)
        #expect(controller.screenState.settingsSnapshot.refreshIntervalPreference == .daily)
        #expect(
            logger.contains(
                "Failed to replace background refresh schedule after applying settings changes",
                level: .error
            )
        )
        #expect(logger.contains("reason=notPermitted", level: .error))
    }
}
