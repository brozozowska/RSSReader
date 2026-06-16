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

        harness.dependencies.appActions.showInbox(using: appState)
        harness.dependencies.appActions.showFeedManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.appActions.finishCreatingFolder(named: "Research", using: appState)

        #expect(appState.isPresentingFeedManagementScreen)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersMoveFeedReloadsSelectedFeedAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-move.xml",
                title: "Helper Move",
                kind: .rss
            )
        )

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        harness.dependencies.appActions.showFeedManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.appActions.finishMovingSource(
            feedID: feed.id,
            previousFolderName: "News",
            updatedFolderName: "Tech",
            using: appState
        )

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersEditFolderRetargetsSelectionAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()

        harness.dependencies.appActions.showFolder(named: "News", using: appState)
        harness.dependencies.appActions.showFeedManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.appActions.finishFolderEditing(
            previousName: "News",
            updatedFolderName: "World News",
            using: appState
        )

        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersSaveFeedDismissesThenRefreshesSelection() async throws {
        let feedURL = "https://example.com/helper-save.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .delayedResponse(
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
                        ),
                        delayNanoseconds: 200_000_000
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

        harness.dependencies.appActions.showInbox(using: appState)
        harness.dependencies.appActions.showFeedManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        let result = await harness.dependencies.appActions.finishSavingFeed(id: feed.id, using: appState)
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result == nil)
        #expect(appState.isPresentingFeedManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
        #expect(articles.isEmpty)

        await harness.dependencies.appActions.waitForScheduledFeedSaveRefreshes()

        let refreshedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(refreshedArticles.count == 1)
        #expect(refreshedArticles.first?.title == "Helper Saved Article")
    }

    @Test
    func shellActionCompletionHelpersUnsubscribeFeedKeepsCurrentSelectionWhenAnotherFeedIsRemoved() throws {
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

        harness.dependencies.appActions.showFeed(id: selectedFeed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.appActions.finishUnsubscribingFeed(id: removedFeedID, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(selectedFeed.id))
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeCompletion)
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

        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.appActions.finishDeletingFolder(named: "Archived", using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }
}
