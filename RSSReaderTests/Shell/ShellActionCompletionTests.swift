import Foundation
import Testing
@testable import RSSReader

@Suite("Shell / Completion Helpers")
@MainActor
struct ShellActionCompletionTests {
    @Test
    func shellActionCompletionHelpersCreateFolderReloadsSidebarAndKeepsModalFlowOpen() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()

        harness.dependencies.showInbox(using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishCreatingFolder(named: "Research", using: appState)

        #expect(appState.isPresentingSourceManagementScreen)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersMoveSourceReloadsSelectedFeedAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-move.xml",
                title: "Helper Move",
                kind: .rss
            )
        )

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishMovingSource(
            feedID: feed.id,
            previousFolderName: "News",
            updatedFolderName: "Tech",
            using: appState
        )

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersEditFolderRetargetsSelectionAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()

        harness.dependencies.showFolder(named: "News", using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishFolderEditing(
            previousName: "News",
            updatedFolderName: "World News",
            using: appState
        )

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersSaveFeedRefreshesSelectionAndDismissesModalFlow() async throws {
        let feedURL = "https://example.com/helper-save.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Helper Saved Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Helper Saved Article",
                            itemLink: "https://example.com/articles/helper-saved",
                            itemGUID: "helper-saved-article",
                            itemDescription: "Helper saved description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Helper Feed",
                kind: .rss
            )
        )

        harness.dependencies.showInbox(using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        let result = await harness.dependencies.finishSavingFeed(id: feed.id, using: appState)
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result?.status == .fetched)
        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Helper Saved Article")
    }

    @Test
    func shellActionCompletionHelpersUnsubscribeFeedKeepsCurrentSelectionWhenAnotherSourceIsRemoved() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let selectedFeed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-selected.xml",
                title: "Selected Feed",
                kind: .rss
            )
        )
        let removedFeedID = UUID()

        harness.dependencies.showFeed(id: selectedFeed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishUnsubscribingFeed(id: removedFeedID, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(selectedFeed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersDeleteFolderKeepsCurrentSelectionWhenAnotherFolderIsRemoved() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-delete-folder.xml",
                title: "Current Feed",
                kind: .rss
            )
        )

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishDeletingFolder(named: "Archived", using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }
}
