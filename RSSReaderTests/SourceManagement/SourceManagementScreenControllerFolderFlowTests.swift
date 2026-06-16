import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen Controller / Folder Flow")
@MainActor
struct SourceManagementScreenControllerFolderFlowTests {
    @Test
    func sourceManagementScreenControllerReturnsToAddFeedWithNewFolderSelectedAfterInlineFolderCreation() async throws {
        let feedURL = "https://example.com/feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Example Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Example Article",
                            itemLink: "https://example.com/articles/example",
                            itemGUID: "example-article",
                            itemDescription: "Example description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        _ = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let previewBeforeFolderDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after loading preview")
            return
        }

        #expect(previewBeforeFolderDestination.urlInput == feedURL)
        #expect(previewBeforeFolderDestination.primaryActionTitle == SourceManagementLocalization.addFeedTitle)
        #expect(previewBeforeFolderDestination.isConfirmationActionEnabled)
        #expect(previewBeforeFolderDestination.preview?.title == "Example Feed")

        controller.startCreateFolderFromAddFeed(dependencies: harness.dependencies)

        guard case .createFolder(let createFolderDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination when starting from add-feed flow")
            return
        }

        #expect(createFolderDestination.existingFolders.map(\.name) == ["News"])

        controller.handleCreateFolderNameChange("Research")
        controller.submitCreateFolder(dependencies: harness.dependencies)

        guard case .addFeed(let addFeedDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination after inline folder creation")
            return
        }

        #expect(addFeedDestination.urlInput == feedURL)
        #expect(addFeedDestination.primaryActionTitle == SourceManagementLocalization.addFeedTitle)
        #expect(addFeedDestination.isConfirmationActionEnabled)
        #expect(addFeedDestination.preview?.title == "Example Feed")
        #expect(addFeedDestination.placementOptions.map(\.title) == [SourceManagementLocalization.ungroupedTitle, "News", "Research"])
        #expect(addFeedDestination.placementOptions.last?.isSelected == true)
    }

    @Test
    func sourceManagementScreenControllerRestoresPreviewedAddFeedAfterBackingOutOfNestedFolderCreation() async throws {
        let feedURL = "https://example.com/feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Example Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Example Article",
                            itemLink: "https://example.com/articles/example",
                            itemGUID: "example-article",
                            itemDescription: "Example description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)
        controller.handleAddFeedFolderPlacementSelection(.folder(newsFolder.id))
        controller.startCreateFolderFromAddFeed(dependencies: harness.dependencies)
        controller.dismissPresentedScenario()

        guard case .addFeed(let addFeedDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination after backing out of nested folder creation")
            return
        }

        #expect(addFeedDestination.urlInput == feedURL)
        #expect(addFeedDestination.primaryActionTitle == SourceManagementLocalization.addFeedTitle)
        #expect(addFeedDestination.isConfirmationActionEnabled)
        #expect(addFeedDestination.preview?.title == "Example Feed")
        #expect(addFeedDestination.placementOptions.first(where: { $0.title == "News" })?.isSelected == true)
    }

    @Test
    func sourceManagementScreenControllerCreatesFolderThroughServiceAndRefreshesDestination() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SourceManagementScreenController()

        _ = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))

        controller.handleScenarioSelection(.createFolder, dependencies: harness.dependencies)

        guard case .createFolder(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation")
            return
        }

        #expect(initialDestination.existingFolders.map(\.name) == ["News"])
        #expect(initialDestination.isPrimaryActionEnabled == false)

        controller.handleCreateFolderNameChange("Research")

        guard case .createFolder(let draftDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after input")
            return
        }

        #expect(draftDestination.validationMessage == nil)
        #expect(draftDestination.isPrimaryActionEnabled)

        controller.submitCreateFolder(dependencies: harness.dependencies)

        guard case .createFolder(let createdDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after submission")
            return
        }

        #expect(createdDestination.nameInput.isEmpty)
        #expect(createdDestination.existingFolders.map(\.name) == ["News", "Research"])
        #expect(createdDestination.placementDescription == SourceManagementLocalization.existingFolderPlacementDescription(count: 2))
        #expect(createdDestination.feedback?.kind == .success)

        let folders = try harness.folderRepository.fetchAllFolders()
        #expect(folders.map(\.name) == ["News", "Research"])
        #expect(folders.map(\.sortOrder) == [0, 1])
    }

    @Test
    func sourceManagementScreenControllerCreatesFolderRequestsSidebarReloadInAppFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let controller = SourceManagementScreenController()
        let appState = AppState()
        let sidebarReloadIDBeforeCreation = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCreation = appState.articleListReloadID

        harness.dependencies.appActions.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.createFolder, dependencies: harness.dependencies)
        controller.handleCreateFolderNameChange("Research")
        controller.submitCreateFolder(
            dependencies: harness.dependencies,
            appState: appState
        )

        guard case .createFolder(let createdDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation after app-level creation")
            return
        }

        #expect(appState.isPresentingSourceManagementScreen)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCreation)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCreation)
        #expect(createdDestination.feedback?.title == SourceManagementLocalization.folderCreatedTitle)
        #expect(createdDestination.feedback?.detail == SourceManagementLocalization.folderCreatedDetail("Research"))
        #expect(try harness.folderRepository.fetchFolder(name: "Research") != nil)
    }
}
