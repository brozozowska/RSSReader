import Foundation

@MainActor
struct WebViewScreenState {
    let route: ArticleWebViewRoute
    private(set) var phase: WebViewScreenPhase = .initialLoading
    private(set) var currentPageURL: URL?
    private(set) var pageTitle: String?
    private(set) var loadingProgress: Double = 0
    private(set) var reloadRevision: Int = 0
    private(set) var toolbar: WebViewScreenToolbarState
    private(set) var bottomActions: WebViewScreenBottomActionsState

    init(route: ArticleWebViewRoute) {
        self.route = route
        let canLoadInitialURL = route.url.isSupportedArticleWebViewURL
        self.currentPageURL = canLoadInitialURL ? route.url : nil
        self.toolbar = WebViewScreenToolbarState(pageURL: currentPageURL)
        self.bottomActions = WebViewScreenBottomActionsState(
            pageURL: currentPageURL,
            canRefreshPage: canLoadInitialURL,
            canOpenExternalBrowserURL: currentPageURL != nil
        )
        if !canLoadInitialURL {
            self.phase = .failed("This article link can't be opened in the in-app browser.")
        }
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

    mutating func applyCurrentPageURL(_ url: URL?) {
        guard let url else {
            return
        }
        currentPageURL = url.isSupportedArticleWebViewURL ? url : nil
        updateActionAvailability()
    }

    mutating func applyNavigationFinished() {
        loadingProgress = 1
        phase = .loaded
    }

    mutating func applyNavigationFailure(_ message: String) {
        phase = .failed(message)
    }

    mutating func requestReload() {
        guard route.url.isSupportedArticleWebViewURL else {
            return
        }
        reloadRevision += 1
    }

    func derivedViewState() -> WebViewScreenDerivedViewState {
        let showsBrowserActions = phase == .loaded && currentPageURL != nil

        return WebViewScreenDerivedViewState(
            initialURL: route.url,
            navigationTitle: pageTitle ?? currentPageURL?.host ?? route.url.host ?? "Article",
            loadingProgress: loadingProgress,
            reloadRevision: reloadRevision,
            showsWebViewContent: route.url.isSupportedArticleWebViewURL && !phase.isFailed,
            showsShareAction: showsBrowserActions,
            showsBottomActions: showsBrowserActions,
            primaryLoadingState: primaryLoadingState,
            placeholder: placeholder,
            toolbar: toolbar,
            bottomActions: bottomActions
        )
    }
}

private extension WebViewScreenState {
    mutating func updateActionAvailability() {
        toolbar = WebViewScreenToolbarState(pageURL: currentPageURL)
        bottomActions = WebViewScreenBottomActionsState(
            pageURL: currentPageURL,
            canRefreshPage: route.url.isSupportedArticleWebViewURL,
            canOpenExternalBrowserURL: currentPageURL != nil
        )
    }

    var primaryLoadingState: WebViewScreenPrimaryLoadingState? {
        guard phase == .initialLoading else {
            return nil
        }

        return WebViewScreenPrimaryLoadingState(title: "Loading Page")
    }

    var placeholder: WebViewScreenPlaceholderState? {
        guard case .failed(let message) = phase else {
            return nil
        }

        return WebViewScreenPlaceholderState(
            title: "Failed to Load Page",
            systemImage: "exclamationmark.triangle",
            description: message
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

private extension URL {
    var isSupportedArticleWebViewURL: Bool {
        guard let scheme else {
            return false
        }
        let normalizedScheme = scheme.lowercased()
        guard normalizedScheme == "http" || normalizedScheme == "https" else {
            return false
        }
        return host?.isEmpty == false
    }
}

private extension WebViewScreenPhase {
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
