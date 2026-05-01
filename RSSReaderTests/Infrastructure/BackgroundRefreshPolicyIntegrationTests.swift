import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Policy Integration")
@MainActor
struct BackgroundRefreshPolicyIntegrationTests {
    @Test
    func appDependenciesReplaceBackgroundRefreshScheduleLoadsConfigurationFromBackgroundRefreshService() throws {
        let recordingScheduler = RecordingBackgroundRefreshScheduler()
        let dependencies = try makeDependencies(backgroundRefreshScheduler: recordingScheduler)
        let appSettingsService = try #require(dependencies.appSettingsService)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try appSettingsService.updateSettings(
            AppSettingsPatch(
                refreshIntervalPreference: .every6Hours,
                updatedAt: now
            )
        )

        let result = try dependencies.replaceBackgroundRefreshSchedule(now: now)

        let configuration = try #require(recordingScheduler.lastReplacedConfiguration)
        #expect(configuration.settingsSnapshot.refreshIntervalPreference == .every6Hours)
        #expect(configuration.policy.preference == .every6Hours)
        #expect(configuration.policy.minimumInterval == TimeInterval(6 * 60 * 60))
        #expect(result == .scheduled(BackgroundRefreshSchedulePlan(
            identifier: BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
            earliestBeginDate: now.addingTimeInterval(6 * 60 * 60)
        )))
    }

    @Test
    func appDependenciesReplaceBackgroundRefreshScheduleUsesManualConfigurationAsCancellationPath() throws {
        let recordingScheduler = RecordingBackgroundRefreshScheduler()
        let dependencies = try makeDependencies(backgroundRefreshScheduler: recordingScheduler)
        let appSettingsService = try #require(dependencies.appSettingsService)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try appSettingsService.updateSettings(
            AppSettingsPatch(
                refreshIntervalPreference: .manual,
                updatedAt: now
            )
        )

        let result = try dependencies.replaceBackgroundRefreshSchedule(now: now)

        let configuration = try #require(recordingScheduler.lastReplacedConfiguration)
        #expect(configuration.settingsSnapshot.refreshIntervalPreference == .manual)
        #expect(configuration.policy.preference == .manual)
        #expect(configuration.policy.minimumInterval == nil)
        #expect(result == .cancelled)
    }

    @Test
    func appDependenciesReplaceBackgroundRefreshScheduleLogsWhenBackgroundRefreshServiceIsUnavailable() throws {
        let logger = RecordingLogger()
        let recordingScheduler = RecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: logger,
            backgroundRefreshScheduler: recordingScheduler
        )

        let result = try dependencies.replaceBackgroundRefreshSchedule(
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(result == nil)
        #expect(recordingScheduler.lastReplacedConfiguration == nil)
        #expect(
            logger.contains(
                "Background refresh service is unavailable for schedule replacement",
                level: .error
            )
        )
    }

    private func makeDependencies(
        backgroundRefreshScheduler: any BackgroundRefreshScheduling
    ) throws -> AppDependencies {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        return AppDependencies(
            logger: TestLogger(),
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: backgroundRefreshScheduler
        )
    }
}

@MainActor
private final class RecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private(set) var lastReplacedConfiguration: BackgroundRefreshConfiguration?

    func schedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshSchedulePlan? {
        lastReplacedConfiguration = configuration
        return DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now)
    }

    func cancel() {}

    func replace(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshScheduleResult {
        lastReplacedConfiguration = configuration

        if let plan = DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now) {
            return .scheduled(plan)
        }

        return .cancelled
    }
}
