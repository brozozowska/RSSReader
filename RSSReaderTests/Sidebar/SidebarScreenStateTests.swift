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
        #expect(viewState.primaryLoadingState?.title == "Loading Sources")
        #expect(viewState.placeholder == nil)
        #expect(viewState.shouldDisableScrolling)
        #expect(viewState.smartRows.isEmpty)
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
        let snapshot = SourcesSidebarSnapshotDTO(
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
}
