import Foundation

@MainActor
enum WebViewScreenPhase: Equatable {
    case initialLoading
    case loaded
    case failed(String)
}

@MainActor
struct WebViewScreenToolbarState: Equatable {
    let shareURL: URL?
    let isShareEnabled: Bool

    init(route: ArticleWebViewRoute, canSharePageURL: Bool) {
        self.shareURL = canSharePageURL ? route.url : nil
        self.isShareEnabled = canSharePageURL
    }
}

@MainActor
struct WebViewScreenBottomActionsState: Equatable {
    let openExternalBrowserURL: URL?
    let isOpenExternalBrowserEnabled: Bool

    init(route: ArticleWebViewRoute, canOpenExternalBrowserURL: Bool) {
        self.openExternalBrowserURL = canOpenExternalBrowserURL ? route.url : nil
        self.isOpenExternalBrowserEnabled = canOpenExternalBrowserURL
    }
}

@MainActor
struct WebViewScreenDerivedViewState: Equatable {
    let initialURL: URL
    let navigationTitle: String
    let phase: WebViewScreenPhase
    let loadingProgress: Double
    let showsWebViewContent: Bool
    let toolbar: WebViewScreenToolbarState
    let bottomActions: WebViewScreenBottomActionsState
}
