import BackgroundTasks
import Foundation

enum BackgroundRefreshExecutionOutcome: Sendable {
    case success(BackgroundFeedRefreshResult)
    case partialFailure(BackgroundFeedRefreshResult)
    case totalFailure(BackgroundFeedRefreshResult)
    case skippedManual(BackgroundRefreshConfiguration)
    case failedToStart(BackgroundRefreshServiceExecutionFailure)
    case cancelled(BackgroundFeedRefreshResult?)

    var result: BackgroundFeedRefreshResult? {
        switch self {
        case .success(let result), .partialFailure(let result), .totalFailure(let result):
            result
        case .cancelled(let result):
            result
        case .skippedManual, .failedToStart:
            nil
        }
    }
}

@MainActor
protocol BackgroundRefreshExecutionCoordinating {
    func executeAppRefresh() async -> BackgroundRefreshExecutionOutcome
}

@MainActor
final class DefaultBackgroundRefreshExecutionCoordinator: BackgroundRefreshExecutionCoordinating {
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func executeAppRefresh() async -> BackgroundRefreshExecutionOutcome {
        dependencies.logger.info("Starting background refresh execution")
        let cancellationState = BackgroundRefreshCancellationMarkerState()
        let refreshTask = Task { @MainActor in
            await dependencies.refreshFeedsForBackground()
        }

        let outcome = await withTaskCancellationHandler {
            let serviceResult = await refreshTask.value
            if Task.isCancelled {
                return BackgroundRefreshExecutionOutcome.cancelled(
                    serviceResult.backgroundFeedRefreshResult
                )
            }

            return mapExecutionOutcome(from: serviceResult)
        } onCancel: {
            cancellationState.markCancellationRequested()
            refreshTask.cancel()
        }

        logCancellationMarkerIfNeeded(cancellationState)
        logExecutionOutcome(outcome)
        replaceBackgroundRefreshScheduleAfterExecution()
        dependencies.backgroundRefreshForegroundHandoffCoordinator
            .handleBackgroundRefreshExecutionOutcome(outcome)
        return outcome
    }

    private func mapExecutionOutcome(
        from serviceResult: BackgroundRefreshServiceExecutionResult
    ) -> BackgroundRefreshExecutionOutcome {
        switch serviceResult {
        case .skippedManual(let configuration):
            return .skippedManual(configuration)
        case .failedToStart(let failure):
            return .failedToStart(failure)
        case .executed(let result):
            return Self.classifyExecutedRefreshResult(result)
        }
    }

    private static func classifyExecutedRefreshResult(
        _ result: BackgroundFeedRefreshResult
    ) -> BackgroundRefreshExecutionOutcome {
        let summary = result.summary

        if summary.totalFeedCount == 0 {
            return .success(result)
        }

        let successfulCount = summary.fetchedCount + summary.notModifiedCount
        let unsuccessfulCount = summary.failedCount + summary.cancelledCount

        if unsuccessfulCount == 0 {
            return .success(result)
        }

        if successfulCount == 0 {
            return .totalFailure(result)
        }

        return .partialFailure(result)
    }

    private func replaceBackgroundRefreshScheduleAfterExecution() {
        do {
            guard let result = try dependencies.replaceBackgroundRefreshSchedule(now: .now) else {
                dependencies.logger.error(
                    "Background refresh execution reschedule outcome=serviceUnavailable"
                )
                return
            }

            switch result {
            case .scheduled(let plan):
                dependencies.logger.info(
                    "Background refresh execution reschedule outcome=scheduled identifier=\(plan.identifier) earliestBeginDate=\(plan.earliestBeginDate)"
                )
            case .cancelled:
                dependencies.logger.info(
                    "Background refresh execution reschedule outcome=cancelled"
                )
            }
        } catch {
            let failureReason = Self.classifyScheduleFailure(error)
            dependencies.logger.error(
                "Background refresh execution reschedule outcome=failed reason=\(failureReason) error=\(error)"
            )
        }
    }

    private func logCancellationMarkerIfNeeded(
        _ cancellationState: BackgroundRefreshCancellationMarkerState
    ) {
        guard cancellationState.consumeCancellationRequested() else { return }
        dependencies.logger.info(
            "Received background refresh task cancellation; cancelling in-flight refresh task"
        )
    }

    private func logExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome) {
        switch outcome {
        case .success(let result):
            dependencies.logger.info(
                "Completed background refresh execution outcome=success \(Self.makeSummaryLogFields(from: result.summary)) \(Self.makeFailureDiagnosticsLogFields(from: result)) duration=\(result.duration)"
            )
        case .partialFailure(let result):
            dependencies.logger.info(
                "Completed background refresh execution outcome=partialFailure \(Self.makeSummaryLogFields(from: result.summary)) \(Self.makeFailureDiagnosticsLogFields(from: result)) duration=\(result.duration)"
            )
        case .totalFailure(let result):
            dependencies.logger.info(
                "Completed background refresh execution outcome=totalFailure \(Self.makeSummaryLogFields(from: result.summary)) \(Self.makeFailureDiagnosticsLogFields(from: result)) duration=\(result.duration)"
            )
        case .skippedManual(let configuration):
            dependencies.logger.info(
                "Completed background refresh execution outcome=skippedManual refreshIntervalPreference=\(configuration.policy.preference.rawValue)"
            )
        case .failedToStart(let failure):
            dependencies.logger.error(
                "Completed background refresh execution outcome=failedToStart reason=\(failure.logDescription)"
            )
        case .cancelled(let result):
            if let result {
                dependencies.logger.info(
                    "Completed background refresh execution outcome=cancelled partialResultAvailable=true \(Self.makeSummaryLogFields(from: result.summary)) \(Self.makeFailureDiagnosticsLogFields(from: result)) duration=\(result.duration)"
                )
            } else {
                dependencies.logger.info(
                    "Completed background refresh execution outcome=cancelled partialResultAvailable=false"
                )
            }
        }
    }

    private static func makeSummaryLogFields(from summary: FeedRefreshBatchSummary) -> String {
        "totalFeedCount=\(summary.totalFeedCount) fetchedCount=\(summary.fetchedCount) notModifiedCount=\(summary.notModifiedCount) failedCount=\(summary.failedCount) cancelledCount=\(summary.cancelledCount)"
    }

    private static func makeFailureDiagnosticsLogFields(from result: BackgroundFeedRefreshResult) -> String {
        let diagnostics = result.failureDiagnostics
        return "networkFailureCount=\(diagnostics.networkFailureCount) likelyNoConnectivity=\(diagnostics.likelyNoConnectivity)"
    }

    private static func classifyScheduleFailure(_ error: Error) -> String {
        BackgroundRefreshScheduleFailureReason.classify(error).rawValue
    }
}

private final class BackgroundRefreshCancellationMarkerState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cancellationRequested = false

    nonisolated
    func markCancellationRequested() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    nonisolated
    func consumeCancellationRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let currentValue = cancellationRequested
        cancellationRequested = false
        return currentValue
    }
}

private extension BackgroundRefreshServiceExecutionResult {
    var backgroundFeedRefreshResult: BackgroundFeedRefreshResult? {
        switch self {
        case .executed(let result):
            result
        case .skippedManual, .failedToStart:
            nil
        }
    }
}

private extension BackgroundRefreshServiceExecutionFailure {
    var logDescription: String {
        switch self {
        case .configurationLoadFailed:
            "configurationLoadFailed"
        case .feedRefreshServiceUnavailable:
            "feedRefreshServiceUnavailable"
        }
    }
}

private extension BackgroundFeedRefreshResult {
    var failureDiagnostics: BackgroundRefreshFailureDiagnostics {
        let networkFailureCount = batchResult.failedResults.reduce(into: 0) { partialResult, result in
            guard let errorDescription = result.errorDescription,
                  BackgroundRefreshFailureDiagnostics.isLikelyNetworkFailure(errorDescription) else {
                return
            }

            partialResult += 1
        }

        return BackgroundRefreshFailureDiagnostics(
            failedCount: summary.failedCount,
            networkFailureCount: networkFailureCount
        )
    }
}

private struct BackgroundRefreshFailureDiagnostics {
    let failedCount: Int
    let networkFailureCount: Int

    var likelyNoConnectivity: Bool {
        failedCount > 0 && networkFailureCount == failedCount
    }

    static func isLikelyNetworkFailure(_ errorDescription: String) -> Bool {
        let networkMarkers = [
            "NSURLErrorDomain Code=-1009",
            "NSURLErrorDomain Code=-1005",
            "NSURLErrorDomain Code=-1004",
            "NSURLErrorDomain Code=-1003"
        ]

        return networkMarkers.contains { errorDescription.contains($0) }
    }
}
