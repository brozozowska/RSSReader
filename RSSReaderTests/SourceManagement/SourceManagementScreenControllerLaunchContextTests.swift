import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen Controller / Launch Contexts")
@MainActor
struct SourceManagementScreenControllerLaunchContextTests {
    @Test
    func sourceManagementScreenControllerEditsFolderFromSidebarLaunchContextAndRetargetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let controller = SourceManagementScreenController()
        let sidebarReloadIDBeforeEdit = appState.sidebarReloadID

        harness.dependencies.appActions.showFolder(named: "News", using: appState)
        harness.dependencies.appActions.showFolderEditor(named: "News", using: appState)
        controller.handleLaunchContext(.editFolder(folder.id), dependencies: harness.dependencies)

        guard case .createFolder(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation for folder editor launch context")
            return
        }

        #expect(initialDestination.title == SourceManagementLocalization.editFolderTitle)
        #expect(initialDestination.nameInput == "News")

        controller.handleCreateFolderNameChange("World News")
        controller.submitCreateFolder(dependencies: harness.dependencies, appState: appState)

        let renamedFolder = try #require(try harness.folderRepository.fetchFolder(id: folder.id))

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeEdit)
        #expect(renamedFolder.name == "World News")
        #expect(renamedFolder.sortOrder == 0)
    }

    @Test
    func sourceManagementScreenControllerOrganizesFeedFromSidebarLaunchContextWithoutPreview() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let techFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/organize-me.xml",
                title: "Organize Me",
                kind: .rss,
                folder: newsFolder
            )
        )
        let controller = SourceManagementScreenController()
        let sidebarReloadIDBeforeMove = appState.sidebarReloadID

        harness.dependencies.appActions.showFeedOrganizer(id: feed.id, using: appState)
        controller.handleLaunchContext(.organizeFeed(feed.id), dependencies: harness.dependencies)

        guard case .moveSource(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-source destination presentation for feed organizer launch context")
            return
        }

        #expect(appState.sourceManagementLaunchContext == .organizeFeed(feed.id))
        #expect(initialDestination.feeds.first(where: { $0.id == feed.id })?.isSelected == true)
        #expect(initialDestination.placementOptions.first(where: { $0.title == "News" })?.isSelected == true)
        #expect(initialDestination.isPrimaryActionEnabled == false)

        controller.handleMoveSourcePlacementSelection(.folder(techFolder.id))
        controller.submitMoveSource(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let requests = await harness.httpClient.recordedRequests()

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeMove)
        #expect(persistedFeed.folder?.id == techFolder.id)
        #expect(requests.isEmpty)
    }
}
