import Foundation

struct SidebarScreenState {
    private(set) var feeds: [FeedSidebarItem] = []
    private(set) var unreadSmartCount = 0
    private(set) var starredSmartCount = 0
    private(set) var starredFeedIDs = Set<UUID>()
    private(set) var phase: SidebarContentPhase = .loading
    private(set) var refreshStatus: SidebarRefreshStatus = .idle(lastUpdatedAt: nil)

    var isSyncing: Bool {
        refreshStatus.isSyncing
    }

    mutating func beginLoading(showsFullScreenLoading: Bool) {
        if showsFullScreenLoading {
            phase = .loading
        }

        unreadSmartCount = 0
        starredSmartCount = 0
        starredFeedIDs = []
    }

    mutating func beginRefreshing() {
        refreshStatus = .syncing
    }

    mutating func restoreRefreshStatus(_ previousStatus: SidebarRefreshStatus) {
        refreshStatus = previousStatus
    }

    mutating func applyLoadedSnapshot(
        _ snapshot: SourcesSidebarSnapshotDTO,
        refreshedAt: Date?
    ) {
        feeds = snapshot.feeds
        unreadSmartCount = snapshot.unreadSmartCount
        starredSmartCount = snapshot.starredSmartCount
        starredFeedIDs = snapshot.starredFeedIDs
        phase = snapshot.feeds.isEmpty ? .empty : .loaded

        if let refreshedAt {
            refreshStatus = .idle(lastUpdatedAt: refreshedAt)
        }
    }

    mutating func applyLoadingFailure(_ message: String) {
        feeds = []
        unreadSmartCount = 0
        starredSmartCount = 0
        starredFeedIDs = []
        phase = .failed(message)
    }

    func derivedViewState(
        filter: SourcesFilter,
        expandedFolderNames: Set<String>
    ) -> SidebarScreenDerivedViewState {
        let visibleFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: filter,
            starredFeedIDs: starredFeedIDs
        )
        let folderGroups = FolderSidebarGroup.groups(from: visibleFeeds)
        let visibleFolderRows = folderGroups.flatMap { group in
            var rows: [FolderSectionRow] = [.folder(group)]
            if expandedFolderNames.contains(group.name) {
                rows.append(contentsOf: group.feeds.map(FolderSectionRow.feed))
            }
            return rows
        }

        return SidebarScreenDerivedViewState(
            visibleSmartItems: SmartSidebarItem.visibleItems(
                for: filter,
                hasFeeds: feeds.isEmpty == false
            ),
            visibleFolderRows: visibleFolderRows,
            ungroupedFeeds: SidebarUngroupedFeeds.visibleFeeds(from: visibleFeeds),
            smartCount: SidebarCountPresentation.smartCount(
                for: filter,
                unreadSmartCount: unreadSmartCount,
                starredSmartCount: starredSmartCount
            ),
            shouldDisableScrolling: phase != .loaded,
            primaryLoadingState: primaryLoadingState,
            placeholder: placeholder,
            toolbarState: SidebarToolbarState(refreshStatus: refreshStatus)
        )
    }

    static func previewLoading() -> SidebarScreenState {
        var state = SidebarScreenState()
        state.phase = .loading
        return state
    }

    static func previewFailed(message: String) -> SidebarScreenState {
        var state = SidebarScreenState()
        state.phase = .failed(message)
        return state
    }

    static func previewLoaded(
        snapshot: SourcesSidebarSnapshotDTO,
        refreshedAt: Date? = nil
    ) -> SidebarScreenState {
        var state = SidebarScreenState()
        state.applyLoadedSnapshot(snapshot, refreshedAt: refreshedAt)
        return state
    }
}

private extension SidebarScreenState {
    var primaryLoadingState: SidebarScreenPrimaryLoadingState? {
        guard phase == .loading else {
            return nil
        }

        return SidebarScreenPrimaryLoadingState(title: "Loading Sources")
    }

    var placeholder: SidebarScreenPlaceholderState? {
        switch phase {
        case .loading, .loaded:
            nil
        case .empty:
            SidebarScreenPlaceholderState(
                title: "No Sources",
                systemImage: "dot.radiowaves.left.and.right",
                description: "Add a source to populate the Sources sidebar."
            )
        case .failed(let message):
            SidebarScreenPlaceholderState(
                title: "Unable to Load Sources",
                systemImage: "exclamationmark.triangle",
                description: message
            )
        }
    }
}
