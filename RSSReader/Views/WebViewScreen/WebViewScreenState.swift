import Foundation

@MainActor
struct WebViewScreenState {
    let route: ArticleWebViewRoute
    private(set) var phase: WebViewScreenPhase = .initialLoading
    private(set) var pageTitle: String?
    private(set) var loadingProgress: Double = 0
    private(set) var pendingCommand: WebViewScreenCommand?
    private(set) var toolbar: WebViewScreenToolbarState
    private(set) var bottomActions: WebViewScreenBottomActionsState

    init(route: ArticleWebViewRoute) {
        self.route = route
        let canLoadInitialURL = route.url.isSupportedArticleWebViewURL
        self.toolbar = WebViewScreenToolbarState(
            route: route,
            canSharePageURL: canLoadInitialURL
        )
        self.bottomActions = WebViewScreenBottomActionsState(
            route: route,
            canOpenExternalBrowserURL: canLoadInitialURL
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

    mutating func applyNavigationFinished() {
        loadingProgress = 1
        phase = .loaded
    }

    mutating func applyNavigationFailure(_ message: String) {
        phase = .failed(message)
    }

    mutating func enqueueReloadCommand() {
        guard route.url.isSupportedArticleWebViewURL else {
            return
        }
        pendingCommand = .reload()
    }

    mutating func acknowledgeCommand(_ command: WebViewScreenCommand) {
        guard pendingCommand == command else {
            return
        }
        pendingCommand = nil
    }

    func derivedViewState() -> WebViewScreenDerivedViewState {
        WebViewScreenDerivedViewState(
            initialURL: route.url,
            navigationTitle: pageTitle ?? route.url.host ?? "Article",
            phase: phase,
            loadingProgress: loadingProgress,
            showsWebViewContent: route.url.isSupportedArticleWebViewURL && !phase.isFailed,
            pendingCommand: pendingCommand,
            toolbar: toolbar,
            bottomActions: bottomActions
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
