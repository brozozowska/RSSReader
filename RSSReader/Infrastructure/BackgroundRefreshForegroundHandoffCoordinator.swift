import Foundation

@MainActor
protocol BackgroundRefreshForegroundHandoffCoordinating {
    func bindReloadHandler(_ handler: @escaping @MainActor () -> Void)
    func unbindReloadHandler()
    func updateRuntimeState(_ runtimeState: AppRuntimeReloadState)
    func handleBackgroundRefreshExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome)
}

@MainActor
final class DefaultBackgroundRefreshForegroundHandoffCoordinator: BackgroundRefreshForegroundHandoffCoordinating {
    private var runtimeState: AppRuntimeReloadState = .inactiveOrBackground
    private var pendingReload = false
    private var reloadHandler: (@MainActor () -> Void)?

    func bindReloadHandler(_ handler: @escaping @MainActor () -> Void) {
        reloadHandler = handler
        flushPendingReloadIfNeeded()
    }

    func unbindReloadHandler() {
        reloadHandler = nil
    }

    func updateRuntimeState(_ runtimeState: AppRuntimeReloadState) {
        self.runtimeState = runtimeState
        flushPendingReloadIfNeeded()
    }

    func handleBackgroundRefreshExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome) {
        let decision = BackgroundRefreshForegroundHandoffPolicy.decision(
            for: outcome,
            runtimeState: runtimeState
        )

        switch decision {
        case .noReload:
            return
        case .requestReloadImmediately:
            if let reloadHandler {
                reloadHandler()
            } else {
                pendingReload = true
            }
        case .deferUntilNextForeground:
            pendingReload = true
        }
    }

    private func flushPendingReloadIfNeeded() {
        guard pendingReload, runtimeState == .activeForeground, let reloadHandler else {
            return
        }

        pendingReload = false
        reloadHandler()
    }
}
