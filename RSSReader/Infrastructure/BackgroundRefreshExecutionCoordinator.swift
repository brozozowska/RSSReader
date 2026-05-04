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
        dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionStarted()
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
                dependencies.backgroundRefreshValidationDiagnosticsReporter.reportPostRunReschedule(
                    outcome: .serviceUnavailable,
                    identifier: nil,
                    earliestBeginDate: nil,
                    failureReason: nil
                )
                return
            }

            switch result {
            case .scheduled(let plan):
                dependencies.backgroundRefreshValidationDiagnosticsReporter.reportPostRunReschedule(
                    outcome: .scheduled,
                    identifier: plan.identifier,
                    earliestBeginDate: plan.earliestBeginDate,
                    failureReason: nil
                )
            case .cancelled:
                dependencies.backgroundRefreshValidationDiagnosticsReporter.reportPostRunReschedule(
                    outcome: .cancelled,
                    identifier: nil,
                    earliestBeginDate: nil,
                    failureReason: nil
                )
            }
        } catch {
            let failureReason = BackgroundRefreshScheduleFailureReason.classify(error)
            dependencies.backgroundRefreshValidationDiagnosticsReporter.reportPostRunReschedule(
                outcome: .failed,
                identifier: nil,
                earliestBeginDate: nil,
                failureReason: failureReason
            )
        }
    }

    private func logCancellationMarkerIfNeeded(
        _ cancellationState: BackgroundRefreshCancellationMarkerState
    ) {
        guard cancellationState.consumeCancellationRequested() else { return }
        dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCancellationReceived()
    }

    private func logExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome) {
        switch outcome {
        case .success(let result):
            dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCompleted(
                Self.makeExecutionCompletionDiagnostics(
                    kind: .success,
                    result: result
                )
            )
        case .partialFailure(let result):
            dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCompleted(
                Self.makeExecutionCompletionDiagnostics(
                    kind: .partialFailure,
                    result: result
                )
            )
        case .totalFailure(let result):
            dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCompleted(
                Self.makeExecutionCompletionDiagnostics(
                    kind: .totalFailure,
                    result: result
                )
            )
        case .skippedManual(let configuration):
            dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCompleted(
                BackgroundRefreshExecutionCompletionDiagnostics(
                    kind: .skippedManual,
                    refreshIntervalPreference: configuration.policy.preference,
                    partialResultAvailable: nil,
                    totalFeedCount: nil,
                    fetchedCount: nil,
                    notModifiedCount: nil,
                    failedCount: nil,
                    cancelledCount: nil,
                    networkFailureCount: nil,
                    likelyNoConnectivityHeuristic: nil,
                    duration: nil,
                    failureReason: nil
                )
            )
        case .failedToStart(let failure):
            dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCompleted(
                BackgroundRefreshExecutionCompletionDiagnostics(
                    kind: .failedToStart,
                    refreshIntervalPreference: nil,
                    partialResultAvailable: nil,
                    totalFeedCount: nil,
                    fetchedCount: nil,
                    notModifiedCount: nil,
                    failedCount: nil,
                    cancelledCount: nil,
                    networkFailureCount: nil,
                    likelyNoConnectivityHeuristic: nil,
                    duration: nil,
                    failureReason: failure.logDescription
                )
            )
        case .cancelled(let result):
            if let result {
                dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCompleted(
                    Self.makeExecutionCompletionDiagnostics(
                        kind: .cancelled,
                        result: result,
                        partialResultAvailable: true
                    )
                )
            } else {
                dependencies.backgroundRefreshValidationDiagnosticsReporter.reportExecutionCompleted(
                    BackgroundRefreshExecutionCompletionDiagnostics(
                        kind: .cancelled,
                        refreshIntervalPreference: nil,
                        partialResultAvailable: false,
                        totalFeedCount: nil,
                        fetchedCount: nil,
                        notModifiedCount: nil,
                        failedCount: nil,
                        cancelledCount: nil,
                        networkFailureCount: nil,
                        likelyNoConnectivityHeuristic: nil,
                        duration: nil,
                        failureReason: nil
                    )
                )
            }
        }
    }

    private static func makeExecutionCompletionDiagnostics(
        kind: BackgroundRefreshExecutionCompletionKind,
        result: BackgroundFeedRefreshResult,
        partialResultAvailable: Bool? = nil
    ) -> BackgroundRefreshExecutionCompletionDiagnostics {
        let summary = result.summary
        let failureDiagnostics = result.failureDiagnostics
        return BackgroundRefreshExecutionCompletionDiagnostics(
            kind: kind,
            refreshIntervalPreference: nil,
            partialResultAvailable: partialResultAvailable,
            totalFeedCount: summary.totalFeedCount,
            fetchedCount: summary.fetchedCount,
            notModifiedCount: summary.notModifiedCount,
            failedCount: summary.failedCount,
            cancelledCount: summary.cancelledCount,
            networkFailureCount: failureDiagnostics.networkFailureCount,
            likelyNoConnectivityHeuristic: failureDiagnostics.likelyNoConnectivityHeuristic,
            duration: result.duration,
            failureReason: nil
        )
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

    // This is a best-effort signal derived from stringly error descriptions.
    // Validation must not treat it as a typed source of truth for connectivity state.
    var likelyNoConnectivityHeuristic: Bool {
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
