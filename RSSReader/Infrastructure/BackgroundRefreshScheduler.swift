import BackgroundTasks
import Foundation

struct BackgroundRefreshSchedulePlan: Equatable, Sendable {
    let identifier: String
    let earliestBeginDate: Date
}

enum BackgroundRefreshScheduleResult: Equatable, Sendable {
    case scheduled(BackgroundRefreshSchedulePlan)
    case cancelled
}

enum BackgroundRefreshScheduleFailureReason: String, Sendable {
    case backgroundRefreshUnavailable
    case notPermitted
    case tooManyPendingTaskRequests
    case immediateRunIneligible
    case unknown

    static func classify(_ error: Error) -> BackgroundRefreshScheduleFailureReason {
        let nsError = error as NSError
        guard nsError.domain == BGTaskScheduler.Error.errorDomain,
              let code = BGTaskScheduler.Error.Code(rawValue: nsError.code) else {
            return .unknown
        }

        return switch code {
        case .unavailable:
            BackgroundRefreshScheduleFailureReason.backgroundRefreshUnavailable
        case .notPermitted:
            BackgroundRefreshScheduleFailureReason.notPermitted
        case .tooManyPendingTaskRequests:
            BackgroundRefreshScheduleFailureReason.tooManyPendingTaskRequests
        case .immediateRunIneligible:
            BackgroundRefreshScheduleFailureReason.immediateRunIneligible
        @unknown default:
            BackgroundRefreshScheduleFailureReason.unknown
        }
    }
}

protocol BackgroundTaskRequestScheduling {
    func submit(_ taskRequest: BGTaskRequest) throws
    func cancel(taskRequestWithIdentifier identifier: String)
}

extension BGTaskScheduler: BackgroundTaskRequestScheduling {}

@MainActor
protocol BackgroundRefreshScheduling {
    @discardableResult
    func schedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshSchedulePlan?

    func cancel()

    @discardableResult
    func replace(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshScheduleResult
}

@MainActor
final class DefaultBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private let logger: Logging
    private let taskScheduler: any BackgroundTaskRequestScheduling
    private let taskIdentifier: String

    init(
        logger: Logging,
        taskScheduler: any BackgroundTaskRequestScheduling = BGTaskScheduler.shared,
        taskIdentifier: String = BackgroundRefreshTaskConfiguration.appRefreshIdentifier
    ) {
        self.logger = logger
        self.taskScheduler = taskScheduler
        self.taskIdentifier = taskIdentifier
    }

    @discardableResult
    func schedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date = .now
    ) throws -> BackgroundRefreshSchedulePlan? {
        guard let plan = Self.makeSchedulePlan(
            using: configuration,
            now: now,
            taskIdentifier: taskIdentifier
        ) else {
            logger.info("Skipped scheduling background app refresh because refreshIntervalPreference is manual")
            return nil
        }

        let request = BGAppRefreshTaskRequest(identifier: plan.identifier)
        request.earliestBeginDate = plan.earliestBeginDate

        do {
            try taskScheduler.submit(request)
            logger.info(
                "Scheduled background app refresh request identifier=\(plan.identifier) earliestBeginDate=\(plan.earliestBeginDate)"
            )
            return plan
        } catch {
            logger.error(
                "Failed to schedule background app refresh request identifier=\(plan.identifier) earliestBeginDate=\(plan.earliestBeginDate) error=\(error)"
            )
            throw error
        }
    }

    func cancel() {
        taskScheduler.cancel(taskRequestWithIdentifier: taskIdentifier)
        logger.info("Cancelled background app refresh request identifier=\(taskIdentifier)")
    }

    @discardableResult
    func replace(
        using configuration: BackgroundRefreshConfiguration,
        now: Date = .now
    ) throws -> BackgroundRefreshScheduleResult {
        cancel()

        if let plan = try schedule(using: configuration, now: now) {
            return .scheduled(plan)
        }

        return .cancelled
    }

    static func makeSchedulePlan(
        using configuration: BackgroundRefreshConfiguration,
        now: Date,
        taskIdentifier: String = BackgroundRefreshTaskConfiguration.appRefreshIdentifier
    ) -> BackgroundRefreshSchedulePlan? {
        guard let minimumInterval = configuration.policy.minimumInterval else {
            return nil
        }

        return BackgroundRefreshSchedulePlan(
            identifier: taskIdentifier,
            earliestBeginDate: now.addingTimeInterval(minimumInterval)
        )
    }
}
