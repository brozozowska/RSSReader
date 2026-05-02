import Foundation

enum BackgroundRefreshExecutionOutcome: Sendable {
    case finished(BackgroundFeedRefreshResult?)
    case cancelled(BackgroundFeedRefreshResult?)

    var result: BackgroundFeedRefreshResult? {
        switch self {
        case .finished(let result), .cancelled(let result):
            result
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
            let result = await refreshTask.value
            if Task.isCancelled {
                return .cancelled(result)
            }

            return .finished(result)
        } onCancel: {
            refreshTask.cancel()
        }
    }
}
