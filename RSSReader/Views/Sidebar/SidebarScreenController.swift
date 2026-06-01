import Foundation
import Observation

@MainActor
@Observable
final class SidebarScreenController {
    var screenState: SidebarScreenState
    private(set) var expandedFolderNames: Set<String>
    let isPreviewMode: Bool

    init(previewScreenState: SidebarScreenState? = nil) {
        self.screenState = previewScreenState ?? SidebarScreenState()
        self.expandedFolderNames = []
        self.isPreviewMode = previewScreenState != nil
    }

    func viewState(
        filter: SourcesFilter,
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
        filter: SourcesFilter,
        refreshedAt: Date? = nil
    ) async -> SidebarSelection? {
        screenState.beginLoading(showsFullScreenLoading: showsFullScreenLoading)

        guard let sourcesSidebarQueryService = dependencies.sourcesSidebarQueryService else {
            screenState.applyLoadingFailure("Sources are unavailable in the current app environment.")
            return currentSelection
        }

        do {
            let snapshot = try sourcesSidebarQueryService.fetchSnapshot()
            let effectiveRefreshedAt = refreshedAt ?? lastSourcesRefreshAt(dependencies: dependencies)
            screenState.applyLoadedSnapshot(snapshot, refreshedAt: effectiveRefreshedAt)
            syncExpandedFolderNames(filter: filter)
            return resolvedSelection(currentSelection: currentSelection, filter: filter)
        } catch {
            dependencies.logger.error("Failed to load sidebar feeds: \(error)")
            screenState.applyLoadingFailure("Unable to load sources right now. Try again.")
            return currentSelection
        }
    }

    func refreshSources(
        dependencies: AppDependencies,
        appState: AppState,
        currentSelection: SidebarSelection?,
        filter: SourcesFilter
    ) async -> SidebarSelection? {
        guard screenState.isSyncing == false else {
            return currentSelection
        }

        let previousStatus = screenState.refreshStatus
        screenState.beginRefreshing()
        let result = await dependencies.appActions.refreshVisibleSources(using: appState)
        let refreshedAt = result.flatMap(Self.sourcesRefreshDisplayDate)
        let adjustedSelection = await loadFeeds(
            showsFullScreenLoading: false,
            dependencies: dependencies,
            currentSelection: currentSelection,
            filter: filter,
            refreshedAt: refreshedAt
        )

        if refreshedAt == nil {
            screenState.restoreRefreshStatus(previousStatus)
        }

        return adjustedSelection
    }

    private func lastSourcesRefreshAt(dependencies: AppDependencies) -> Date? {
        do {
            return try dependencies.appSettingsService?.fetchSettings().lastSourcesRefreshAt
        } catch {
            dependencies.logger.error("Failed to load last sources refresh timestamp: \(error)")
            return nil
        }
    }

    private static func sourcesRefreshDisplayDate(from result: FeedRefreshBatchResult) -> Date? {
        guard result.summary.fetchedCount + result.summary.notModifiedCount > 0 else {
            return nil
        }

        return result.finishedAt
    }

    func resolvedSelection(
        currentSelection: SidebarSelection?,
        filter: SourcesFilter
    ) -> SidebarSelection? {
        let visibleFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: screenState.feeds,
            filter: filter,
            starredFeedIDs: screenState.starredFeedIDs
        )
        let folderGroups = FolderSidebarGroup.groups(
            from: screenState.folders,
            feeds: visibleFeeds,
            filter: filter
        )

        return SidebarSelectionBehavior.resolvedSelection(
            currentSelection: currentSelection,
            filter: filter,
            visibleFeedIDs: Set(visibleFeeds.map(\.id)),
            visibleFolderNames: Set(folderGroups.map(\.name))
        )
    }

    func visibleFolderNames(filter: SourcesFilter) -> Set<String> {
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

    func syncExpandedFolderNames(filter: SourcesFilter) {
        expandedFolderNames = visibleFolderNames(filter: filter)
    }
}
