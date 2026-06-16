import Foundation
import Observation

@MainActor
@Observable
final class FeedManagementScreenController {
    var screenState: FeedManagementScreenState
    let isPreviewMode: Bool
    var scenarioToRestoreAfterCreateFolder: FeedManagementScenarioID? = nil

    init(previewScreenState: FeedManagementScreenState? = nil) {
        self.screenState = previewScreenState ?? FeedManagementScreenState()
        self.isPreviewMode = previewScreenState != nil
    }

    func viewState() -> FeedManagementScreenViewState {
        screenState.derivedViewState()
    }
}
