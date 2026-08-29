import Foundation
import Observation

@MainActor
@Observable
final class SidebarScreenController {
    var screenState: SidebarScreenState
    private(set) var expandedFolderNames: Set<String>
    let isPreviewMode: Bool
    private var pendingRetry: PendingManualFeedRefreshRetry?

    init(previewScreenState: SidebarScreenState? = nil) {
        self.screenState = previewScreenState ?? SidebarScreenState()
        self.expandedFolderNames = []
        self.isPreviewMode = previewScreenState != nil
    }

    func viewState(
        filter: SidebarArticleFilter,
        iCloudSyncStatus: ICloudSyncStatus
    ) -> SidebarScreenDerivedViewState {
        screenState.derivedViewState(
            filter: filter,
            expandedFolderNames: expandedFolderNames,
            iCloudSyncStatus: iCloudSyncStatus
        )
    }

    func loadFeeds(
        showsFullScreenLoading: Bool,
        dependencies: AppDependencies,
        currentSelection: SidebarSelection?,
        filter: SidebarArticleFilter,
        refreshedAt: Date? = nil
    ) async -> SidebarSelection? {
        screenState.beginLoading(showsFullScreenLoading: showsFullScreenLoading)

        guard let sidebarQueryService = dependencies.sidebarQueryService else {
            screenState.applyLoadingFailure(SidebarLocalization.unavailablePreviewMessage)
            return currentSelection
        }

        do {
            let snapshot = try sidebarQueryService.fetchSnapshot()
            let effectiveRefreshedAt = refreshedAt ?? lastFeedsRefreshAt(dependencies: dependencies)
            screenState.applyLoadedSnapshot(snapshot, refreshedAt: effectiveRefreshedAt)
            syncExpandedFolderNames(filter: filter)
            return resolvedSelection(currentSelection: currentSelection, filter: filter)
        } catch {
            dependencies.logger.error("Failed to load sidebar feeds: \(error)")
            screenState.applyLoadingFailure(SidebarLocalization.genericLoadFailureMessage)
            return currentSelection
        }
    }

    func refreshSidebar(
        dependencies: AppDependencies,
        appState: AppState,
        currentSelection: SidebarSelection?,
        filter: SidebarArticleFilter
    ) async -> SidebarSelection? {
        guard screenState.isSyncing == false else {
            return currentSelection
        }
        guard appState.selectedSidebarSelection == currentSelection,
              appState.selectedSidebarArticleFilter == filter else {
            return appState.selectedSidebarSelection
        }

        let refreshContext = ManualFeedRefreshContext(
            selection: currentSelection,
            sidebarArticleFilter: filter
        )
        let previousStatus = screenState.refreshStatus
        screenState.beginRefreshing()
        let result: FeedRefreshBatchResult?
        if let pendingRetry, pendingRetry.context == refreshContext {
            result = await dependencies.appActions.retryFeeds(
                pendingRetry.feedIDs,
                context: refreshContext,
                using: appState
            )
        } else {
            pendingRetry = nil
            result = await dependencies.appActions.refreshSelection(
                refreshContext,
                using: appState
            )
        }

        guard appState.selectedSidebarSelection == refreshContext.selection,
              appState.selectedSidebarArticleFilter == refreshContext.sidebarArticleFilter else {
            pendingRetry = nil
            screenState.restoreRefreshStatus(previousStatus)
            return appState.selectedSidebarSelection
        }

        if let retryFeedIDs = result?.retryFeedIDs, retryFeedIDs.isEmpty == false {
            pendingRetry = PendingManualFeedRefreshRetry(
                context: refreshContext,
                feedIDs: retryFeedIDs
            )
        } else if result != nil {
            pendingRetry = nil
        }
        let refreshedAt = result.flatMap {
            Self.sidebarRefreshDisplayDate(from: $0, context: refreshContext)
        }
        let adjustedSelection = await loadFeeds(
            showsFullScreenLoading: false,
            dependencies: dependencies,
            currentSelection: currentSelection,
            filter: filter,
            refreshedAt: refreshedAt
        )

        if result?.hasUnsuccessfulOutcome == true {
            screenState.applyRefreshFailure(lastUpdatedAt: previousStatus.lastUpdatedAt)
        } else if result != nil, refreshedAt == nil {
            screenState.restoreRefreshStatus(.idle(lastUpdatedAt: previousStatus.lastUpdatedAt))
        } else if refreshedAt == nil {
            screenState.restoreRefreshStatus(previousStatus)
        }

        return adjustedSelection
    }

    private func lastFeedsRefreshAt(dependencies: AppDependencies) -> Date? {
        do {
            return try dependencies.appSettingsService?.fetchSettings().lastFeedsRefreshAt
        } catch {
            dependencies.logger.error("Failed to load last feeds refresh timestamp: \(error)")
            return nil
        }
    }

    private static func sidebarRefreshDisplayDate(
        from result: FeedRefreshBatchResult,
        context: ManualFeedRefreshContext
    ) -> Date? {
        guard context.scope == .allFeeds,
              result.isCompleteSuccess,
              result.summary.fetchedCount + result.summary.notModifiedCount > 0 else {
            return nil
        }

        return result.finishedAt
    }

    func resolvedSelection(
        currentSelection: SidebarSelection?,
        filter: SidebarArticleFilter
    ) -> SidebarSelection? {
        return SidebarSelectionBehavior.resolvedSelection(
            currentSelection: currentSelection,
            filter: filter,
            existingFeedIDs: Set(screenState.feeds.map(\.id)),
            existingFolderNames: Set(screenState.folders.map(\.name))
        )
    }

    func visibleFolderNames(filter: SidebarArticleFilter) -> Set<String> {
        let visibleFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: screenState.feeds,
            filter: filter,
            starredFeedIDs: screenState.starredFeedIDs
        )

        return Set(
            FolderSidebarGroup.groups(
                from: screenState.folders,
                feeds: visibleFeeds,
                filter: filter
            ).map(\.name)
        )
    }

    func toggleFolderExpansion(named folderName: String) {
        if expandedFolderNames.contains(folderName) {
            expandedFolderNames.remove(folderName)
        } else {
            expandedFolderNames.insert(folderName)
        }
    }

    func syncExpandedFolderNames(filter: SidebarArticleFilter) {
        expandedFolderNames = visibleFolderNames(filter: filter)
    }
}

private struct PendingManualFeedRefreshRetry {
    let context: ManualFeedRefreshContext
    let feedIDs: [UUID]
}
