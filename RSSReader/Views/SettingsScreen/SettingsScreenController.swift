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
            let message = dependencies.modelContainerBootstrapFailureDescription
                ?? "Settings are unavailable in the current app environment."
            screenState.applyLoadingFailure(message)
            return
        }

        do {
            let snapshot = try appSettingsService.fetchSettings()
            let resolvedSyncStatus = resolveSyncStatusPresentation(
                dependencies: dependencies,
                appState: appState,
                settingsSnapshot: snapshot
            )
            screenState.applyLoadedSnapshot(
                snapshot,
                iCloudSyncStatus: resolvedSyncStatus.iCloudSyncStatus,
                syncStatusPresentation: resolvedSyncStatus,
                isUsingLocalOnlySyncFallbackForCurrentLaunch: dependencies.syncBootstrapContext?.isRunningLocalOnlyFallbackForCurrentLaunch == true
            )
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

    func refreshArticleImageCacheAvailability(dependencies: AppDependencies) async {
        do {
            let hasDiskCache = try await ArticleImageDiskCache.shared.isEmpty() == false
            let hasMemoryCache = ArticleImageMemoryCache.shared.hasImages
            screenState.applyArticleImageCacheAvailability(hasDiskCache || hasMemoryCache)
        } catch {
            dependencies.logger.error("Failed to inspect article image cache: \(error)")
            screenState.applyArticleImageCacheAvailability(ArticleImageMemoryCache.shared.hasImages)
        }
    }

    func refreshSourceIconCacheAvailability(dependencies: AppDependencies) async {
        do {
            let hasCache = try await dependencies.sourceIconCache.hasCachedData()
            screenState.applySourceIconCacheAvailability(hasCache)
        } catch {
            dependencies.logger.error("Failed to inspect source icon cache: \(error)")
            screenState.applySourceIconCacheAvailability(false)
        }
    }

    func refreshArchivedArticlesAvailability(dependencies: AppDependencies) {
        do {
            let hasArchivedArticles = try dependencies.articleRepository?.fetchArchivedArticles().isEmpty == false
            screenState.applyArchivedArticlesAvailability(hasArchivedArticles)
        } catch {
            dependencies.logger.error("Failed to inspect archived articles: \(error)")
            screenState.applyArchivedArticlesAvailability(false)
        }
    }

    func handlePickerOptionSelection(
        itemID: SettingsScreenItemID,
        optionID: String,
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) {
        switch itemID {
        case .articleOpeningMode:
            updateArticleOpeningMode(optionID: optionID, dependencies: dependencies)
        case .articleSourceLinkOpeningPolicy:
            updateArticleSourceLinkOpeningPolicy(optionID: optionID, dependencies: dependencies)
        case .unreadArticleSortMode:
            updateUnreadArticleSortMode(optionID: optionID, dependencies: dependencies)
        case .articleRetentionPolicy:
            updateArticleRetentionPolicy(optionID: optionID, dependencies: dependencies)
        case .articleBodyLinkOpeningPolicy:
            updateArticleBodyLinkOpeningPolicy(optionID: optionID, dependencies: dependencies)
        case .readerAdjacentNavigationControlsMode:
            updateReaderAdjacentNavigationControlsMode(optionID: optionID, dependencies: dependencies)
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
                .showUnreadCountBadge,
                .useICloudSync,
                .iCloudSyncStatus,
                .purgeArchivedArticles,
                .clearArticleImageCache,
                .clearSourceIconCache:
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
        case .useICloudSync:
            updateUseICloudSync(isOn: isOn, dependencies: dependencies)
        case .showUnreadCountBadge:
            updateShowUnreadCountBadge(isOn: isOn, dependencies: dependencies)
        case .articleOpeningMode,
                .articleSourceLinkOpeningPolicy,
                .unreadArticleSortMode,
                .articleRetentionPolicy,
                .articleBodyLinkOpeningPolicy,
                .readerAdjacentNavigationControlsMode,
                .refreshInterval,
                .iCloudSyncStatus,
                .appearance,
                .purgeArchivedArticles,
                .clearArticleImageCache,
                .clearSourceIconCache:
            return
        }
    }

    func handleButtonTap(
        itemID: SettingsScreenItemID,
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) async {
        switch itemID {
        case .purgeArchivedArticles:
            purgeArchivedArticles(dependencies: dependencies, appState: appState)
        case .clearArticleImageCache:
            await clearArticleImageCache(dependencies: dependencies)
        case .clearSourceIconCache:
            await clearSourceIconCache(dependencies: dependencies, appState: appState)
        case .articleOpeningMode,
                .markAsReadOnOpen,
                .articleSourceLinkOpeningPolicy,
                .unreadArticleSortMode,
                .articleRetentionPolicy,
                .askBeforeMarkingAllAsRead,
                .showUnreadCountBadge,
                .refreshInterval,
                .useICloudSync,
                .iCloudSyncStatus,
                .articleBodyLinkOpeningPolicy,
                .readerAdjacentNavigationControlsMode,
                .appearance:
            return
        }
    }

    @discardableResult
    func applySettingsChanges(
        dependencies: AppDependencies,
        appState: AppState? = nil
    ) -> Bool {
        guard screenState.derivedViewState().canApplyChanges else {
            return true
        }

        guard let appSettingsService = dependencies.appSettingsService else {
            dependencies.logger.error("App settings service is unavailable for applying settings changes")
            return false
        }

        let previousSnapshot = screenState.settingsSnapshot
        let pendingSnapshot = screenState.pendingSettingsSnapshot()

        do {
            let updatedSnapshot = try appSettingsService.saveSettings(
                pendingSnapshot,
                updatedAt: .now
            )
            applyUpdatedSettingsSnapshot(updatedSnapshot)
            applySettingsSideEffects(
                previousSnapshot: previousSnapshot,
                updatedSnapshot: updatedSnapshot,
                dependencies: dependencies,
                appState: appState
            )
            return true
        } catch {
            dependencies.logger.error("Failed to apply settings changes: \(error)")
            return false
        }
    }
}

private extension SettingsScreenController {
    func clearArticleImageCache(dependencies: AppDependencies) async {
        ArticleImageMemoryCache.shared.removeAllImages()
        URLCache.shared.removeAllCachedResponses()

        do {
            try await ArticleImageDiskCache.shared.removeAll()
            screenState.applyArticleImageCacheAvailability(false)
            dependencies.logger.info("Cleared article image cache")
        } catch {
            dependencies.logger.error("Failed to clear article image disk cache: \(error)")
            await refreshArticleImageCacheAvailability(dependencies: dependencies)
        }
    }

    func clearSourceIconCache(
        dependencies: AppDependencies,
        appState: AppState?
    ) async {
        do {
            try await dependencies.sourceIconCache.removeAllCachedData()
            screenState.applySourceIconCacheAvailability(false)
            appState?.requestSourceIconCacheReset()
            dependencies.logger.info("Cleared source icon cache")
        } catch {
            dependencies.logger.error("Failed to clear source icon cache: \(error)")
            await refreshSourceIconCacheAvailability(dependencies: dependencies)
        }
    }

    func purgeArchivedArticles(
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        guard let result = dependencies.appActions.purgeArchivedArticles() else {
            refreshArchivedArticlesAvailability(dependencies: dependencies)
            return
        }

        screenState.applyArchivedArticlesAvailability(false)
        if result.deletedCount > 0 {
            appState?.requestSourcesSidebarReload()
            appState?.requestArticleListReload()
        }
    }

    func updateArticleOpeningMode(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedMode = ArticleOpeningMode(rawValue: optionID) else {
            dependencies.logger.error("Skipped article opening mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleOpeningMode != selectedMode else {
            return
        }

        var input = screenState.settingsInput
        input.articleOpeningMode = selectedMode
        screenState.applyDraftInput(input)
    }

    func updateMarkAsReadOnOpen(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.markAsReadOnOpen != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.markAsReadOnOpen = isOn
        screenState.applyDraftInput(input)
    }

    func updateAskBeforeMarkingAllAsRead(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.askBeforeMarkingAllAsRead != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.askBeforeMarkingAllAsRead = isOn
        screenState.applyDraftInput(input)
    }

    func updateUseICloudSync(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.useiCloudSync != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.useiCloudSync = isOn
        screenState.applyDraftInput(input)
    }

    func updateShowUnreadCountBadge(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.showUnreadCountBadge != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.showUnreadCountBadge = isOn
        screenState.applyDraftInput(input)
    }

    func updateUnreadArticleSortMode(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedOrder = UnreadArticleSortOrder(rawValue: optionID) else {
            dependencies.logger.error("Skipped unread article sort mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.unreadArticleSortOrder != selectedOrder else {
            return
        }

        var input = screenState.settingsInput
        input.unreadArticleSortOrder = selectedOrder
        screenState.applyDraftInput(input)
    }

    func updateArticleRetentionPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleRetentionPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article retention policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleRetentionPolicy != selectedPolicy else {
            return
        }

        var input = screenState.settingsInput
        input.articleRetentionPolicy = selectedPolicy
        screenState.applyDraftInput(input)
    }

    func updateArticleBodyLinkOpeningPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleBodyLinkOpeningPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article body link opening policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleBodyLinkOpeningPolicy != selectedPolicy else {
            return
        }

        var input = screenState.settingsInput
        input.articleBodyLinkOpeningPolicy = selectedPolicy
        screenState.applyDraftInput(input)
    }

    func updateArticleSourceLinkOpeningPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleSourceLinkOpeningPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article source link opening policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleSourceLinkOpeningPolicy != selectedPolicy else {
            return
        }

        var input = screenState.settingsInput
        input.articleSourceLinkOpeningPolicy = selectedPolicy
        screenState.applyDraftInput(input)
    }

    func updateReaderAdjacentNavigationControlsMode(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedMode = ReaderAdjacentNavigationControlsMode(rawValue: optionID) else {
            dependencies.logger.error("Skipped reader adjacent navigation controls mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.readerAdjacentNavigationControlsMode != selectedMode else {
            return
        }

        var input = screenState.settingsInput
        input.readerAdjacentNavigationControlsMode = selectedMode
        screenState.applyDraftInput(input)
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

        guard screenState.settingsInput.interfaceThemeMode != selectedMode else {
            return
        }

        var input = screenState.settingsInput
        input.interfaceThemeMode = selectedMode
        screenState.applyDraftInput(input)
    }

    func updateRefreshIntervalPreference(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPreference = RefreshPreference(rawValue: optionID) else {
            dependencies.logger.error("Skipped refresh interval update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.refreshIntervalPreference != selectedPreference else {
            return
        }

        var input = screenState.settingsInput
        input.refreshIntervalPreference = selectedPreference
        screenState.applyDraftInput(input)
    }

    func resolveSyncStatusPresentation(
        dependencies: AppDependencies,
        appState: AppState?,
        settingsSnapshot: AppSettingsSnapshot
    ) -> SettingsSyncStatusPresentation {
        if let syncCoordinator = dependencies.syncCoordinator,
           syncCoordinator.runtimeState.isSyncEnabled {
            let resolvedStatus = SettingsSyncStatusPresentation(runtimeState: syncCoordinator.runtimeState)
            appState?.applyICloudSyncStatus(resolvedStatus.iCloudSyncStatus)
            return resolvedStatus
        }

        if let syncBootstrapContext = dependencies.syncBootstrapContext,
           syncBootstrapContext.isRunningLocalOnlyFallbackForCurrentLaunch {
            let fallbackStatus = bootstrapFallbackStatusPresentation(for: syncBootstrapContext)
            appState?.applyICloudSyncStatus(fallbackStatus.iCloudSyncStatus)
            return fallbackStatus
        }

        if let appState, appState.iCloudSyncStatus != .disabled {
            return SettingsSyncStatusPresentation(iCloudSyncStatus: appState.iCloudSyncStatus)
        }

        if let appState {
            return SettingsSyncStatusPresentation(iCloudSyncStatus: appState.iCloudSyncStatus)
        }

        if settingsSnapshot.useiCloudSync == false {
            return .disabled
        }

        return .statusUnavailable
    }

    func applySettingsSideEffects(
        previousSnapshot: AppSettingsSnapshot,
        updatedSnapshot: AppSettingsSnapshot,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        if previousSnapshot.useiCloudSync != updatedSnapshot.useiCloudSync {
            dependencies.syncBootstrapPreferenceStore.saveBootPreference(
                updatedSnapshot.useiCloudSync ? .enabled : .disabled
            )
        }

        if previousSnapshot.interfaceThemeMode != updatedSnapshot.interfaceThemeMode {
            appState?.applyInterfaceThemeMode(updatedSnapshot.interfaceThemeMode)
        }

        if previousSnapshot.articleRetentionPolicy != updatedSnapshot.articleRetentionPolicy {
            let cleanupResult = dependencies.appActions.cleanupArchivedArticles(
                policy: updatedSnapshot.articleRetentionPolicy,
                now: .now
            )
            if cleanupResult?.deletedCount ?? 0 > 0 {
                appState?.requestSourcesSidebarReload()
                appState?.requestArticleListReload()
            }
        }

        if previousSnapshot.showUnreadCountBadge != updatedSnapshot.showUnreadCountBadge {
            dependencies.appActions.applyUnreadAppIconBadgePreference(isEnabled: updatedSnapshot.showUnreadCountBadge)
        }

        guard previousSnapshot.refreshIntervalPreference != updatedSnapshot.refreshIntervalPreference else {
            return
        }

        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: updatedSnapshot,
            policy: BackgroundRefreshPolicy(preference: updatedSnapshot.refreshIntervalPreference)
        )

        do {
            try dependencies.replaceBackgroundRefreshSchedule(
                using: configuration,
                now: .now
            )
        } catch {
            let failureReason = BackgroundRefreshScheduleFailureReason.classify(error).rawValue
            dependencies.logger.error(
                "Failed to replace background refresh schedule after applying settings changes: reason=\(failureReason) error=\(error)"
            )
        }
    }

    func applyUpdatedSettingsSnapshot(_ snapshot: AppSettingsSnapshot) {
        screenState.applyLoadedSnapshot(
            snapshot,
            iCloudSyncStatus: screenState.iCloudSyncStatus,
            syncStatusPresentation: screenState.syncStatusPresentation,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: screenState.settingsInput.isUsingLocalOnlySyncFallbackForCurrentLaunch
        )
    }

    func bootstrapFallbackStatusPresentation(
        for syncBootstrapContext: AppSyncBootstrapContext
    ) -> SettingsSyncStatusPresentation {
        SettingsSyncStatusPresentation(accountAvailability: syncBootstrapContext.accountAvailabilityAtBootstrap)
    }
}
