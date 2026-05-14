import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Screen Controller")
@MainActor
struct SourceManagementScreenControllerTests {
    @Test
    func sourceManagementScreenControllerLoadsFeedPreviewThroughSourceManagementService() async throws {
        let feedURL = "https://example.com/preview-controller.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Controller Preview Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Preview Article",
                            itemLink: "https://example.com/articles/preview",
                            itemGUID: "controller-preview-article",
                            itemDescription: "Preview description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(" \(feedURL) ")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after preview loading")
            return
        }

        #expect(destination.preview?.title == "Controller Preview Feed")
        #expect(destination.preview?.siteURL == "https://example.com/")
        #expect(destination.preview?.kindTitle == "RSS")
        #expect(destination.primaryActionTitle == "Add Feed")
        #expect(destination.isPrimaryActionEnabled)
        #expect(destination.isConfirmationActionEnabled)

        let recordedRequests = await harness.httpClient.recordedRequests()
        #expect(recordedRequests.map(\.url.absoluteString) == [feedURL])
    }

    @Test
    func sourceManagementScreenControllerCreatesFeedThroughServiceAfterConfirmedPreview() async throws {
        let feedURL = "https://example.com/create-from-preview.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Created Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Created Article",
                            itemLink: "https://example.com/articles/created",
                            itemGUID: "created-article",
                            itemDescription: "Created description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let folder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(" \(feedURL) ")
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)
        controller.handleAddFeedFolderPlacementSelection(.folder(folder.id))
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let createdDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after feed creation")
            return
        }

        let persistedFeed = try harness.feedRepository.fetchFeed(url: feedURL)

        #expect(createdDestination.primaryActionTitle == "Feed Added")
        #expect(createdDestination.isPrimaryActionEnabled == false)
        #expect(createdDestination.status?.title == "Feed added")
        #expect(createdDestination.status?.detail == "Created Feed was saved in Tech.")
        #expect(persistedFeed?.url == feedURL)
        #expect(persistedFeed?.title == "Created Feed")
        #expect(persistedFeed?.siteURL == "https://example.com/")
        #expect(persistedFeed?.kind == .rss)
        #expect(persistedFeed?.folder?.id == folder.id)
    }

    @Test
    func sourceManagementScreenControllerCreatesFeedRefreshesItAndDismissesSourceManagementFlow() async throws {
        let feedURL = "https://example.com/create-and-refresh.xml"
        let responseStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Created And Refreshed Feed",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "First Refreshed Article",
                itemLink: "https://example.com/articles/first-refreshed",
                itemGUID: "first-refreshed-article",
                itemDescription: "Refreshed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                steps: [responseStep, responseStep]
            )
        )
        let appState = AppState()
        let controller = SourceManagementScreenController()
        let articleReloadIDBeforeCreation = appState.articleListReloadID
        let sidebarReloadIDBeforeCreation = appState.sourcesSidebarReloadID

        harness.dependencies.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.addFeed, dependencies: harness.dependencies)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(url: feedURL))
        let articles = try harness.articleRepository.fetchArticles(feedID: persistedFeed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(persistedFeed.id))
        #expect(appState.articleListReloadID != articleReloadIDBeforeCreation)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCreation)
        #expect(persistedFeed.lastFetchedAt != nil)
        #expect(persistedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "First Refreshed Article")
        #expect(requests.map(\.url.absoluteString) == [feedURL, feedURL])
    }

    @Test
    func sourceManagementScreenControllerEditsFeedFromSidebarLaunchContextAndRefreshesUpdatedSource() async throws {
        let initialURL = "https://example.com/original-feed.xml"
        let updatedURL = "https://example.com/updated-feed.xml"
        let previewStep = ScriptedHTTPClient.Step.response(
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: makeValidRSSFeedXML(
                channelTitle: "Updated Feed Title",
                channelLink: "https://example.com/",
                language: "en",
                itemTitle: "Updated Feed Article",
                itemLink: "https://example.com/articles/updated-feed",
                itemGUID: "updated-feed-article",
                itemDescription: "Updated feed description",
                pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: [previewStep, previewStep])
        )
        let originalFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: initialURL,
                title: "Original Feed",
                kind: .rss,
                folder: originalFolder
            )
        )
        let appState = AppState()
        let controller = SourceManagementScreenController()

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.showFeedEditor(id: feed.id, using: appState)
        controller.handleLaunchContext(.editFeed(feed.id), dependencies: harness.dependencies)

        guard case .addFeed(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation for feed editor launch context")
            return
        }

        #expect(initialDestination.title == "Edit Feed")
        #expect(initialDestination.urlInput == initialURL)
        #expect(initialDestination.placementOptions.isEmpty)
        #expect(initialDestination.createFolderActionTitle == nil)

        controller.handleAddFeedURLChange(updatedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let requests = await harness.httpClient.recordedRequests()

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(persistedFeed.url == updatedURL)
        #expect(persistedFeed.title == "Updated Feed Title")
        #expect(persistedFeed.folder?.id == originalFolder.id)
        #expect(persistedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Updated Feed Article")
        #expect(requests.map(\.url.absoluteString) == [updatedURL, updatedURL])
    }

    @Test
    func sourceManagementScreenControllerEditsFolderFromSidebarLaunchContextAndRetargetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let controller = SourceManagementScreenController()
        let sidebarReloadIDBeforeEdit = appState.sourcesSidebarReloadID

        harness.dependencies.showFolder(named: "News", using: appState)
        harness.dependencies.showFolderEditor(named: "News", using: appState)
        controller.handleLaunchContext(.editFolder(folder.id), dependencies: harness.dependencies)

        guard case .createFolder(let initialDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected create-folder destination presentation for folder editor launch context")
            return
        }

        #expect(initialDestination.title == "Edit Folder")
        #expect(initialDestination.nameInput == "News")

        controller.handleCreateFolderNameChange("World News")
        controller.submitCreateFolder(dependencies: harness.dependencies, appState: appState)

        let renamedFolder = try #require(try harness.folderRepository.fetchFolder(id: folder.id))

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeEdit)
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
        let sidebarReloadIDBeforeMove = appState.sourcesSidebarReloadID

        harness.dependencies.showFeedOrganizer(id: feed.id, using: appState)
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
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeMove)
        #expect(persistedFeed.folder?.id == techFolder.id)
        #expect(requests.isEmpty)
    }

    @Test
    func sourceManagementScreenControllerShowsDuplicateFeedWarningWhenPreviewMatchesExistingSource() async throws {
        let feedURL = "https://example.com/existing-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Existing Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Existing Article",
                            itemLink: "https://example.com/articles/existing",
                            itemGUID: "existing-article",
                            itemDescription: "Existing description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        _ = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Existing Feed",
                kind: .rss
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after duplicate preview loading")
            return
        }

        #expect(destination.preview?.title == "Existing Feed")
        #expect(destination.preview?.existingFeedNotice == "This source already exists in the library.")
        #expect(destination.status?.kind == .warning)
        #expect(destination.status?.title == "This feed is already in the library")
        #expect(destination.primaryActionTitle == "Already Added")
        #expect(destination.isPrimaryActionEnabled == false)
    }

    @Test
    func sourceManagementScreenControllerShowsNetworkFailureStatusWhenPreviewRequestFails() async throws {
        let feedURL = "https://example.com/network-failure.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .urlError(.notConnectedToInternet)
                ]
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after network failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == "Network error while loading preview")
        #expect(destination.status?.detail == "Check the internet connection and try again.")
        #expect(destination.primaryActionTitle == "Preview Feed")
        #expect(destination.isPrimaryActionEnabled == false)
    }

    @Test
    func sourceManagementScreenControllerShowsUnsupportedFeedStatusWhenPreviewResponseIsNotAFeed() async throws {
        let feedURL = "https://example.com/not-a-feed"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "text/html; charset=utf-8"],
                        body: "<html><body>Not a feed</body></html>"
                    )
                ]
            )
        )
        let controller = SourceManagementScreenController()

        controller.handleScenarioSelection(.addFeed)
        controller.handleAddFeedURLChange(feedURL)
        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let destination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after unsupported-feed failure")
            return
        }

        #expect(destination.preview == nil)
        #expect(destination.status?.kind == .failure)
        #expect(destination.status?.title == "Source is not a supported feed")
        #expect(destination.status?.detail == "The address responded with text/html; charset=utf-8, not a supported RSS or Atom feed.")
        #expect(destination.primaryActionTitle == "Preview Feed")
        #expect(destination.isPrimaryActionEnabled == false)
    }

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

        harness.dependencies.showFolder(named: "News", using: appState)
        let articleReloadIDBeforeMove = appState.articleListReloadID
        let sidebarReloadIDBeforeMove = appState.sourcesSidebarReloadID

        harness.dependencies.showSourceManagement(using: appState)
        controller.handleScenarioSelection(.moveSource, dependencies: harness.dependencies)
        controller.handleMoveSourcePlacementSelection(.folder(techFolder.id))
        controller.submitMoveSource(dependencies: harness.dependencies, appState: appState)

        let persistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeMove)
        #expect(appState.articleListReloadID != articleReloadIDBeforeMove)
        #expect(persistedFeed?.folder?.id == techFolder.id)
    }

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
        #expect(addFeedDestination.primaryActionTitle == "Preview Feed")
        #expect(addFeedDestination.placementOptions.isEmpty)

        await controller.handleAddFeedPrimaryAction(dependencies: harness.dependencies)

        guard case .addFeed(let previewDestination)? = controller.viewState().presentedDestination else {
            Issue.record("Expected add-feed destination presentation after loading preview")
            return
        }

        #expect(previewDestination.placementOptions.map(\.title) == ["Ungrouped", "News", "Research"])
        #expect(previewDestination.placementOptions.last?.isSelected == true)
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
        #expect(createdDestination.placementDescription == "This folder will be added after 2 existing folders.")
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

        harness.dependencies.showSourceManagement(using: appState)
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
        #expect(createdDestination.feedback?.title == "Folder created")
        #expect(createdDestination.feedback?.detail == "\"Research\" is ready for sources.")
        #expect(try harness.folderRepository.fetchFolder(name: "Research") != nil)
    }
}
