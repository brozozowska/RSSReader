import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppComposition Background Refresh Bootstrap")
@MainActor
struct AppCompositionBackgroundRefreshBootstrapTests {
    @Test
    func appCompositionSchedulesBackgroundRefreshOnLaunchFromPersistedConfiguration() throws {
        let scheduler = LaunchRecordingBackgroundRefreshScheduler()
        let dependencies = try makeDependencies(
            logger: TestLogger(),
            backgroundRefreshScheduler: scheduler
        )
        let appSettingsService = try #require(dependencies.appSettingsService)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try appSettingsService.updateSettings(
            AppSettingsPatch(
                refreshIntervalPreference: .hourly,
                updatedAt: now
            )
        )

        AppComposition.scheduleBackgroundRefreshOnLaunch(using: dependencies)

        let configuration = try #require(scheduler.lastReplacedConfiguration)
        #expect(configuration.settingsSnapshot.refreshIntervalPreference == .hourly)
        #expect(configuration.policy.minimumInterval == TimeInterval(60 * 60))
    }

    @Test
    func appCompositionCancelsBackgroundRefreshOnLaunchForManualPolicy() throws {
        let scheduler = LaunchRecordingBackgroundRefreshScheduler()
        let dependencies = try makeDependencies(
            logger: TestLogger(),
            backgroundRefreshScheduler: scheduler
        )
        let appSettingsService = try #require(dependencies.appSettingsService)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try appSettingsService.updateSettings(
            AppSettingsPatch(
                refreshIntervalPreference: .manual,
                updatedAt: now
            )
        )

        AppComposition.scheduleBackgroundRefreshOnLaunch(using: dependencies)

        let configuration = try #require(scheduler.lastReplacedConfiguration)
        #expect(configuration.settingsSnapshot.refreshIntervalPreference == .manual)
        #expect(configuration.policy.minimumInterval == nil)
    }

    @Test
    func appCompositionLogsLaunchSchedulingFailure() throws {
        let logger = RecordingLogger()
        let scheduler = FailingBackgroundRefreshScheduler()
        let dependencies = try makeDependencies(
            logger: logger,
            backgroundRefreshScheduler: scheduler
        )

        AppComposition.scheduleBackgroundRefreshOnLaunch(using: dependencies)

        #expect(
            logger.contains(
                "Failed to configure background refresh schedule on app launch",
                level: .error
            )
        )
    }

    private func makeDependencies(
        logger: Logging,
        backgroundRefreshScheduler: any BackgroundRefreshScheduling
    ) throws -> AppDependencies {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        return AppDependencies(
            logger: logger,
            httpClient: harness.httpClient,
            feedFetcher: harness.dependencies.feedFetcher,
            modelContainer: harness.modelContainer,
            backgroundRefreshScheduler: backgroundRefreshScheduler
        )
    }
}

@MainActor
private final class FailingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    struct SchedulerFailure: Error {}

    func schedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshSchedulePlan? {
        throw SchedulerFailure()
    }

    func cancel() {}

    func replace(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshScheduleResult {
        throw SchedulerFailure()
    }
}

@MainActor
private final class LaunchRecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
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
