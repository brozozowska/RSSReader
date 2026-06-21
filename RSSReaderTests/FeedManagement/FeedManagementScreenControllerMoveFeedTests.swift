import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Screen Controller / Move Feed")
@MainActor
struct FeedManagementScreenControllerMoveFeedTests {
    @Test
    func feedManagementScreenControllerMovesFeedThroughServiceAndRefreshesDestination() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let techFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/move-me.xml",
                title: "Move Me",
                kind: .rss,
                folder: newsFolder
            )
        )
        let controller = FeedManagementScreenController()

        controller.handleScenarioSelection(.moveFeed, dependencies: harness.dependencies)

        guard case .moveFeed(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-feed destination presentation")
            return
        }

        #expect(initialDestination.feeds.map(\.title) == ["Move Me"])
        #expect(initialDestination.feeds.first?.currentPlacementTitle == "News")
        #expect(initialDestination.isPrimaryActionEnabled == false)

        controller.handleMoveFeedPlacementSelection(.folder(techFolder.id))
        controller.submitMoveFeed(dependencies: harness.dependencies)

        guard case .moveFeed(let movedDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-feed destination presentation after move")
            return
        }

        let persistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(movedDestination.feedback?.kind == .success)
        #expect(movedDestination.feedback?.detail?.contains("Tech") == true)
        #expect(movedDestination.feeds.first?.currentPlacementTitle == "Tech")
        #expect(movedDestination.isPrimaryActionEnabled == false)
        #expect(persistedFeed?.folder?.id == techFolder.id)
    }

    @Test
    func feedManagementScreenControllerMovesFeedDismissesModalAndReloadsAffectedSelectionInAppFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let techFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/app-move.xml",
                title: "App Move",
                kind: .rss,
                folder: newsFolder
            )
        )
        let controller = FeedManagementScreenController()
        let appState = AppState()

        harness.dependencies.appActions.showFolder(named: "News", using: appState)
        let articleReloadIDBeforeMove = appState.articleListReloadID
        let sidebarReloadIDBeforeMove = appState.sidebarReloadID

        harness.dependencies.appActions.showFeedManagement(using: appState)
        controller.handleScenarioSelection(.moveFeed, dependencies: harness.dependencies)
        controller.handleMoveFeedPlacementSelection(.folder(techFolder.id))
        controller.submitMoveFeed(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeMove)
        #expect(appState.articleListReloadID != articleReloadIDBeforeMove)
        #expect(persistedFeed?.folder?.id == techFolder.id)
    }
}
