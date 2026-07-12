import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Screen Controller / Launch Contexts")
@MainActor
struct FeedManagementScreenControllerLaunchContextTests {
    @Test
    func feedManagementScreenControllerEditsFolderFromSidebarLaunchContextAndRetargetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let controller = FeedManagementScreenController()
        let sidebarReloadIDBeforeEdit = appState.sidebarReloadID

        harness.dependencies.appActions.showFolder(named: "News", using: appState)
        harness.dependencies.appActions.showFolderEditor(named: "News", using: appState)
        controller.handleLaunchContext(.editFolder(folder.id), dependencies: harness.dependencies)

        guard case .createFolder(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation for folder editor launch context")
            return
        }

        #expect(SidebarLocalization.renameFolderActionTitle == "Переименовать...")
        #expect(initialDestination.title == FeedManagementLocalization.renameFolderTitle)
        #expect(initialDestination.title == "Переименовать папку")
        #expect(initialDestination.nameInput == "News")
        #expect(initialDestination.summaryTitle == FeedManagementLocalization.folderNameSummaryTitle)
        #expect(initialDestination.summaryDescription == FeedManagementLocalization.editFolderDescription)
        #expect(initialDestination.existingFolders.contains(where: { $0.id == folder.id && $0.name == "News" }))

        controller.handleCreateFolderNameChange("World News")
        controller.submitCreateFolder(dependencies: harness.dependencies, appState: appState)

        let renamedFolder = try #require(try harness.folderRepository.fetchFolder(id: folder.id))

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeEdit)
        #expect(renamedFolder.name == "World News")
        #expect(renamedFolder.sortOrder == 0)
    }

    @Test
    func feedManagementScreenControllerOrganizesFeedFromSidebarLaunchContextWithoutPreview() async throws {
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
        let controller = FeedManagementScreenController()
        let sidebarReloadIDBeforeMove = appState.sidebarReloadID

        harness.dependencies.appActions.showFeedOrganizer(id: feed.id, using: appState)
        controller.handleLaunchContext(.organizeFeed(feed.id), dependencies: harness.dependencies)

        guard case .moveFeed(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected move-feed destination presentation for feed organizer launch context")
            return
        }

        #expect(appState.feedManagementLaunchContext == .organizeFeed(feed.id))
        #expect(initialDestination.feeds.first(where: { $0.id == feed.id })?.isSelected == true)
        #expect(initialDestination.placementOptions.first(where: { $0.title == "News" })?.isSelected == true)
        #expect(initialDestination.isPrimaryActionEnabled == false)

        controller.handleMoveFeedPlacementSelection(.folder(techFolder.id))
        controller.submitMoveFeed(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let requests = await harness.httpClient.recordedRequests()

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeMove)
        #expect(persistedFeed.folder?.id == techFolder.id)
        #expect(requests.isEmpty)
    }
}
