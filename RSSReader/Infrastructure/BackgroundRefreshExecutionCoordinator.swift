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
        let refreshTask = Task { @MainActor in
            await dependencies.refreshFeedsForBackground()
        }

        return await withTaskCancellationHandler {
            let serviceResult = await refreshTask.value
            if Task.isCancelled {
                return .cancelled(serviceResult.backgroundFeedRefreshResult)
            }

            return mapExecutionOutcome(from: serviceResult)
        } onCancel: {
            refreshTask.cancel()
        }
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
