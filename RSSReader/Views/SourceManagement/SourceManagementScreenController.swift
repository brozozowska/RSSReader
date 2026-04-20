import Foundation
import Observation

@MainActor
@Observable
final class SourceManagementScreenController {
    var screenState: SourceManagementScreenState
    let isPreviewMode: Bool

    init(previewScreenState: SourceManagementScreenState? = nil) {
        self.screenState = previewScreenState ?? SourceManagementScreenState()
        self.isPreviewMode = previewScreenState != nil
    }

    func viewState() -> SourceManagementScreenViewState {
        screenState.derivedViewState()
    }

    func handleScenarioSelection(_ scenarioID: SourceManagementScenarioID) {
        screenState.presentScenario(scenarioID)
    }

    func dismissPresentedScenario() {
        screenState.dismissPresentedScenario()
    }
}
