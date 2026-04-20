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

    func loadSettings(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        screenState.beginLoading()

        guard let appSettingsService = dependencies.appSettingsService else {
            screenState.applyLoadingFailure("Settings are unavailable in the current app environment.")
            return
        }

        do {
            let snapshot = try appSettingsService.fetchSettings()
            let resolvedICloudSyncStatus = resolveICloudSyncStatus(
                dependencies: dependencies,
                appState: appState,
                settingsSnapshot: snapshot
            )
            screenState.applyLoadedSnapshot(snapshot, iCloudSyncStatus: resolvedICloudSyncStatus)
            if let appState, appState.interfaceThemeMode != snapshot.interfaceThemeMode {
                appState.applyInterfaceThemeMode(snapshot.interfaceThemeMode)
            }
        } catch {
            dependencies.logger.error("Failed to load settings snapshot: \(error)")
            screenState.applyLoadingFailure("Unable to load settings right now. Try again.")
        }
    }

    func retryLoadingSettings(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        loadSettings(dependencies: dependencies, appState: appState)
    }

    func handleItemSelection(_ itemID: SettingsScreenItemID) {
        switch itemID {
        case .defaultReaderMode,
                .articleSourceLinkOpeningPolicy,
                .articleSortMode,
                .articleBodyLinkOpeningPolicy,
                .appearance,
                .refreshInterval:
            screenState.presentPicker(for: itemID)
        case .markAsReadOnOpen,
                .askBeforeMarkingAllAsRead,
                .iCloudSyncStatus:
            return
        }
    }

    func dismissPresentedPicker() {
        screenState.dismissPresentedPicker()
    }

    func handlePickerOptionSelection(
        itemID: SettingsScreenItemID,
        optionID: String,
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        switch itemID {
        case .defaultReaderMode:
            updateDefaultReaderMode(optionID: optionID, dependencies: dependencies)
        case .articleSourceLinkOpeningPolicy:
            updateArticleSourceLinkOpeningPolicy(optionID: optionID, dependencies: dependencies)
        case .articleSortMode:
            updateArticleSortMode(optionID: optionID, dependencies: dependencies)
        case .articleBodyLinkOpeningPolicy:
            updateArticleBodyLinkOpeningPolicy(optionID: optionID, dependencies: dependencies)
        case .refreshInterval:
            updateRefreshIntervalPreference(optionID: optionID, dependencies: dependencies)
        case .appearance:
            updateInterfaceThemeMode(
                optionID: optionID,
                dependencies: dependencies,
                appState: appState
            )
        case .markAsReadOnOpen,
                .askBeforeMarkingAllAsRead,
                .iCloudSyncStatus:
            return
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
                .articleSourceLinkOpeningPolicy,
                .articleSortMode,
                .articleBodyLinkOpeningPolicy,
                .refreshInterval,
                .iCloudSyncStatus,
                .appearance:
            return
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

        persistSettingsPatch(
            AppSettingsPatch(
                defaultReaderMode: selectedMode,
                updatedAt: .now
            ),
            dependencies: dependencies,
            unavailableServiceLog: "App settings service is unavailable for default reader mode update",
            failureLogPrefix: "Failed to update default reader mode"
        )
    }

    func updateMarkAsReadOnOpen(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsSnapshot.markAsReadOnOpen != isOn else {
            return
        }

        persistSettingsPatch(
            AppSettingsPatch(
                markAsReadOnOpen: isOn,
                updatedAt: .now
            ),
            dependencies: dependencies,
            unavailableServiceLog: "App settings service is unavailable for mark-as-read-on-open update",
            failureLogPrefix: "Failed to update mark-as-read-on-open setting"
        )
    }

    func updateAskBeforeMarkingAllAsRead(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsSnapshot.askBeforeMarkingAllAsRead != isOn else {
            return
        }

        persistSettingsPatch(
            AppSettingsPatch(
                askBeforeMarkingAllAsRead: isOn,
                updatedAt: .now
            ),
            dependencies: dependencies,
            unavailableServiceLog: "App settings service is unavailable for ask-before-marking-all-as-read update",
            failureLogPrefix: "Failed to update ask-before-marking-all-as-read setting"
        )
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

        persistSettingsPatch(
            AppSettingsPatch(
                sortMode: selectedSortMode,
                updatedAt: .now
            ),
            dependencies: dependencies,
            unavailableServiceLog: "App settings service is unavailable for article sort mode update",
            failureLogPrefix: "Failed to update article sort mode"
        )
    }

    func updateArticleBodyLinkOpeningPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleBodyLinkOpeningPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article body link opening policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsSnapshot.articleBodyLinkOpeningPolicy != selectedPolicy else {
            screenState.dismissPresentedPicker()
            return
        }

        persistSettingsPatch(
            AppSettingsPatch(
                articleBodyLinkOpeningPolicy: selectedPolicy,
                updatedAt: .now
            ),
            dependencies: dependencies,
            unavailableServiceLog: "App settings service is unavailable for article body link opening policy update",
            failureLogPrefix: "Failed to update article body link opening policy"
        )
    }

    func updateArticleSourceLinkOpeningPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleSourceLinkOpeningPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article source link opening policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsSnapshot.articleSourceLinkOpeningPolicy != selectedPolicy else {
            screenState.dismissPresentedPicker()
            return
        }

        persistSettingsPatch(
            AppSettingsPatch(
                articleSourceLinkOpeningPolicy: selectedPolicy,
                updatedAt: .now
            ),
            dependencies: dependencies,
            unavailableServiceLog: "App settings service is unavailable for article source link opening policy update",
            failureLogPrefix: "Failed to update article source link opening policy"
        )
    }

    func updateInterfaceThemeMode(
        optionID: String,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        guard let selectedMode = InterfaceThemeMode(rawValue: optionID) else {
            dependencies.logger.error("Skipped interface theme mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsSnapshot.interfaceThemeMode != selectedMode else {
            screenState.dismissPresentedPicker()
            return
        }

        persistSettingsPatch(
            AppSettingsPatch(
                interfaceThemeMode: selectedMode,
                updatedAt: .now
            ),
            dependencies: dependencies,
            unavailableServiceLog: "App settings service is unavailable for interface theme mode update",
            failureLogPrefix: "Failed to update interface theme mode"
        ) { updatedSnapshot in
            appState?.applyInterfaceThemeMode(updatedSnapshot.interfaceThemeMode)
        }
    }

    func updateRefreshIntervalPreference(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPreference = RefreshPreference(rawValue: optionID) else {
            dependencies.logger.error("Skipped refresh interval update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsSnapshot.refreshIntervalPreference != selectedPreference else {
            screenState.dismissPresentedPicker()
            return
        }

        guard let backgroundRefreshService = dependencies.backgroundRefreshService else {
            dependencies.logger.error("Background refresh service is unavailable for refresh interval update")
            return
        }

        do {
            let updatedConfiguration = try backgroundRefreshService.updatePreference(
                selectedPreference,
                updatedAt: .now
            )
            applyUpdatedSettingsSnapshot(updatedConfiguration.settingsSnapshot)
        } catch {
            dependencies.logger.error("Failed to update refresh interval preference: \(error)")
        }
    }

    func resolveICloudSyncStatus(
        dependencies: AppDependencies,
        appState: AppState?,
        settingsSnapshot: AppSettingsSnapshot
    ) -> ICloudSyncStatus {
        if settingsSnapshot.useiCloudSync == false {
            appState?.applyICloudSyncStatus(.disabled)
            return .disabled
        }

        if let appState, appState.iCloudSyncStatus != .disabled {
            return appState.iCloudSyncStatus
        }

        guard let iCloudSyncStatusService = dependencies.iCloudSyncStatusService else {
            appState?.applyICloudSyncStatus(.statusUnavailable)
            return .statusUnavailable
        }

        do {
            let resolvedStatus = try iCloudSyncStatusService.currentStatus()
            appState?.applyICloudSyncStatus(resolvedStatus)
            return resolvedStatus
        } catch {
            dependencies.logger.error("Failed to resolve iCloud sync status: \(error)")
            let failedStatus = ICloudSyncStatus.failed("Unable to load iCloud sync status right now.")
            appState?.applyICloudSyncStatus(failedStatus)
            return failedStatus
        }
    }

    func persistSettingsPatch(
        _ patch: AppSettingsPatch,
        dependencies: AppDependencies,
        unavailableServiceLog: String,
        failureLogPrefix: String,
        onApplied: ((AppSettingsSnapshot) -> Void)? = nil
    ) {
        guard let appSettingsService = dependencies.appSettingsService else {
            dependencies.logger.error(unavailableServiceLog)
            return
        }

        do {
            let updatedSnapshot = try appSettingsService.updateSettings(patch)
            applyUpdatedSettingsSnapshot(updatedSnapshot)
            onApplied?(updatedSnapshot)
        } catch {
            dependencies.logger.error("\(failureLogPrefix): \(error)")
        }
    }

    func applyUpdatedSettingsSnapshot(_ snapshot: AppSettingsSnapshot) {
        screenState.applyLoadedSnapshot(snapshot, iCloudSyncStatus: screenState.iCloudSyncStatus)
    }
}
