import Foundation
import Testing
@testable import RSSReader

@Suite("WebView Screen / State")
@MainActor
struct WebViewScreenStateTests {
    @Test
    func webViewScreenStateBuildsInitialDerivedStateFromRoute() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/webview-state")!
        )
        let state = WebViewScreenState(route: route)
        let viewState = state.derivedViewState()

        #expect(viewState.initialURL == route.url)
        #expect(viewState.navigationTitle == "example.com")
        #expect(viewState.primaryLoadingState?.title == "Loading Page")
        #expect(viewState.placeholder == nil)
        #expect(viewState.loadingProgress == 0)
        #expect(viewState.reloadRevision == 0)
        #expect(viewState.showsWebViewContent)
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)
        #expect(viewState.toolbar.shareURL == route.url)
        #expect(viewState.toolbar.isShareEnabled)
        #expect(viewState.bottomActions.isRefreshEnabled)
        #expect(viewState.bottomActions.openExternalBrowserURL == route.url)
        #expect(viewState.bottomActions.isOpenExternalBrowserEnabled)
    }

    @Test
    func webViewScreenStateTracksTitleLoadingProgressAndFailureIndependentlyFromView() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/webview-state-progress")!
        )
        var state = WebViewScreenState(route: route)

        state.applyNavigationStart()
        state.applyLoadingProgress(0.42)
        state.applyPageTitle("Loaded Article")

        var viewState = state.derivedViewState()
        #expect(viewState.primaryLoadingState?.title == "Loading Page")
        #expect(viewState.placeholder == nil)
        #expect(viewState.loadingProgress == 0.42)
        #expect(viewState.navigationTitle == "Loaded Article")
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)

        state.applyNavigationFinished()
        viewState = state.derivedViewState()
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.loadingProgress == 1)
        #expect(viewState.showsShareAction)
        #expect(viewState.showsBottomActions)

        state.applyNavigationFailure("The page could not be loaded.")
        viewState = state.derivedViewState()
        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder?.title == "Failed to Load Page")
        #expect(viewState.placeholder?.description == "The page could not be loaded.")
        #expect(viewState.showsWebViewContent == false)
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)
    }

    @Test
    func webViewScreenStateSwitchesShareAndBrowserActionsToCurrentPageURL() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/original")!
        )
        var state = WebViewScreenState(route: route)

        state.applyCurrentPageURL(URL(string: "https://example.com/articles/redirected")!)

        var viewState = state.derivedViewState()
        #expect(viewState.toolbar.shareURL?.absoluteString == "https://example.com/articles/redirected")
        #expect(
            viewState.bottomActions.openExternalBrowserURL?.absoluteString
                == "https://example.com/articles/redirected"
        )

        state.applyCurrentPageURL(URL(string: "mailto:hello@example.com")!)

        viewState = state.derivedViewState()
        #expect(viewState.toolbar.shareURL == nil)
        #expect(viewState.toolbar.isShareEnabled == false)
        #expect(viewState.bottomActions.openExternalBrowserURL == nil)
        #expect(viewState.bottomActions.isOpenExternalBrowserEnabled == false)
    }

    @Test
    func webViewScreenStateIncrementsReloadRevisionOnlyForSupportedURLs() {
        let supportedRoute = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "https://example.com/articles/webview-reload")!
        )
        var supportedState = WebViewScreenState(route: supportedRoute)

        supportedState.requestReload()

        #expect(supportedState.derivedViewState().reloadRevision == 1)

        let unsupportedRoute = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "mailto:hello@example.com")!
        )
        var unsupportedState = WebViewScreenState(route: unsupportedRoute)

        unsupportedState.requestReload()

        #expect(unsupportedState.derivedViewState().reloadRevision == 0)
    }

    @Test
    func webViewScreenStateStartsInFailurePhaseForUnsupportedInitialURL() {
        let route = ArticleWebViewRoute(
            articleID: UUID(),
            url: URL(string: "mailto:hello@example.com")!
        )
        let state = WebViewScreenState(route: route)
        let viewState = state.derivedViewState()

        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder?.title == "Failed to Load Page")
        #expect(
            viewState.placeholder?.description
                == "This article link can't be opened in the in-app browser."
        )
        #expect(viewState.navigationTitle == "Article")
        #expect(viewState.showsWebViewContent == false)
        #expect(viewState.showsShareAction == false)
        #expect(viewState.showsBottomActions == false)
        #expect(viewState.toolbar.shareURL == nil)
        #expect(viewState.toolbar.isShareEnabled == false)
        #expect(viewState.bottomActions.isRefreshEnabled == false)
        #expect(viewState.bottomActions.openExternalBrowserURL == nil)
        #expect(viewState.bottomActions.isOpenExternalBrowserEnabled == false)
    }
}
