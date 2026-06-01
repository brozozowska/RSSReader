import SwiftUI

extension AppComposition {
    @MainActor
    static func scheduleBackgroundRefreshOnLaunch(using dependencies: AppDependencies) {
        dependencies.configureBackgroundRefreshLaunchScheduling()
    }

    @MainActor
    static func scheduleBackgroundRefreshOnLaunchIfNeeded(
        using dependencies: AppDependencies
    ) {
        scheduleBackgroundRefreshOnLaunchIfNeeded(
            using: dependencies,
            guard: backgroundRefreshLaunchSchedulingGuard
        )
    }

    @MainActor
    static func scheduleBackgroundRefreshOnLaunchIfNeeded(
        using dependencies: AppDependencies,
        guard bootstrapGuard: AppLaunchBootstrapGuard
    ) {
        guard bootstrapGuard.beginAttempt(identifier: "BackgroundRefreshLaunchScheduling") else {
            dependencies.reportSkippedDuplicateBackgroundRefreshLaunchSchedulingAttempt()
            return
        }

        scheduleBackgroundRefreshOnLaunch(using: dependencies)
    }

    @MainActor
    static func bindBackgroundRefreshForegroundReloadHandler(
        using dependencies: AppDependencies,
        appState: AppState
    ) {
        dependencies.backgroundRefreshForegroundHandoffCoordinator.bindReloadHandler {
            appState.requestBackgroundRefreshReload()
        }
    }

    @MainActor
    static func unbindBackgroundRefreshForegroundReloadHandler(using dependencies: AppDependencies) {
        dependencies.backgroundRefreshForegroundHandoffCoordinator.unbindReloadHandler()
    }

    @MainActor
    static func applyBackgroundRefreshForegroundRuntimeState(
        from scenePhase: ScenePhase,
        using dependencies: AppDependencies
    ) {
        dependencies.backgroundRefreshForegroundHandoffCoordinator.updateRuntimeState(
            runtimeState(from: scenePhase)
        )
    }

    @MainActor
    static func runtimeState(from scenePhase: ScenePhase) -> AppRuntimeReloadState {
        switch scenePhase {
        case .active:
            .activeForeground
        case .background, .inactive:
            .inactiveOrBackground
        @unknown default:
            .inactiveOrBackground
        }
    }
}
