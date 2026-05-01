import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Scheduler")
@MainActor
struct BackgroundRefreshSchedulerTests {
    @Test
    func backgroundRefreshSchedulerBuildsSchedulePlanFromAutomaticRefreshPolicy() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
            policy: BackgroundRefreshPolicy(preference: .hourly)
        )

        let plan = try #require(
            DefaultBackgroundRefreshScheduler.makeSchedulePlan(
                using: configuration,
                now: now
            )
        )

        #expect(plan.identifier == BackgroundRefreshTaskConfiguration.appRefreshIdentifier)
        #expect(plan.earliestBeginDate == now.addingTimeInterval(60 * 60))
    }

    @Test
    func backgroundRefreshSchedulerDoesNotBuildSchedulePlanForManualPolicy() {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )

        let plan = DefaultBackgroundRefreshScheduler.makeSchedulePlan(
            using: configuration,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(plan == nil)
    }

    @Test
    func backgroundRefreshSchedulerSchedulesAppRefreshRequestForAutomaticPolicy() throws {
        let taskScheduler = FakeBackgroundTaskScheduler()
        let logger = RecordingLogger()
        let scheduler = DefaultBackgroundRefreshScheduler(
            logger: logger,
            taskScheduler: taskScheduler
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .every6Hours),
            policy: BackgroundRefreshPolicy(preference: .every6Hours)
        )

        let plan = try #require(try scheduler.schedule(using: configuration, now: now))

        let request = try #require(taskScheduler.submittedAppRefreshRequests.last)
        #expect(plan.identifier == BackgroundRefreshTaskConfiguration.appRefreshIdentifier)
        #expect(plan.earliestBeginDate == now.addingTimeInterval(6 * 60 * 60))
        #expect(request.identifier == BackgroundRefreshTaskConfiguration.appRefreshIdentifier)
        #expect(request.earliestBeginDate == now.addingTimeInterval(6 * 60 * 60))
        #expect(
            logger.contains(
                "Scheduled background app refresh request identifier=\(BackgroundRefreshTaskConfiguration.appRefreshIdentifier)",
                level: .info
            )
        )
    }

    @Test
    func backgroundRefreshSchedulerSkipsSchedulingForManualPolicy() throws {
        let taskScheduler = FakeBackgroundTaskScheduler()
        let logger = RecordingLogger()
        let scheduler = DefaultBackgroundRefreshScheduler(
            logger: logger,
            taskScheduler: taskScheduler
        )
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )

        let plan = try scheduler.schedule(
            using: configuration,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(plan == nil)
        #expect(taskScheduler.submittedAppRefreshRequests.isEmpty)
        #expect(
            logger.contains(
                "Skipped scheduling background app refresh because refreshIntervalPreference is manual",
                level: .info
            )
        )
    }

    @Test
    func backgroundRefreshSchedulerCancelsPendingRequestByIdentifier() {
        let taskScheduler = FakeBackgroundTaskScheduler()
        let scheduler = DefaultBackgroundRefreshScheduler(
            logger: TestLogger(),
            taskScheduler: taskScheduler
        )

        scheduler.cancel()

        #expect(
            taskScheduler.cancelledIdentifiers
                == [BackgroundRefreshTaskConfiguration.appRefreshIdentifier]
        )
    }

    @Test
    func backgroundRefreshSchedulerReplacesPendingRequestForAutomaticPolicy() throws {
        let taskScheduler = FakeBackgroundTaskScheduler()
        let scheduler = DefaultBackgroundRefreshScheduler(
            logger: TestLogger(),
            taskScheduler: taskScheduler
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .daily),
            policy: BackgroundRefreshPolicy(preference: .daily)
        )

        let result = try scheduler.replace(using: configuration, now: now)

        let request = try #require(taskScheduler.submittedAppRefreshRequests.last)
        #expect(taskScheduler.cancelledIdentifiers == [BackgroundRefreshTaskConfiguration.appRefreshIdentifier])
        #expect(result == .scheduled(BackgroundRefreshSchedulePlan(
            identifier: BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
            earliestBeginDate: now.addingTimeInterval(24 * 60 * 60)
        )))
        #expect(request.earliestBeginDate == now.addingTimeInterval(24 * 60 * 60))
    }

    @Test
    func backgroundRefreshSchedulerReplacesPendingRequestWithCancellationForManualPolicy() throws {
        let taskScheduler = FakeBackgroundTaskScheduler()
        let scheduler = DefaultBackgroundRefreshScheduler(
            logger: TestLogger(),
            taskScheduler: taskScheduler
        )
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )

        let result = try scheduler.replace(
            using: configuration,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(taskScheduler.cancelledIdentifiers == [BackgroundRefreshTaskConfiguration.appRefreshIdentifier])
        #expect(taskScheduler.submittedAppRefreshRequests.isEmpty)
        #expect(result == .cancelled)
    }
}

private final class FakeBackgroundTaskScheduler: BackgroundTaskRequestScheduling {
    private(set) var submittedAppRefreshRequests: [BGAppRefreshTaskRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    func submit(_ taskRequest: BGTaskRequest) throws {
        guard let request = taskRequest as? BGAppRefreshTaskRequest else {
            Issue.record("Expected BGAppRefreshTaskRequest")
            return
        }

        submittedAppRefreshRequests.append(request)
    }

    func cancel(taskRequestWithIdentifier identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}
