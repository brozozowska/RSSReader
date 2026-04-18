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
        switch itemID {
        case .defaultReaderMode:
            screenState.presentPicker(for: itemID)
        case .markAsReadOnOpen,
                .articleSortMode,
                .articleGrouping,
                .refreshInterval,
                .iCloudSyncStatus,
                .linkOpening,
                .appearance:
            dependencies.logger.info("Settings item action is not implemented yet: \(itemID.rawValue)")
        }
    }

    func dismissPresentedPicker() {
        screenState.dismissPresentedPicker()
    }

    func handlePickerOptionSelection(
        itemID: SettingsScreenItemID,
        optionID: String,
        dependencies: AppDependencies
    ) {
        switch itemID {
        case .defaultReaderMode:
            updateDefaultReaderMode(optionID: optionID, dependencies: dependencies)
        case .markAsReadOnOpen,
                .articleSortMode,
                .articleGrouping,
                .refreshInterval,
                .iCloudSyncStatus,
                .linkOpening,
                .appearance:
            dependencies.logger.info("Settings picker option is not implemented yet: \(itemID.rawValue).\(optionID)")
        }
    }
}

private extension SettingsScreenController {
    func updateDefaultReaderMode(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedMode = ReaderMode(rawValue: optionID) else {
            dependencies.logger.error("Skipped default reader mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsSnapshot.defaultReaderMode != selectedMode else {
            screenState.dismissPresentedPicker()
            return
        }

        guard let appSettingsService = dependencies.appSettingsService else {
            dependencies.logger.error("App settings service is unavailable for default reader mode update")
            return
        }

        do {
            let updatedSnapshot = try appSettingsService.updateSettings(
                AppSettingsPatch(
                    defaultReaderMode: selectedMode,
                    updatedAt: .now
                )
            )
            screenState.applyLoadedSnapshot(updatedSnapshot)
        } catch {
            dependencies.logger.error("Failed to update default reader mode: \(error)")
        }
    }
}
