import Foundation
import Testing
@testable import RSSReader

@Suite("Shell / App State")
@MainActor
struct ReadingShellAppStateTests {
    @Test
    func readingShellSidebarSelectionSwitchResetsArticleDetailSelectionAndTriggersReload() {
        let appState = AppState()
        let initialReloadID = appState.articleListReloadID
        let feedID = UUID()
        let articleID = UUID()

        appState.selectSidebarSelection(.feed(feedID))
        appState.selectedArticleID = articleID
        appState.presentSafari(articleID: articleID, url: URL(string: "https://example.com/article")!)

        let reloadIDBeforeSwitch = appState.articleListReloadID

        appState.selectSidebarSelection(.inbox)

        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
        #expect(reloadIDBeforeSwitch != initialReloadID)
        #expect(appState.articleListReloadID != reloadIDBeforeSwitch)
    }

    @Test
    func readingShellSelectingSameSidebarSelectionDoesNotResetSelectionOrTriggerReload() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectSidebarSelection(.feed(feedID))
        appState.selectedArticleID = articleID

        let reloadIDBeforeReselect = appState.articleListReloadID

        appState.selectSidebarSelection(.feed(feedID))

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
    func readingShellSidebarArticleFilterSwitchUpdatesActiveFilterWithoutBreakingNavigationContext() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectSidebarSelection(.feed(feedID))
        appState.selectedArticleID = articleID
        let reloadIDBeforeFilterSwitch = appState.articleListReloadID

        appState.selectSidebarArticleFilter(.starred)

        #expect(appState.selectedSidebarArticleFilter == .starred)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.presentedSafariRoute == nil)
        #expect(appState.articleListReloadID == reloadIDBeforeFilterSwitch)
    }

    @Test
    func readingShellReapplyingSameSidebarArticleFilterKeepsShellStateStable() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/sources-filter-article")!

        appState.selectSidebarArticleFilter(.unread)
        appState.selectedArticleID = articleID
        appState.presentSafari(articleID: articleID, url: webURL)

        let reloadIDBeforeReapplyingFilter = appState.articleListReloadID

        appState.selectSidebarArticleFilter(.unread)

        #expect(appState.selectedSidebarArticleFilter == .unread)
        #expect(appState.selectedArticleID == articleID)
        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(articleID: articleID, url: webURL),
                dismissalTarget: .article
            )
        )
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: articleID, url: webURL))
        #expect(appState.articleListReloadID == reloadIDBeforeReapplyingFilter)
    }

    @Test
    func readingShellAppStateKeepsArticleListScrollPositionPerSelectionAndFilter() {
        let appState = AppState()
        let feedID = UUID()
        let allItemsPositionID = UUID()
        let unreadPositionID = UUID()

        appState.updateArticleListScrollPosition(
            allItemsPositionID,
            sidebarSelection: .feed(feedID),
            sidebarArticleFilter: .allItems
        )
        appState.updateArticleListScrollPosition(
            unreadPositionID,
            sidebarSelection: .feed(feedID),
            sidebarArticleFilter: .unread
        )

        #expect(
            appState.articleListScrollPositionID(
                sidebarSelection: .feed(feedID),
                sidebarArticleFilter: .allItems
            ) == allItemsPositionID
        )
        #expect(
            appState.articleListScrollPositionID(
                sidebarSelection: .feed(feedID),
                sidebarArticleFilter: .unread
            ) == unreadPositionID
        )

        appState.updateArticleListScrollPosition(
            nil,
            sidebarSelection: .feed(feedID),
            sidebarArticleFilter: .allItems
        )

        #expect(
            appState.articleListScrollPositionID(
                sidebarSelection: .feed(feedID),
                sidebarArticleFilter: .allItems
            ) == nil
        )
        #expect(
            appState.articleListScrollPositionID(
                sidebarSelection: .feed(feedID),
                sidebarArticleFilter: .unread
            ) == unreadPositionID
        )
    }

    @Test
    func readingShellPublishesReadOnOpenEventWithinCurrentListContext() {
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        appState.selectSidebarSelection(.feed(feedID))
        appState.selectSidebarArticleFilter(.unread)
        appState.recordArticleReadOnOpenInCurrentListSession(articleID)

        #expect(appState.articleReadOnOpenEvent?.articleID == articleID)
        #expect(appState.articleReadOnOpenEvent?.sidebarSelection == .feed(feedID))
        #expect(appState.articleReadOnOpenEvent?.sidebarArticleFilter == .unread)
    }

    @Test
    func readingShellPublishesDistinctReadOnOpenEvents() {
        let appState = AppState()
        let firstArticleID = UUID()
        let secondArticleID = UUID()

        appState.recordArticleReadOnOpenInCurrentListSession(firstArticleID)
        let firstEvent = appState.articleReadOnOpenEvent

        appState.recordArticleReadOnOpenInCurrentListSession(secondArticleID)

        #expect(firstEvent?.articleID == firstArticleID)
        #expect(appState.articleReadOnOpenEvent?.articleID == secondArticleID)
        #expect(appState.articleReadOnOpenEvent?.id != firstEvent?.id)
    }

    @Test
    func readingShellOpenArticleSafariSetsPresentedRouteAndPreservesArticleContext() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/webview-article")!

        appState.selectedArticleID = articleID
        appState.presentSafari(articleID: articleID, url: webURL)

        #expect(appState.selectedArticleID == articleID)
        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(articleID: articleID, url: webURL),
                dismissalTarget: .article
            )
        )
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: articleID, url: webURL))
    }

    @Test
    func readingShellOpenArticleSafariFromArticleListDoesNotSelectReaderArticle() {
        let appState = AppState()
        let articleID = UUID()
        let webURL = URL(string: "https://example.com/direct-safari")!

        appState.presentSafariFromArticleList(articleID: articleID, url: webURL)

        #expect(appState.selectedArticleID == nil)
        #expect(
            appState.selectedDetailRoute == .safari(
                ArticleSafariRoute(articleID: articleID, url: webURL),
                dismissalTarget: .articleList
            )
        )
        #expect(appState.presentedSafariRoute == ArticleSafariRoute(articleID: articleID, url: webURL))

        appState.dismissPresentedSafari()

        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)
        #expect(appState.presentedSafariRoute == nil)
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
    func readingShellSidebarSelectionSwitchClearsArticleNavigationContext() {
        let appState = AppState()

        appState.updateArticleNavigationContext([UUID(), UUID()])
        appState.selectSidebarSelection(.unread)

        #expect(appState.articleNavigationContextIDs.isEmpty)
    }

    @Test
    func readingShellRejectsStaleAdjacentArticleNavigationContextFromPreviousSidebarSelection() {
        let appState = AppState()
        let previousFeedID = UUID()
        let currentFeedID = UUID()
        let firstArticleID = UUID()
        let secondArticleID = UUID()

        appState.selectSidebarSelection(.feed(currentFeedID))
        appState.selectedArticleID = firstArticleID

        appState.updateArticleNavigationContext(
            [firstArticleID, secondArticleID],
            sidebarSelection: .feed(previousFeedID),
            sidebarArticleFilter: .allItems
        )

        #expect(appState.adjacentArticleID(.next) == nil)
        #expect(appState.selectAdjacentArticle(.next) == false)

        appState.updateArticleNavigationContext(
            [firstArticleID, secondArticleID],
            sidebarSelection: .feed(currentFeedID),
            sidebarArticleFilter: .allItems
        )

        #expect(appState.adjacentArticleID(.next) == secondArticleID)
    }

    @Test
    func readingShellRejectsStaleAdjacentArticleNavigationContextFromPreviousSidebarArticleFilter() {
        let appState = AppState()
        let feedID = UUID()
        let firstArticleID = UUID()
        let secondArticleID = UUID()

        appState.selectSidebarSelection(.feed(feedID))
        appState.selectSidebarArticleFilter(.unread)
        appState.selectedArticleID = firstArticleID

        appState.updateArticleNavigationContext(
            [firstArticleID, secondArticleID],
            sidebarSelection: .feed(feedID),
            sidebarArticleFilter: .allItems
        )

        #expect(appState.adjacentArticleID(.next) == nil)
        #expect(appState.selectAdjacentArticle(.next) == false)

        appState.updateArticleNavigationContext(
            [firstArticleID, secondArticleID],
            sidebarSelection: .feed(feedID),
            sidebarArticleFilter: .unread
        )

        #expect(appState.adjacentArticleID(.next) == secondArticleID)
    }

    @Test
    func readingShellAppStateKeepsRemoteSyncAndBackgroundRefreshReloadTriggersSeparate() {
        let appState = AppState()
        let initialSidebarReloadID = appState.sidebarReloadID
        let initialArticleListReloadID = appState.articleListReloadID
        let initialArticleScreenReloadID = appState.articleScreenReloadID

        appState.requestRemoteSyncImportReload()

        #expect(appState.lastContentReloadTrigger == .remoteSyncImport)
        #expect(appState.sidebarReloadID != initialSidebarReloadID)
        #expect(appState.articleListReloadID != initialArticleListReloadID)
        #expect(appState.articleScreenReloadID != initialArticleScreenReloadID)

        let remoteSyncSidebarReloadID = appState.sidebarReloadID
        let remoteSyncArticleListReloadID = appState.articleListReloadID
        let remoteSyncArticleScreenReloadID = appState.articleScreenReloadID

        appState.requestBackgroundRefreshReload()

        #expect(appState.lastContentReloadTrigger == .backgroundRefresh)
        #expect(appState.sidebarReloadID != remoteSyncSidebarReloadID)
        #expect(appState.articleListReloadID != remoteSyncArticleListReloadID)
        #expect(appState.articleScreenReloadID != remoteSyncArticleScreenReloadID)
    }
}
