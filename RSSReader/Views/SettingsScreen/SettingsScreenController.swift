import Foundation
import Observation

@MainActor
@Observable
final class SettingsScreenController {
    var screenState: SettingsScreenState
    let isPreviewMode: Bool

    init(previewScreenState: SettingsScreenState? = nil) {
        self.screenState = previewScreenState ?? SettingsScreenState()
        self.isPreviewMode = previewScreenState != nil
    }

    func viewState() -> SettingsScreenViewState {
        screenState.derivedViewState()
    }

    func loadSettings(dependencies: AppDependencies) {
        screenState.beginLoading()

        guard let appSettingsService = dependencies.appSettingsService else {
            screenState.applyLoadingFailure("Settings are unavailable in the current app environment.")
            return
        }

        do {
            let snapshot = try appSettingsService.fetchSettings()
            screenState.applyLoadedSnapshot(snapshot)
        } catch {
            dependencies.logger.error("Failed to load settings snapshot: \(error)")
            screenState.applyLoadingFailure("Unable to load settings right now. Try again.")
        }
    }

    func retryLoadingSettings(dependencies: AppDependencies) {
        loadSettings(dependencies: dependencies)
    }

    func handleItemSelection(_ itemID: SettingsScreenItemID, dependencies: AppDependencies) {
        dependencies.logger.info("Settings item action is not implemented yet: \(itemID.rawValue)")
    }
}
