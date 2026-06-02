import Foundation

enum SettingsScreenPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct SettingsScreenState {
    private(set) var phase: SettingsScreenPhase = .loading
    private(set) var settingsSnapshot = AppSettingsSnapshot()
    private(set) var settingsInput = SettingsScreenInput()
    private(set) var iCloudSyncStatus: ICloudSyncStatus = .disabled
    private(set) var syncStatusPresentation: SettingsSyncStatusPresentation = .disabled
    private(set) var hasArticleImageCache = false
    private(set) var hasSourceIconCache = false
    private(set) var hasArchivedArticles = false
    private(set) var sections: [SettingsScreenSectionPresentation] = []

    mutating func beginLoading() {
        phase = .loading
    }

    mutating func applyLoadedSnapshot(
        _ snapshot: AppSettingsSnapshot,
        iCloudSyncStatus: ICloudSyncStatus = .disabled,
        syncStatusPresentation: SettingsSyncStatusPresentation? = nil,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool = false
    ) {
        let input = SettingsScreenInputBuilder.build(
            from: snapshot,
            iCloudSyncStatus: iCloudSyncStatus,
            syncStatusPresentation: syncStatusPresentation,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: isUsingLocalOnlySyncFallbackForCurrentLaunch
        )
        applyLoadedSnapshot(snapshot, input: input)
    }

    mutating func applyLoadedSnapshot(
        _ snapshot: AppSettingsSnapshot,
        input: SettingsScreenInput
    ) {
        settingsSnapshot = snapshot
        settingsInput = input
        iCloudSyncStatus = input.iCloudSyncStatus
        syncStatusPresentation = input.syncStatusPresentation
        sections = SettingsScreenPresentationBuilder.buildSections(
            from: input,
            hasArticleImageCache: hasArticleImageCache,
            hasSourceIconCache: hasSourceIconCache,
            hasArchivedArticles: hasArchivedArticles
        )
        phase = .loaded
    }

    mutating func applyDraftInput(_ input: SettingsScreenInput) {
        settingsInput = input
        iCloudSyncStatus = input.iCloudSyncStatus
        syncStatusPresentation = input.syncStatusPresentation
        sections = SettingsScreenPresentationBuilder.buildSections(
            from: input,
            hasArticleImageCache: hasArticleImageCache,
            hasSourceIconCache: hasSourceIconCache,
            hasArchivedArticles: hasArchivedArticles
        )
    }

    mutating func applyArticleImageCacheAvailability(_ hasCache: Bool) {
        hasArticleImageCache = hasCache
        sections = SettingsScreenPresentationBuilder.buildSections(
            from: settingsInput,
            hasArticleImageCache: hasArticleImageCache,
            hasSourceIconCache: hasSourceIconCache,
            hasArchivedArticles: hasArchivedArticles
        )
    }

    mutating func applySourceIconCacheAvailability(_ hasCache: Bool) {
        hasSourceIconCache = hasCache
        sections = SettingsScreenPresentationBuilder.buildSections(
            from: settingsInput,
            hasArticleImageCache: hasArticleImageCache,
            hasSourceIconCache: hasSourceIconCache,
            hasArchivedArticles: hasArchivedArticles
        )
    }

    mutating func applyArchivedArticlesAvailability(_ hasArchivedArticles: Bool) {
        self.hasArchivedArticles = hasArchivedArticles
        sections = SettingsScreenPresentationBuilder.buildSections(
            from: settingsInput,
            hasArticleImageCache: hasArticleImageCache,
            hasSourceIconCache: hasSourceIconCache,
            hasArchivedArticles: self.hasArchivedArticles
        )
    }

    mutating func applyLoadingFailure(_ message: String) {
        sections = []
        phase = .failed(message)
    }

    func derivedViewState() -> SettingsScreenViewState {
        SettingsScreenViewState(
            sections: sections,
            primaryLoadingState: primaryLoadingState,
            placeholder: placeholder,
            canApplyChanges: canApplyChanges
        )
    }

    func pendingSettingsSnapshot() -> AppSettingsSnapshot {
        draftSnapshot
    }

    static func previewLoading() -> SettingsScreenState {
        var state = SettingsScreenState()
        state.beginLoading()
        return state
    }

    static func previewFailed(message: String) -> SettingsScreenState {
        var state = SettingsScreenState()
        state.applyLoadingFailure(message)
        return state
    }

    static func previewLoaded(
        snapshot: AppSettingsSnapshot,
        iCloudSyncStatus: ICloudSyncStatus = .disabled,
        syncStatusPresentation: SettingsSyncStatusPresentation? = nil,
        isUsingLocalOnlySyncFallbackForCurrentLaunch: Bool = false
    ) -> SettingsScreenState {
        let input = SettingsScreenInputBuilder.build(
            from: snapshot,
            iCloudSyncStatus: iCloudSyncStatus,
            syncStatusPresentation: syncStatusPresentation,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: isUsingLocalOnlySyncFallbackForCurrentLaunch
        )
        return previewLoaded(snapshot: snapshot, input: input)
    }

    static func previewLoaded(
        snapshot: AppSettingsSnapshot,
        input: SettingsScreenInput
    ) -> SettingsScreenState {
        var state = SettingsScreenState()
        state.applyLoadedSnapshot(snapshot, input: input)
        return state
    }
}

private extension SettingsScreenState {
    var canApplyChanges: Bool {
        guard phase == .loaded else { return false }
        return draftSnapshot != settingsSnapshot
    }

    var draftSnapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            articleOpeningMode: settingsInput.articleOpeningMode,
            selectedSourcesFilterRawValue: settingsSnapshot.selectedSourcesFilterRawValue,
            refreshIntervalPreference: settingsInput.refreshIntervalPreference,
            useiCloudSync: settingsInput.useiCloudSync,
            markAsReadOnOpen: settingsInput.markAsReadOnOpen,
            askBeforeMarkingAllAsRead: settingsInput.askBeforeMarkingAllAsRead,
            showUnreadCountBadge: settingsInput.showUnreadCountBadge,
            unreadArticleSortMode: settingsInput.unreadArticleSortOrder.unreadArticleSortMode,
            articleRetentionPolicy: settingsInput.articleRetentionPolicy,
            articleBodyLinkOpeningPolicy: settingsInput.articleBodyLinkOpeningPolicy,
            articleSourceLinkOpeningPolicy: settingsInput.articleSourceLinkOpeningPolicy,
            readerAdjacentNavigationControlsMode: settingsInput.readerAdjacentNavigationControlsMode,
            interfaceThemeMode: settingsInput.interfaceThemeMode,
            lastSourcesRefreshAt: settingsSnapshot.lastSourcesRefreshAt
        )
    }

    var primaryLoadingState: SettingsScreenPrimaryLoadingState? {
        guard phase == .loading else {
            return nil
        }

        return SettingsScreenPrimaryLoadingState(title: "Loading Settings")
    }

    var placeholder: SettingsScreenPlaceholderState? {
        guard case .failed(let message) = phase else {
            return nil
        }

        return SettingsScreenPlaceholderState(
            title: "Unable to Load Settings",
            systemImage: "exclamationmark.triangle",
            description: message,
            actionTitle: "Retry"
        )
    }
}
