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
        case .defaultReaderMode, .articleSortMode:
            screenState.presentPicker(for: itemID)
        case .markAsReadOnOpen,
                .askBeforeMarkingAllAsRead,
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
        case .articleSortMode:
            updateArticleSortMode(optionID: optionID, dependencies: dependencies)
        case .markAsReadOnOpen,
                .askBeforeMarkingAllAsRead,
                .refreshInterval,
                .iCloudSyncStatus,
                .linkOpening,
                .appearance:
            dependencies.logger.info("Settings picker option is not implemented yet: \(itemID.rawValue).\(optionID)")
        }
    }

    func handleToggleValueChange(
        itemID: SettingsScreenItemID,
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        switch itemID {
        case .markAsReadOnOpen:
            updateMarkAsReadOnOpen(isOn: isOn, dependencies: dependencies)
        case .askBeforeMarkingAllAsRead:
            updateAskBeforeMarkingAllAsRead(isOn: isOn, dependencies: dependencies)
        case .defaultReaderMode,
                .articleSortMode,
                .refreshInterval,
                .iCloudSyncStatus,
                .linkOpening,
                .appearance:
            dependencies.logger.info("Settings toggle action is not implemented yet: \(itemID.rawValue).\(isOn)")
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

    func updateMarkAsReadOnOpen(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsSnapshot.markAsReadOnOpen != isOn else {
            return
        }

        guard let appSettingsService = dependencies.appSettingsService else {
            dependencies.logger.error("App settings service is unavailable for mark-as-read-on-open update")
            return
        }

        do {
            let updatedSnapshot = try appSettingsService.updateSettings(
                AppSettingsPatch(
                    markAsReadOnOpen: isOn,
                    updatedAt: .now
                )
            )
            screenState.applyLoadedSnapshot(updatedSnapshot)
        } catch {
            dependencies.logger.error("Failed to update mark-as-read-on-open setting: \(error)")
        }
    }

    func updateAskBeforeMarkingAllAsRead(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsSnapshot.askBeforeMarkingAllAsRead != isOn else {
            return
        }

        guard let appSettingsService = dependencies.appSettingsService else {
            dependencies.logger.error("App settings service is unavailable for ask-before-marking-all-as-read update")
            return
        }

        do {
            let updatedSnapshot = try appSettingsService.updateSettings(
                AppSettingsPatch(
                    askBeforeMarkingAllAsRead: isOn,
                    updatedAt: .now
                )
            )
            screenState.applyLoadedSnapshot(updatedSnapshot)
        } catch {
            dependencies.logger.error("Failed to update ask-before-marking-all-as-read setting: \\(error)")
        }
    }

    func updateArticleSortMode(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedOrder = ArticleListSortOrder(rawValue: optionID) else {
            dependencies.logger.error("Skipped article sort mode update because option is invalid: \(optionID)")
            return
        }

        let selectedSortMode = selectedOrder.sortMode
        guard screenState.settingsSnapshot.sortMode != selectedSortMode else {
            screenState.dismissPresentedPicker()
            return
        }

        guard let appSettingsService = dependencies.appSettingsService else {
            dependencies.logger.error("App settings service is unavailable for article sort mode update")
            return
        }

        do {
            let updatedSnapshot = try appSettingsService.updateSettings(
                AppSettingsPatch(
                    sortMode: selectedSortMode,
                    updatedAt: .now
                )
            )
            screenState.applyLoadedSnapshot(updatedSnapshot)
        } catch {
            dependencies.logger.error("Failed to update article sort mode: \(error)")
        }
    }
}
