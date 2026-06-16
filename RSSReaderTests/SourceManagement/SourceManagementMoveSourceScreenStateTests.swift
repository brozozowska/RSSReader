import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen State / Move Source")
@MainActor
struct SourceManagementMoveSourceScreenStateTests {
    @Test
    func sourceManagementScreenStateBuildsMoveSourcePresentationWithFeedAndPlacementSelection() {
        var state = SourceManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let techFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        state.applyMoveSourceContext(
            feeds: [
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    url: "https://example.com/apple.xml",
                    title: "Apple Feed",
                    folderID: newsFolderID,
                    folderName: "News"
                ),
                SourceManagementFeedSummary(
                    id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                    url: "https://example.com/beta.xml",
                    title: "Beta Feed",
                    folderID: nil,
                    folderName: nil
                )
            ],
            folders: [
                SourceManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 2
                ),
                SourceManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 6
                )
            ]
        )
        state.presentScenario(.moveSource)

        guard case .moveSource(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation")
            return
        }

        #expect(initialDestination.feeds.map(\.title) == ["Apple Feed", "Beta Feed"])
        #expect(initialDestination.feeds.first?.isSelected == true)
        #expect(initialDestination.placementOptions.map(\.title) == [SourceManagementLocalization.ungroupedTitle, "News", "Tech"])
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.selectMoveSourcePlacement(.folder(techFolderID))

        guard case .moveSource(let changedDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation after placement change")
            return
        }

        #expect(changedDestination.isPrimaryActionEnabled)
        #expect(changedDestination.placementOptions.last?.isSelected == true)
    }

    @Test
    func sourceManagementScreenStatePreselectsRequestedFeedForMoveSourceContext() {
        var state = SourceManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let techFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let appleFeedID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let betaFeedID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

        state.applyMoveSourceContext(
            feeds: [
                SourceManagementFeedSummary(
                    id: appleFeedID,
                    url: "https://example.com/apple.xml",
                    title: "Apple Feed",
                    folderID: newsFolderID,
                    folderName: "News"
                ),
                SourceManagementFeedSummary(
                    id: betaFeedID,
                    url: "https://example.com/beta.xml",
                    title: "Beta Feed",
                    folderID: techFolderID,
                    folderName: "Tech"
                )
            ],
            folders: [
                SourceManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 2
                ),
                SourceManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 6
                )
            ],
            selectedFeedID: betaFeedID
        )
        state.presentScenario(.moveSource)

        guard case .moveSource(let destination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation")
            return
        }

        #expect(destination.feeds.first(where: { $0.id == appleFeedID })?.isSelected == false)
        #expect(destination.feeds.first(where: { $0.id == betaFeedID })?.isSelected == true)
        #expect(destination.placementOptions.first(where: { $0.title == "Tech" })?.isSelected == true)
        #expect(destination.isPrimaryActionEnabled == false)
    }
}
