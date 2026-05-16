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
        appState.presentSafari(articleID: articleID, url: URL(string: "https://example.com/article")!)

        let reloadIDBeforeSwitch = appState.articleListReloadID

        appState.selectReadingSource(.inbox)

        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
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
    func readingShellSelectingDifferentArticleTriggersArticleScreenReload() {
        let appState = AppState()
        let firstArticleID = UUID()
        let secondArticleID = UUID()

        appState.selectedArticleID = firstArticleID
        let reloadIDBeforeSelectingSecondArticle = appState.articleScreenReloadID

        appState.selectedArticleID = secondArticleID

        #expect(appState.selectedArticleID == secondArticleID)
        #expect(appState.selectedDetailRoute == .article(secondArticleID))
        #expect(appState.articleScreenReloadID != reloadIDBeforeSelectingSecondArticle)
    }

    @Test
    func readingShellSelectingSameArticleDoesNotTriggerArticleScreenReload() {
        let appState = AppState()
        let articleID = UUID()

        appState.selectedArticleID = articleID
        let reloadIDBeforeReselectingArticle = appState.articleScreenReloadID

        appState.selectedArticleID = articleID

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.articleScreenReloadID == reloadIDBeforeReselectingArticle)
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
        #expect(appState.presentedSafariRoute == nil)
        #expect(appState.articleListReloadID == reloadIDBeforeFilterSwitch)
    }

    @Test
    func readingShellReapplyingSameSourcesFilterKeepsShellStateStable() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/sources-filter-article")!

        appState.selectSourcesFilter(.unread)
        appState.selectedArticleID = articleID
        appState.presentSafari(articleID: articleID, url: webURL)

        let reloadIDBeforeReapplyingFilter = appState.articleListReloadID

        appState.selectSourcesFilter(.unread)

        #expect(appState.selectedSourcesFilter == .unread)
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .safari(ArticleSafariRoute(articleID: articleID, url: webURL)))
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: articleID, url: webURL))
        #expect(appState.articleListReloadID == reloadIDBeforeReapplyingFilter)
    }

    @Test
    func readingShellOpenArticleSafariSetsPresentedRouteAndPreservesArticleContext() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/webview-article")!

        appState.selectedArticleID = articleID
        appState.presentSafari(articleID: articleID, url: webURL)

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .safari(ArticleSafariRoute(articleID: articleID, url: webURL)))
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: articleID, url: webURL))
    }

    @Test
    func readingShellRejectsUnsupportedArticleSafariRoutes() {
        let appState = AppState()
        let articleID = UUID()
        let unsupportedURL = URL(string: "mailto:hello@example.com")!

        let didPresentSafari = appState.presentSafari(articleID: articleID, url: unsupportedURL)

        #expect(didPresentSafari == false)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func readingShellClosingArticleSafariRestoresArticleDetailRoute() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/webview-close")!

        appState.selectedArticleID = articleID
        appState.presentSafari(articleID: articleID, url: webURL)

        appState.dismissPresentedSafari()

        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedSafariRoute == nil)
    }

    @Test
    func readingShellSelectsAdjacentArticlesFromCurrentListContext() {
        let appState = AppState()
        let firstArticleID = UUID()
        let secondArticleID = UUID()
        let thirdArticleID = UUID()

        appState.updateArticleNavigationContext([
            firstArticleID,
            secondArticleID,
            thirdArticleID
        ])
        appState.selectedArticleID = secondArticleID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        #expect(appState.adjacentArticleID(.next) == thirdArticleID)
        #expect(appState.adjacentArticleID(.previous) == firstArticleID)

        #expect(appState.selectAdjacentArticle(.next))
        #expect(appState.selectedArticleID == thirdArticleID)
        #expect(appState.selectedDetailRoute == .article(thirdArticleID))
        #expect(appState.articleScreenReloadID != initialArticleScreenReloadID)

        #expect(appState.adjacentArticleID(.next) == nil)
        #expect(appState.adjacentArticleID(.previous) == secondArticleID)
        #expect(appState.selectAdjacentArticle(.next) == false)
        #expect(appState.selectedArticleID == thirdArticleID)

        #expect(appState.selectAdjacentArticle(.previous))
        #expect(appState.selectedArticleID == secondArticleID)
        #expect(appState.selectedDetailRoute == .article(secondArticleID))
    }

    @Test
    func readingShellDeduplicatesAdjacentArticleNavigationContext() {
        let appState = AppState()
        let firstArticleID = UUID()
        let secondArticleID = UUID()
        let thirdArticleID = UUID()

        appState.updateArticleNavigationContext([
            firstArticleID,
            secondArticleID,
            secondArticleID,
            thirdArticleID,
            firstArticleID
        ])
        appState.selectedArticleID = secondArticleID

        #expect(appState.articleNavigationContextIDs == [
            firstArticleID,
            secondArticleID,
            thirdArticleID
        ])
        #expect(appState.selectAdjacentArticle(.next))
        #expect(appState.selectedArticleID == thirdArticleID)
        #expect(appState.selectedDetailRoute == .article(thirdArticleID))
    }

    @Test
    func readingShellSkipsDuplicateCurrentArticleIDsWhenSelectingAdjacentArticle() {
        let appState = AppState()
        let articleID = UUID()
        let nextArticleID = UUID()

        appState.articleNavigationContextIDs = [
            articleID,
            articleID,
            nextArticleID
        ]
        appState.selectedArticleID = articleID

        #expect(appState.selectAdjacentArticle(.next))
        #expect(appState.selectedArticleID == nextArticleID)
        #expect(appState.selectedDetailRoute == .article(nextArticleID))
    }

    @Test
    func readingShellSourceSwitchClearsArticleNavigationContext() {
        let appState = AppState()

        appState.updateArticleNavigationContext([UUID(), UUID()])
        appState.selectReadingSource(.unread)

        #expect(appState.articleNavigationContextIDs.isEmpty)
    }

    @Test
    func readingShellAppStateKeepsRemoteSyncAndBackgroundRefreshReloadTriggersSeparate() {
        let appState = AppState()
        let initialSidebarReloadID = appState.sourcesSidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        appState.requestRemoteSyncImportReload()

        #expect(appState.lastContentReloadTrigger == .remoteSyncImport)
        #expect(appState.sourcesSidebarReloadID != initialSidebarReloadID)
        #expect(appState.articleListReloadID != initialArticleListReloadID)
        #expect(appState.articleScreenReloadID != initialArticleScreenReloadID)

        let remoteSyncSidebarReloadID = appState.sourcesSidebarReloadID
        let remoteSyncArticleListReloadID = appState.articleListReloadID
        let remoteSyncArticleScreenReloadID = appState.articleScreenReloadID

        appState.requestBackgroundRefreshReload()

        #expect(appState.lastContentReloadTrigger == .backgroundRefresh)
        #expect(appState.sourcesSidebarReloadID != remoteSyncSidebarReloadID)
        #expect(appState.articleListReloadID != remoteSyncArticleListReloadID)
        #expect(appState.articleScreenReloadID != remoteSyncArticleScreenReloadID)
    }
}
