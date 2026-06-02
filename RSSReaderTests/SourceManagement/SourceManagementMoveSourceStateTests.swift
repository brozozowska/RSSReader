import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Move Source State")
@MainActor
struct SourceManagementMoveSourceStateTests {
    @Test
    func moveSourceStateBuildsMoveCommandOnlyAfterPlacementChanges() {
        var state = SourceManagementMoveSourceState()
        let sourceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let folderID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        state.applyContext(
            feeds: [
                SourceManagementFeedSummary(
                    id: sourceID,
                    url: "https://example.com/feed.xml",
                    title: "Example Feed",
                    folderID: nil,
                    folderName: nil
                )
            ],
            folders: [
                SourceManagementFolderSummary(
                    id: folderID,
                    name: "Tech",
                    sortOrder: 0,
                    feedCount: 1
                )
            ],
            selectedFeedID: sourceID
        )

        #expect(state.moveCommand() == nil)

        state.selectPlacement(.folder(folderID))

        let command = state.moveCommand()
        #expect(command?.feedID == sourceID)
        #expect(command?.folderPlacement == .folder(folderID))
        #expect(state.derivedPresentation().isPrimaryActionEnabled)
    }
}
