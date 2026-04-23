import Foundation
import Testing
@testable import RSSReader

@Suite("Shell / App State")
@MainActor
struct ReadingShellAppStateTests {
    @Test
    func readingShellSourceSwitchResetsArticleDetailSelectionAndTriggersReload() {
        let appState = AppState()
        let initialReloadID = appState.articleListReloadID
        let feedID = UUID()
        let articleID = UUID()

        appState.selectReadingSource(.feed(feedID))
        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: URL(string: "https://example.com/article")!)

        let reloadIDBeforeSwitch = appState.articleListReloadID

        appState.selectReadingSource(.inbox)

        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedWebViewRoute == nil)
        #expect(reloadIDBeforeSwitch != initialReloadID)
        #expect(appState.articleListReloadID != reloadIDBeforeSwitch)
    }

    @Test
    func readingShellSelectingSameSourceDoesNotResetSelectionOrTriggerReload() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectReadingSource(.feed(feedID))
        appState.selectedArticleID = articleID

        let reloadIDBeforeReselect = appState.articleListReloadID

        appState.selectReadingSource(.feed(feedID))

        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.articleListReloadID == reloadIDBeforeReselect)
    }

    @Test
    func readingShellSourcesFilterSwitchUpdatesActiveFilterWithoutBreakingNavigationContext() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectReadingSource(.feed(feedID))
        appState.selectedArticleID = articleID
        let reloadIDBeforeFilterSwitch = appState.articleListReloadID

        appState.selectSourcesFilter(.starred)

        #expect(appState.selectedSourcesFilter == .starred)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedWebViewRoute == nil)
        #expect(appState.articleListReloadID == reloadIDBeforeFilterSwitch)
    }

    @Test
    func readingShellReapplyingSameSourcesFilterKeepsShellStateStable() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/sources-filter-article")!

        appState.selectSourcesFilter(.unread)
        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: webURL)

        let reloadIDBeforeReapplyingFilter = appState.articleListReloadID

        appState.selectSourcesFilter(.unread)

        #expect(appState.selectedSourcesFilter == .unread)
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: articleID, url: webURL)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: articleID, url: webURL))
        #expect(appState.articleListReloadID == reloadIDBeforeReapplyingFilter)
    }

    @Test
    func readingShellOpenArticleWebViewSetsPresentedRouteAndPreservesArticleContext() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/webview-article")!

        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: webURL)

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: articleID, url: webURL)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: articleID, url: webURL))
    }

    @Test
    func readingShellClosingArticleWebViewRestoresArticleDetailRoute() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/webview-close")!

        appState.selectedArticleID = articleID
        appState.presentWebView(articleID: articleID, url: webURL)

        appState.dismissPresentedWebView()

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedWebViewRoute == nil)
    }
}
