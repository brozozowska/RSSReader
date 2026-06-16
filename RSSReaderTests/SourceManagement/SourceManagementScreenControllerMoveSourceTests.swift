import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen Controller / Move Source")
@MainActor
struct SourceManagementScreenControllerMoveSourceTests {
    @Test
    func sourceManagementScreenControllerMovesFeedThroughServiceAndRefreshesDestination() throws {
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
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.moveSource, dependencies: harness.dependencies)

        guard case .moveSource(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation")
            return
        }

        #expect(initialDestination.feeds.map(\.title) == ["Move Me"])
        #expect(initialDestination.feeds.first?.currentPlacementTitle == "News")
        #expect(initialDestination.isPrimaryActionEnabled == false)

        controller.handleMoveSourcePlacementSelection(.folder(techFolder.id))
        controller.submitMoveSource(dependencies: harness.dependencies)

        guard case .moveSource(let movedDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation after move")
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
    func sourceManagementScreenControllerMovesFeedDismissesModalAndReloadsAffectedSelectionInAppFlow() throws {
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
        let controller = SourceManagementScreenController()
        let appState = AppState()

        harness.dependencies.appActions.showFolder(named: "News", using: appState)
        let articleReloadIDBeforeMove = appState.articleListReloadID
        let sidebarReloadIDBeforeMove = appState.sidebarReloadID

        harness.dependencies.appActions.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.moveSource, dependencies: harness.dependencies)
        controller.handleMoveSourcePlacementSelection(.folder(techFolder.id))
        controller.submitMoveSource(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeMove)
        #expect(appState.articleListReloadID != articleReloadIDBeforeMove)
        #expect(persistedFeed?.folder?.id == techFolder.id)
    }
}
