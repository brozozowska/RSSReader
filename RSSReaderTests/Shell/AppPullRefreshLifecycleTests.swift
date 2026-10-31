import Foundation
import Testing
@testable import RSSReader

@Suite("Shell / Pull Refresh Lifecycle")
@MainActor
struct AppPullRefreshLifecycleTests {
    @Test(arguments: [-0.1, 0, 0.4, 1, 1.2])
    func pullProgressMapsToIndicatorContract(progress: Double) {
        var lifecycle = AppPullRefreshLifecycle()
        lifecycle.updatePullProgress(progress)
        let state = lifecycle.state
        let clamped = min(max(progress, 0), 1)

        #expect(state.pullProgress == clamped)
        #expect(state.showsIndicator == (clamped > 0))
        if clamped == 0 {
            #expect(state.phase == .idle)
            #expect(state.indicatorState == .idle)
        } else if clamped == 1 {
            #expect(state.phase == .ready)
            #expect(state.indicatorState == .ready)
        } else {
            #expect(state.phase == .pulling)
            #expect(state.indicatorState == .pulling(progress: clamped))
        }
    }

    @Test
    func completionOnlyEndsItsOwnOperation() {
        var lifecycle = AppPullRefreshLifecycle()
        let oldID = lifecycle.begin()
        #expect(lifecycle.state.showsIndicator)
        #expect(lifecycle.state.pullProgress == 1)
        #expect(lifecycle.state.indicatorState == .refreshing)
        lifecycle.updatePullProgress(0)
        #expect(lifecycle.state == .refreshing)
        let currentID = lifecycle.begin()
        #expect(oldID != currentID)
        lifecycle.end(ifMatching: oldID)
        #expect(lifecycle.state == .refreshing)
        lifecycle.end(ifMatching: currentID)
        #expect(lifecycle.state == .idle)
    }

    @Test
    func resetInvalidatesCompletionDuringANewPull() {
        var lifecycle = AppPullRefreshLifecycle()
        let oldID = lifecycle.begin()
        lifecycle.end()
        lifecycle.updatePullProgress(0.5)
        lifecycle.end(ifMatching: oldID)
        #expect(lifecycle.state == .pulling(progress: 0.5))
        lifecycle.updatePullProgress(1)
        lifecycle.end(ifMatching: oldID)
        #expect(lifecycle.state.phase == .ready)
        lifecycle.updatePullProgress(0)
        #expect(lifecycle.state == .idle)
    }

    @Test
    func screenOperationsHaveIndependentIdentitiesAndBusinessState() {
        var sidebar = SidebarScreenState()
        var articles = ArticlesScreenState()
        sidebar.beginRefreshing()
        let subtitleID = articles.beginFeedRefresh()
        let sidebarID = sidebar.beginCustomRefresh()
        articles.updateCustomRefreshPullProgress(0.5)
        #expect(sidebar.customRefreshState == .refreshing)
        #expect(articles.customRefreshState == .pulling(progress: 0.5))
        let articlesID = articles.beginCustomRefresh()
        #expect(sidebarID != articlesID)
        sidebar.endCustomRefresh(ifMatching: articlesID)
        articles.endCustomRefresh(ifMatching: sidebarID)
        #expect(sidebar.customRefreshState == .refreshing)
        #expect(articles.customRefreshState == .refreshing)

        articles.endPresentation()
        sidebar.endCustomRefresh(ifMatching: sidebarID)
        articles.updateCustomRefreshPullProgress(1)
        articles.endCustomRefresh(ifMatching: articlesID)
        #expect(articles.customRefreshState.phase == .ready)
        #expect(sidebar.customRefreshState == .idle)
        #expect(sidebar.refreshStatus == .syncing)
        // The subtitle operation remains separate from the pull lifecycle.
        articles.endFeedRefresh(ifMatching: subtitleID)
    }

    @Test
    func gestureReleaseCommitsOnceAndCancellationClearsPresentation() {
        var gesture = AppRefreshPullGestureState()
        var lifecycle = AppPullRefreshLifecycle()
        var commits = 0
        for event: AppRefreshPullGestureState.Event in [.began, .changed, .ended, .ended] {
            let result = gesture.handle(event, contentOffsetY: -172, contentInsetTop: 100, isEnabled: true)
            lifecycle.updatePullProgress(result.progress)
            if result.shouldRefresh && lifecycle.state.phase == .ready {
                commits += 1
                lifecycle.begin()
            }
        }
        #expect(commits == 1)
        #expect(lifecycle.state == .refreshing)
        lifecycle.end()
        let pull = gesture.handle(.began, contentOffsetY: -172, contentInsetTop: 100, isEnabled: true)
        lifecycle.updatePullProgress(pull.progress)
        let cancelled = gesture.handle(.cancelled, contentOffsetY: -172, contentInsetTop: 100, isEnabled: true)
        lifecycle.updatePullProgress(cancelled.progress)
        #expect(cancelled.shouldRefresh == false)
        #expect(lifecycle.state == .idle)
    }
}
