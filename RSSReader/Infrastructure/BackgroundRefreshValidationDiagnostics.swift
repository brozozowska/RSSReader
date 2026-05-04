import Foundation

enum BackgroundRefreshValidationStage: String, Equatable, Sendable {
    case registration
    case scheduling
    case executionStart
    case executionCancellation
    case executionCompletion
    case postRunReschedule
}

struct BackgroundRefreshValidationDiagnosticsSnapshot: Equatable, Sendable {
    var registration: BackgroundRefreshRegistrationDiagnostics?
    var scheduling: BackgroundRefreshSchedulingDiagnostics?
    var executionStart: BackgroundRefreshExecutionStartDiagnostics?
    var executionCancellation: BackgroundRefreshExecutionCancellationDiagnostics?
    var executionCompletion: BackgroundRefreshExecutionCompletionDiagnostics?
    var postRunReschedule: BackgroundRefreshPostRunRescheduleDiagnostics?
}

struct BackgroundRefreshRegistrationDiagnostics: Equatable, Sendable {
    let identifier: String
    let handlerDescription: String
}

enum BackgroundRefreshSchedulingTrigger: String, Equatable, Sendable {
    case launchBootstrap
}

enum BackgroundRefreshSchedulingOutcome: String, Equatable, Sendable {
    case scheduled
    case cancelled
    case failed
    case skippedDuplicateLaunchAttempt
    case unavailable
}

struct BackgroundRefreshSchedulingDiagnostics: Equatable, Sendable {
    let trigger: BackgroundRefreshSchedulingTrigger
    let outcome: BackgroundRefreshSchedulingOutcome
    let identifier: String?
    let earliestBeginDate: Date?
    let failureReason: BackgroundRefreshScheduleFailureReason?
}

struct BackgroundRefreshExecutionStartDiagnostics: Equatable, Sendable {
    let started = true
}

struct BackgroundRefreshExecutionCancellationDiagnostics: Equatable, Sendable {
    let receivedSystemCancellation = true
}

enum BackgroundRefreshExecutionCompletionKind: String, Equatable, Sendable {
    case success
    case partialFailure
    case totalFailure
    case skippedManual
    case failedToStart
    case cancelled
}

struct BackgroundRefreshExecutionCompletionDiagnostics: Equatable, Sendable {
    let kind: BackgroundRefreshExecutionCompletionKind
    let refreshIntervalPreference: RefreshPreference?
    let partialResultAvailable: Bool?
    let totalFeedCount: Int?
    let fetchedCount: Int?
    let notModifiedCount: Int?
    let failedCount: Int?
    let cancelledCount: Int?
    let networkFailureCount: Int?
    let likelyNoConnectivityHeuristic: Bool?
    let duration: TimeInterval?
    let failureReason: String?
}

enum BackgroundRefreshPostRunRescheduleOutcome: String, Equatable, Sendable {
    case scheduled
    case cancelled
    case failed
    case serviceUnavailable
}

struct BackgroundRefreshPostRunRescheduleDiagnostics: Equatable, Sendable {
    let outcome: BackgroundRefreshPostRunRescheduleOutcome
    let identifier: String?
    let earliestBeginDate: Date?
    let failureReason: BackgroundRefreshScheduleFailureReason?
}

@MainActor
protocol BackgroundRefreshValidationDiagnosticsReporting {
    func currentSnapshot() -> BackgroundRefreshValidationDiagnosticsSnapshot
    func reportRegistrationConfigured(identifier: String, handlerDescription: String)
    func reportLaunchScheduling(
        outcome: BackgroundRefreshSchedulingOutcome,
        identifier: String?,
        earliestBeginDate: Date?,
        failureReason: BackgroundRefreshScheduleFailureReason?
    )
    func reportExecutionStarted()
    func reportExecutionCancellationReceived()
    func reportExecutionCompleted(_ diagnostics: BackgroundRefreshExecutionCompletionDiagnostics)
    func reportPostRunReschedule(
        outcome: BackgroundRefreshPostRunRescheduleOutcome,
        identifier: String?,
        earliestBeginDate: Date?,
        failureReason: BackgroundRefreshScheduleFailureReason?
    )
}

@MainActor
final class DefaultBackgroundRefreshValidationDiagnosticsReporter:
    BackgroundRefreshValidationDiagnosticsReporting
{
    private let logger: Logging
    private var snapshot = BackgroundRefreshValidationDiagnosticsSnapshot()

    init(logger: Logging) {
        self.logger = logger
    }

    func currentSnapshot() -> BackgroundRefreshValidationDiagnosticsSnapshot {
        snapshot
    }

    func reportRegistrationConfigured(identifier: String, handlerDescription: String) {
        let diagnostics = BackgroundRefreshRegistrationDiagnostics(
            identifier: identifier,
            handlerDescription: handlerDescription
        )
        snapshot.registration = diagnostics
        logger.info(
            "Background refresh validation stage=\(BackgroundRefreshValidationStage.registration.rawValue) outcome=configured identifier=\(identifier) handler=\(handlerDescription)"
        )
    }

    func reportLaunchScheduling(
        outcome: BackgroundRefreshSchedulingOutcome,
        identifier: String?,
        earliestBeginDate: Date?,
        failureReason: BackgroundRefreshScheduleFailureReason?
    ) {
        let diagnostics = BackgroundRefreshSchedulingDiagnostics(
            trigger: .launchBootstrap,
            outcome: outcome,
            identifier: identifier,
            earliestBeginDate: earliestBeginDate,
            failureReason: failureReason
        )
        snapshot.scheduling = diagnostics
        logger.log(
            level: outcome == .failed ? .error : .info,
            message: """
            Background refresh validation stage=\(BackgroundRefreshValidationStage.scheduling.rawValue) \
            trigger=\(diagnostics.trigger.rawValue) outcome=\(outcome.rawValue) \
            \(Self.optionalLogField("identifier", identifier)) \
            \(Self.optionalLogField("earliestBeginDate", earliestBeginDate)) \
            \(Self.optionalLogField("failureReason", failureReason?.rawValue))
            """
        )
    }

    func reportExecutionStarted() {
        snapshot.executionStart = BackgroundRefreshExecutionStartDiagnostics()
        logger.info(
            "Background refresh validation stage=\(BackgroundRefreshValidationStage.executionStart.rawValue) outcome=started"
        )
    }

    func reportExecutionCancellationReceived() {
        snapshot.executionCancellation = BackgroundRefreshExecutionCancellationDiagnostics()
        logger.info(
            "Background refresh validation stage=\(BackgroundRefreshValidationStage.executionCancellation.rawValue) outcome=receivedSystemCancellation"
        )
    }

    func reportExecutionCompleted(_ diagnostics: BackgroundRefreshExecutionCompletionDiagnostics) {
        snapshot.executionCompletion = diagnostics
        logger.log(
            level: diagnostics.kind == .failedToStart ? .error : .info,
            message: """
            Background refresh validation stage=\(BackgroundRefreshValidationStage.executionCompletion.rawValue) \
            outcome=\(diagnostics.kind.rawValue) \
            \(Self.optionalLogField("refreshIntervalPreference", diagnostics.refreshIntervalPreference?.rawValue)) \
            \(Self.optionalLogField("partialResultAvailable", diagnostics.partialResultAvailable)) \
            \(Self.optionalLogField("totalFeedCount", diagnostics.totalFeedCount)) \
            \(Self.optionalLogField("fetchedCount", diagnostics.fetchedCount)) \
            \(Self.optionalLogField("notModifiedCount", diagnostics.notModifiedCount)) \
            \(Self.optionalLogField("failedCount", diagnostics.failedCount)) \
            \(Self.optionalLogField("cancelledCount", diagnostics.cancelledCount)) \
            \(Self.optionalLogField("networkFailureCount", diagnostics.networkFailureCount)) \
            \(Self.optionalLogField("likelyNoConnectivityHeuristic", diagnostics.likelyNoConnectivityHeuristic)) \
            \(Self.optionalLogField("duration", diagnostics.duration)) \
            \(Self.optionalLogField("failureReason", diagnostics.failureReason))
            """
        )
    }

    func reportPostRunReschedule(
        outcome: BackgroundRefreshPostRunRescheduleOutcome,
        identifier: String?,
        earliestBeginDate: Date?,
        failureReason: BackgroundRefreshScheduleFailureReason?
    ) {
        let diagnostics = BackgroundRefreshPostRunRescheduleDiagnostics(
            outcome: outcome,
            identifier: identifier,
            earliestBeginDate: earliestBeginDate,
            failureReason: failureReason
        )
        snapshot.postRunReschedule = diagnostics
        logger.log(
            level: outcome == .failed || outcome == .serviceUnavailable ? .error : .info,
            message: """
            Background refresh validation stage=\(BackgroundRefreshValidationStage.postRunReschedule.rawValue) \
            outcome=\(outcome.rawValue) \
            \(Self.optionalLogField("identifier", identifier)) \
            \(Self.optionalLogField("earliestBeginDate", earliestBeginDate)) \
            \(Self.optionalLogField("failureReason", failureReason?.rawValue))
            """
        )
    }

    private static func optionalLogField<T>(_ name: String, _ value: T?) -> String {
        guard let value else { return "" }
        return "\(name)=\(value)"
    }
}

private extension Logging {
    func log(level: LogLevel, message: String) {
        switch level {
        case .debug:
            debug(message)
        case .info:
            info(message)
        case .error:
            error(message)
        }
    }
}
