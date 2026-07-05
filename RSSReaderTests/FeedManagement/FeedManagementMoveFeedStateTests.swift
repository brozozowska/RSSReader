import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Move Feed State")
@MainActor
struct FeedManagementMoveFeedStateTests {
    @Test
    func moveFeedStateBuildsMoveCommandOnlyAfterPlacementChanges() {
        var state = FeedManagementMoveFeedState()
        let feedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let folderID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        state.applyContext(
            feeds: [
                FeedManagementFeedSummary(
                    id: feedID,
                    url: "https://example.com/feed.xml",
                    title: "Example Feed",
                    folderID: nil,
                    folderName: nil
                )
            ],
            folders: [
                FeedManagementFolderSummary(
                    id: folderID,
                    name: "Tech",
                    sortOrder: 0,
                    feedCount: 1
                )
            ],
            selectedFeedID: feedID
        )

        let initialPresentation = state.derivedPresentation()

        #expect(FeedManagementLocalization.targetFolderTitle == "Папка назначения")
        #expect(FeedManagementLocalization.selectFeedTitle == "Выбранная лента")
        #expect(initialPresentation.sectionOrder == [.destinationFolder, .selectedFeed])
        #expect(initialPresentation.placementTitle == FeedManagementLocalization.targetFolderTitle)
        #expect(initialPresentation.feeds.first?.isSelected == true)
        #expect(state.moveCommand() == nil)

        state.selectPlacement(.folder(folderID))

        let command = state.moveCommand()
        #expect(command?.feedID == feedID)
        #expect(command?.folderPlacement == .folder(folderID))
        #expect(state.derivedPresentation().isPrimaryActionEnabled)
    }
}
