import Foundation
import Observation

@MainActor
@Observable
final class SourceManagementScreenController {
    var screenState: SourceManagementScreenState
    let isPreviewMode: Bool
    var scenarioToRestoreAfterCreateFolder: SourceManagementScenarioID? = nil

    init(previewScreenState: SourceManagementScreenState? = nil) {
        self.screenState = previewScreenState ?? SourceManagementScreenState()
        self.isPreviewMode = previewScreenState != nil
    }

    func viewState() -> SourceManagementScreenViewState {
        screenState.derivedViewState()
    }
}
