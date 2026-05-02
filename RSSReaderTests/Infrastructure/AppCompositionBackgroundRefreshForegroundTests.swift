import SwiftUI
import Testing
@testable import RSSReader

@MainActor
@Suite("Infrastructure / AppComposition Background Refresh Foreground")
struct AppCompositionBackgroundRefreshForegroundTests {
    @Test
    func appCompositionMapsActiveScenePhaseToActiveForegroundRuntimeState() {
        let runtimeState = AppComposition.runtimeState(from: .active)

        switch runtimeState {
        case .activeForeground:
            break
        case .inactiveOrBackground:
            Issue.record("Expected .activeForeground runtime state for .active scene phase")
        }
    }

    @Test
    func appCompositionMapsInactiveScenePhaseToInactiveOrBackgroundRuntimeState() {
        let runtimeState = AppComposition.runtimeState(from: .inactive)

        switch runtimeState {
        case .inactiveOrBackground:
            break
        case .activeForeground:
            Issue.record("Expected .inactiveOrBackground runtime state for .inactive scene phase")
        }
    }

    @Test
    func appCompositionBindsBackgroundRefreshReloadHandlerToAppStateTrigger() {
        let coordinator = RecordingBackgroundRefreshForegroundHandoffCoordinator()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            backgroundRefreshForegroundHandoffCoordinator: coordinator
        )
        let appState = AppState()

        AppComposition.bindBackgroundRefreshForegroundReloadHandler(
            using: dependencies,
            appState: appState
        )
        coordinator.triggerBoundReloadHandler()

        #expect(appState.lastContentReloadTrigger == .backgroundRefresh)
    }
}

@MainActor
private final class RecordingBackgroundRefreshForegroundHandoffCoordinator: BackgroundRefreshForegroundHandoffCoordinating {
    private var reloadHandler: (@MainActor () -> Void)?

    func bindReloadHandler(_ handler: @escaping @MainActor () -> Void) {
        reloadHandler = handler
    }

    func unbindReloadHandler() {
        reloadHandler = nil
    }

    func updateRuntimeState(_ runtimeState: AppRuntimeReloadState) {}

    func handleBackgroundRefreshExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome) {}

    func triggerBoundReloadHandler() {
        reloadHandler?()
    }
}
