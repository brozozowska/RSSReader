import Foundation

extension AppDependencies {
    @MainActor
    func reportBackgroundRefreshRegistrationConfigured(
        identifier: String = BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
        handlerDescription: String = "SwiftUI.backgroundTask(.appRefresh)"
    ) {
        backgroundRefreshValidationDiagnosticsReporter.reportRegistrationConfigured(
            identifier: identifier,
            handlerDescription: handlerDescription
        )
    }

    @MainActor
    func executeBackgroundAppRefresh() async -> BackgroundRefreshExecutionOutcome {
        let executionCoordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: self)
        return await executionCoordinator.executeAppRefresh()
    }

    @MainActor
    func startSyncCoordinatorAppLifetime() {
        syncRuntimeOrchestrator.startSyncCoordinatorAppLifetime()
    }

    @MainActor
    func startRemoteSyncReloadAppLifetime(using appState: AppState) {
        syncRuntimeOrchestrator.startRemoteSyncReloadAppLifetime(using: appState)
    }

    @MainActor
    func stopSyncRuntimeAppLifetime() {
        syncRuntimeOrchestrator.stopAppLifetime()
    }
}
