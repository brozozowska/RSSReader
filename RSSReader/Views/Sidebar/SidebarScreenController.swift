import Foundation
import Observation

@MainActor
@Observable
final class SidebarScreenController {
    var screenState: SidebarScreenState

    init(previewScreenState: SidebarScreenState? = nil) {
        self.screenState = previewScreenState ?? SidebarScreenState()
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
            screenState.applyLoadedSnapshot(snapshot, refreshedAt: refreshedAt)
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
        let result = await dependencies.refreshVisibleSources(using: appState)
        let refreshedAt = result?.finishedAt
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

    func resolvedSelection(
        currentSelection: SidebarSelection?,
        filter: SourcesFilter
    ) -> SidebarSelection? {
        let visibleFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: screenState.feeds,
            filter: filter,
            starredFeedIDs: screenState.starredFeedIDs
        )
        let folderGroups = FolderSidebarGroup.groups(from: visibleFeeds)

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

        return Set(FolderSidebarGroup.groups(from: visibleFeeds).map(\.name))
    }
}
