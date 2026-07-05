import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Screen State / Move Feed")
@MainActor
struct FeedManagementMoveFeedScreenStateTests {
    @Test
    func feedManagementScreenStateBuildsMoveFeedPresentationWithFeedAndPlacementSelection() {
        var state = FeedManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let techFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        state.applyMoveFeedContext(
            feeds: [
                FeedManagementFeedSummary(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    url: "https://example.com/apple.xml",
                    title: "Apple Feed",
                    folderID: newsFolderID,
                    folderName: "News"
                ),
                FeedManagementFeedSummary(
                    id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                    url: "https://example.com/beta.xml",
                    title: "Beta Feed",
                    folderID: nil,
                    folderName: nil
                )
            ],
            folders: [
                FeedManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 2
                ),
                FeedManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 6
                )
            ]
        )
        state.presentScenario(.moveFeed)

        guard case .moveFeed(let initialDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-feed destination presentation")
            return
        }

        #expect(FeedManagementLocalization.targetFolderTitle == "Папка назначения")
        #expect(FeedManagementLocalization.selectFeedTitle == "Выбранная лента")
        #expect(initialDestination.sectionOrder == [.destinationFolder, .selectedFeed])
        #expect(initialDestination.placementTitle == FeedManagementLocalization.targetFolderTitle)
        #expect(initialDestination.feeds.map(\.title) == ["Apple Feed", "Beta Feed"])
        #expect(initialDestination.feeds.first?.isSelected == true)
        #expect(initialDestination.placementOptions.map(\.title) == [FeedManagementLocalization.ungroupedTitle, "News", "Tech"])
        #expect(initialDestination.isPrimaryActionEnabled == false)

        state.selectMoveFeedPlacement(.folder(techFolderID))

        guard case .moveFeed(let changedDestination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-feed destination presentation after placement change")
            return
        }

        #expect(changedDestination.isPrimaryActionEnabled)
        #expect(changedDestination.placementOptions.last?.isSelected == true)
    }

    @Test
    func feedManagementScreenStatePreselectsRequestedFeedForMoveFeedContext() {
        var state = FeedManagementScreenState.makePreviewFixture()
        let newsFolderID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let techFolderID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let appleFeedID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let betaFeedID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

        state.applyMoveFeedContext(
            feeds: [
                FeedManagementFeedSummary(
                    id: appleFeedID,
                    url: "https://example.com/apple.xml",
                    title: "Apple Feed",
                    folderID: newsFolderID,
                    folderName: "News"
                ),
                FeedManagementFeedSummary(
                    id: betaFeedID,
                    url: "https://example.com/beta.xml",
                    title: "Beta Feed",
                    folderID: techFolderID,
                    folderName: "Tech"
                )
            ],
            folders: [
                FeedManagementFolderSummary(
                    id: newsFolderID,
                    name: "News",
                    sortOrder: 0,
                    feedCount: 2
                ),
                FeedManagementFolderSummary(
                    id: techFolderID,
                    name: "Tech",
                    sortOrder: 1,
                    feedCount: 6
                )
            ],
            selectedFeedID: betaFeedID
        )
        state.presentScenario(.moveFeed)

        guard case .moveFeed(let destination)? = state.derivedViewState().presentedDestination else {
            Issue.record("Expected move-feed destination presentation")
            return
        }

        #expect(destination.feeds.first(where: { $0.id == appleFeedID })?.isSelected == false)
        #expect(destination.feeds.first(where: { $0.id == betaFeedID })?.isSelected == true)
        #expect(destination.placementOptions.first(where: { $0.title == "Tech" })?.isSelected == true)
        #expect(destination.isPrimaryActionEnabled == false)
    }
}
