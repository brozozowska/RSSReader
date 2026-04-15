import Foundation

@MainActor
struct WebViewScreenState {
    let route: ArticleWebViewRoute
    private(set) var phase: WebViewScreenPhase = .initialLoading
    private(set) var pageTitle: String?
    private(set) var loadingProgress: Double = 0
    private(set) var toolbar: WebViewScreenToolbarState

    init(route: ArticleWebViewRoute) {
        self.route = route
        self.toolbar = WebViewScreenToolbarState(route: route)
    }

    mutating func applyNavigationStart() {
        phase = .initialLoading
    }

    mutating func applyLoadingProgress(_ progress: Double) {
        loadingProgress = min(max(progress, 0), 1)
    }

    mutating func applyPageTitle(_ title: String?) {
        pageTitle = title?.nilIfBlank
    }

    mutating func applyNavigationFinished() {
        loadingProgress = 1
        phase = .loaded
    }

    mutating func applyNavigationFailure(_ message: String) {
        phase = .failed(message)
    }

    func derivedViewState() -> WebViewScreenDerivedViewState {
        WebViewScreenDerivedViewState(
            initialURL: route.url,
            navigationTitle: pageTitle ?? route.url.host ?? "Article",
            phase: phase,
            loadingProgress: loadingProgress,
            toolbar: toolbar
        )
    }
}

extension WebViewScreenState {
    static func previewLoading(
        route: ArticleWebViewRoute,
        progress: Double = 0.35
    ) -> WebViewScreenState {
        var state = WebViewScreenState(route: route)
        state.applyNavigationStart()
        state.applyLoadingProgress(progress)
        return state
    }

    static func previewLoaded(
        route: ArticleWebViewRoute,
        title: String? = nil
    ) -> WebViewScreenState {
        var state = WebViewScreenState(route: route)
        state.applyPageTitle(title)
        state.applyNavigationFinished()
        return state
    }

    static func previewFailed(
        route: ArticleWebViewRoute,
        message: String,
        title: String? = nil
    ) -> WebViewScreenState {
        var state = WebViewScreenState(route: route)
        state.applyPageTitle(title)
        state.applyNavigationFailure(message)
        return state
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
