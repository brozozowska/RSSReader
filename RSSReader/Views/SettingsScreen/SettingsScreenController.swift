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
        case .unreadArticleSortOrder:
            updateUnreadArticleSortOrder(optionID: optionID, dependencies: dependencies)
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
                .importOPML,
                .exportOPML,
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
                .unreadArticleSortOrder,
                .articleRetentionPolicy,
                .articleBodyLinkOpeningPolicy,
                .readerAdjacentNavigationControlsMode,
                .refreshInterval,
                .iCloudSyncStatus,
                .appearance,
                .importOPML,
                .exportOPML,
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
        case .importOPML,
                .exportOPML:
            return
        case .articleOpeningMode,
                .markAsReadOnOpen,
                .articleSourceLinkOpeningPolicy,
                .unreadArticleSortOrder,
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
