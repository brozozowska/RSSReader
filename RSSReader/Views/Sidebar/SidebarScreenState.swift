import Foundation

struct SidebarScreenState {
    private(set) var folders: [FolderSidebarItem] = []
    private(set) var feeds: [FeedSidebarItem] = []
    private(set) var unreadSmartCount = 0
    private(set) var starredSmartCount = 0
    private(set) var starredFeedIDs = Set<UUID>()
    private(set) var phase: SidebarContentPhase = .loading
    private(set) var refreshStatus: SidebarRefreshStatus = .idle(lastUpdatedAt: nil)
    private(set) var customRefreshState: SidebarCustomRefreshState = .idle

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

    mutating func updateCustomRefreshPullProgress(_ progress: Double) {
        guard customRefreshState.phase != .refreshing else { return }
        customRefreshState = .pulling(progress: progress)
    }

    mutating func beginCustomRefresh() {
        customRefreshState = .refreshing
    }

    mutating func endCustomRefresh() {
        customRefreshState = .idle
    }

    mutating func restoreRefreshStatus(_ previousStatus: SidebarRefreshStatus) {
        refreshStatus = previousStatus
    }

    mutating func applyRefreshFailure(lastUpdatedAt: Date?) {
        refreshStatus = .failed(lastUpdatedAt: lastUpdatedAt)
    }

    mutating func applyLoadedSnapshot(
        _ snapshot: SidebarSnapshotDTO,
        refreshedAt: Date?
    ) {
        folders = snapshot.folders
        feeds = snapshot.feeds
        unreadSmartCount = snapshot.unreadSmartCount
        starredSmartCount = snapshot.starredSmartCount
        starredFeedIDs = snapshot.starredFeedIDs
        phase = snapshot.feeds.isEmpty && snapshot.folders.isEmpty ? .empty : .loaded

        if let refreshedAt {
            refreshStatus = .idle(lastUpdatedAt: refreshedAt)
        }
    }

    mutating func applyLoadingFailure(_ message: String) {
        folders = []
        feeds = []
        unreadSmartCount = 0
        starredSmartCount = 0
        starredFeedIDs = []
        phase = .failed(message)
    }

    func derivedViewState(
        filter: SidebarArticleFilter,
        expandedFolderNames: Set<String>,
        iCloudSyncStatus: ICloudSyncStatus
    ) -> SidebarScreenDerivedViewState {
        let visibleFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: filter,
            starredFeedIDs: starredFeedIDs
        )
        let folderGroups = FolderSidebarGroup.groups(
            from: folders,
            feeds: visibleFeeds,
            filter: filter
        )
        let smartCount = SidebarCountPresentation.smartCount(
            for: filter,
            unreadSmartCount: unreadSmartCount,
            starredSmartCount: starredSmartCount
        )
        let folderRows = folderGroups.flatMap { group in
            var rows: [SidebarFolderSectionRowState] = [
                .folder(
                    SidebarFolderRowState(
                        folderID: group.folderID,
                        name: group.name,
                        count: SidebarCountPresentation.folderCount(for: group, filter: filter),
                        isExpanded: expandedFolderNames.contains(group.name),
                        selection: .folder(group.name)
                    )
                )
            ]
            if expandedFolderNames.contains(group.name) {
                rows.append(
                    contentsOf: group.feeds.map {
                        .feed(
                            SidebarFeedRowState(
                                feed: $0,
                                count: SidebarCountPresentation.feedCount(for: $0, filter: filter),
                                isIndented: true
                            )
                        )
                    }
                )
            }
            return rows
        }
        let ungroupedFeedRows = SidebarUngroupedFeeds.visibleFeeds(from: visibleFeeds).map {
            SidebarFeedRowState(
                feed: $0,
                count: SidebarCountPresentation.feedCount(for: $0, filter: filter),
                isIndented: false
            )
        }

        return SidebarScreenDerivedViewState(
            smartRows: SmartSidebarItem.visibleItems(
                for: filter,
                hasFeeds: feeds.isEmpty == false
            ).map { SidebarSmartRowState(item: $0, count: smartCount) },
            folderRows: folderRows,
            ungroupedFeedRows: ungroupedFeedRows,
            shouldDisableScrolling: phase != .loaded,
            primaryLoadingState: primaryLoadingState,
            placeholder: placeholder,
            toolbarState: SidebarToolbarState(
                refreshStatus: refreshStatus,
                iCloudSyncStatus: iCloudSyncStatus
            )
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
        snapshot: SidebarSnapshotDTO,
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

        return SidebarScreenPrimaryLoadingState(title: SidebarLocalization.loadingTitle)
    }

    var placeholder: SidebarScreenPlaceholderState? {
        switch phase {
        case .loading, .loaded:
            nil
        case .empty:
            SidebarScreenPlaceholderState(
                title: SidebarLocalization.emptyTitle,
                systemImage: "dot.radiowaves.left.and.right",
                description: SidebarLocalization.emptyDescription
            )
        case .failed(let message):
            SidebarScreenPlaceholderState(
                title: SidebarLocalization.loadFailureTitle,
                systemImage: "exclamationmark.triangle",
                description: message
            )
        }
    }
}
