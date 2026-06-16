import Foundation
import Testing
@testable import RSSReader

@Suite("Sidebar / Screen State")
@MainActor
struct SidebarScreenStateTests {
    @Test
    func sidebarScreenStateExposesPrimaryLoadingStateThroughDerivedViewState() {
        let state = SidebarScreenState()

        let viewState = state.derivedViewState(
            filter: .allItems,
            expandedFolderNames: [],
            iCloudSyncStatus: .disabled
        )

        #expect(state.phase == .loading)
        #expect(viewState.primaryLoadingState?.title == SidebarLocalization.loadingTitle)
        #expect(viewState.placeholder == nil)
        #expect(viewState.shouldDisableScrolling)
        #expect(viewState.smartRows.isEmpty)
        #expect(state.customRefreshState == .idle)
    }

    @Test
    func sidebarScreenStateTracksCustomRefreshGestureSeparatelyFromRefreshStatus() {
        var state = SidebarScreenState()

        state.updateCustomRefreshPullProgress(0.5)

        #expect(state.customRefreshState.phase == .pulling)
        #expect(state.customRefreshState.pullProgress == 0.5)
        #expect(state.refreshStatus == .idle(lastUpdatedAt: nil))

        state.updateCustomRefreshPullProgress(1)

        #expect(state.customRefreshState.phase == .ready)
        #expect(state.refreshStatus == .idle(lastUpdatedAt: nil))

        state.beginCustomRefresh()
        state.beginRefreshing()

        #expect(state.customRefreshState == .refreshing)
        #expect(state.refreshStatus == .syncing)

        state.updateCustomRefreshPullProgress(0.2)

        #expect(state.customRefreshState == .refreshing)

        state.endCustomRefresh()

        #expect(state.customRefreshState == .idle)
        #expect(state.refreshStatus == .syncing)
    }

    @Test
    func sidebarScreenStateBuildsLoadedDerivedViewStateFromSnapshot() {
        let feed = Feed(
            id: UUID(),
            url: "https://www.theverge.com/rss/index.xml",
            title: "The Verge",
            folder: Folder(name: "Tech")
        )
        let feedSidebarItem = FeedSidebarItem(
            feed: feed,
            unreadCount: 2,
            starredCount: 1
        )
        let snapshot = SidebarSnapshotDTO(
            feeds: [feedSidebarItem],
            unreadSmartCount: 2,
            starredSmartCount: 1,
            starredFeedIDs: [feed.id]
        )
        let state = SidebarScreenState.previewLoaded(snapshot: snapshot)

        let viewState = state.derivedViewState(
            filter: .allItems,
            expandedFolderNames: ["Tech"],
            iCloudSyncStatus: .disabled
        )

        #expect(state.phase == .loaded)
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.smartRows.map(\.item) == [.allItems])
        #expect(viewState.smartRows.first?.count == 2)
        #expect(viewState.folderRows.count == 2)
        #expect(viewState.ungroupedFeedRows.isEmpty)
        #expect(viewState.shouldDisableScrolling == false)

        guard case .folder(let folderRow)? = viewState.folderRows.first else {
            Issue.record("Expected first folder row in SidebarScreenDerivedViewState")
            return
        }
        #expect(folderRow.name == "Tech")
        #expect(folderRow.isExpanded)

        guard case .feed(let feedRow)? = viewState.folderRows.last else {
            Issue.record("Expected nested feed row in SidebarScreenDerivedViewState")
            return
        }
        #expect(feedRow.title == "The Verge")
        #expect(feedRow.isIndented)
    }

    @Test
    func sidebarScreenStateShowsEmptyFoldersFromSnapshot() {
        let emptyFolderID = UUID()
        let snapshot = SidebarSnapshotDTO(
            folders: [
                FolderSidebarItem(
                    id: emptyFolderID,
                    name: "Empty",
                    sortOrder: 0
                )
            ],
            feeds: [],
            unreadSmartCount: 0,
            starredSmartCount: 0,
            starredFeedIDs: []
        )
        let state = SidebarScreenState.previewLoaded(snapshot: snapshot)

        let viewState = state.derivedViewState(
            filter: .allItems,
            expandedFolderNames: ["Empty"],
            iCloudSyncStatus: .disabled
        )

        #expect(state.phase == .loaded)
        #expect(viewState.placeholder == nil)
        #expect(viewState.shouldDisableScrolling == false)
        #expect(viewState.smartRows.isEmpty)
        #expect(viewState.folderRows.count == 1)
        #expect(viewState.ungroupedFeedRows.isEmpty)

        guard case .folder(let folderRow)? = viewState.folderRows.first else {
            Issue.record("Expected empty folder row in SidebarScreenDerivedViewState")
            return
        }

        #expect(folderRow.folderID == emptyFolderID)
        #expect(folderRow.name == "Empty")
        #expect(folderRow.count == 0)
        #expect(folderRow.isExpanded)
    }

    @Test
    func sidebarScreenStateHidesEmptyFoldersWhenUnreadFilterIsActive() {
        let emptyFolderID = UUID()
        let snapshot = SidebarSnapshotDTO(
            folders: [
                FolderSidebarItem(
                    id: emptyFolderID,
                    name: "Empty",
                    sortOrder: 0
                )
            ],
            feeds: [],
            unreadSmartCount: 0,
            starredSmartCount: 0,
            starredFeedIDs: []
        )
        let state = SidebarScreenState.previewLoaded(snapshot: snapshot)

        let viewState = state.derivedViewState(
            filter: .unread,
            expandedFolderNames: ["Empty"],
            iCloudSyncStatus: .disabled
        )

        #expect(state.phase == .loaded)
        #expect(viewState.folderRows.isEmpty)
    }

    @Test
    func sidebarScreenStateHidesFoldersWithoutVisibleStarredFeedsWhenStarredFilterIsActive() {
        let emptyFolderID = UUID()
        let folder = Folder(name: "Tech")
        let visibleFeedID = UUID()
        let hiddenFeedID = UUID()
        let visibleFeed = FeedSidebarItem(
            feed: Feed(
                id: visibleFeedID,
                url: "https://example.com/visible.xml",
                title: "Visible",
                folder: folder
            ),
            unreadCount: 0,
            starredCount: 2
        )
        let hiddenFeed = FeedSidebarItem(
            feed: Feed(
                id: hiddenFeedID,
                url: "https://example.com/hidden.xml",
                title: "Hidden",
                folder: folder
            ),
            unreadCount: 1,
            starredCount: 0
        )
        let snapshot = SidebarSnapshotDTO(
            folders: [
                FolderSidebarItem(
                    id: emptyFolderID,
                    name: "Empty",
                    sortOrder: 0
                ),
                FolderSidebarItem(
                    id: folder.id,
                    name: folder.name,
                    sortOrder: 1
                )
            ],
            feeds: [visibleFeed, hiddenFeed],
            unreadSmartCount: 1,
            starredSmartCount: 2,
            starredFeedIDs: [visibleFeedID]
        )
        let state = SidebarScreenState.previewLoaded(snapshot: snapshot)

        let viewState = state.derivedViewState(
            filter: .starred,
            expandedFolderNames: ["Tech"],
            iCloudSyncStatus: .disabled
        )

        #expect(viewState.folderRows.count == 2)

        guard case .folder(let folderRow)? = viewState.folderRows.first else {
            Issue.record("Expected visible folder row")
            return
        }
        guard case .feed(let feedRow)? = viewState.folderRows.last else {
            Issue.record("Expected nested visible feed row")
            return
        }

        #expect(folderRow.name == "Tech")
        #expect(folderRow.count == 2)
        #expect(feedRow.id == visibleFeedID)
        #expect(feedRow.title == "Visible")
    }
}
