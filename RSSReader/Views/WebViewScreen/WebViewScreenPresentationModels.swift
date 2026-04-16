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

    init(pageURL: URL?) {
        self.shareURL = pageURL
        self.isShareEnabled = pageURL != nil
    }
}

@MainActor
struct WebViewScreenBottomActionsState: Equatable {
    let isRefreshEnabled: Bool
    let openExternalBrowserURL: URL?
    let isOpenExternalBrowserEnabled: Bool

    init(
        pageURL: URL?,
        canRefreshPage: Bool,
        canOpenExternalBrowserURL: Bool
    ) {
        self.isRefreshEnabled = canRefreshPage
        self.openExternalBrowserURL = canOpenExternalBrowserURL ? pageURL : nil
        self.isOpenExternalBrowserEnabled = canOpenExternalBrowserURL
    }
}

@MainActor
struct WebViewScreenPrimaryLoadingState: Equatable {
    let title: String
}

@MainActor
struct WebViewScreenPlaceholderState: Equatable {
    let title: String
    let systemImage: String
    let description: String?
}

@MainActor
struct WebViewScreenDerivedViewState: Equatable {
    let initialURL: URL
    let navigationTitle: String
    let loadingProgress: Double
    let reloadRevision: Int
    let showsWebViewContent: Bool
    let showsShareAction: Bool
    let showsBottomActions: Bool
    let primaryLoadingState: WebViewScreenPrimaryLoadingState?
    let placeholder: WebViewScreenPlaceholderState?
    let toolbar: WebViewScreenToolbarState
    let bottomActions: WebViewScreenBottomActionsState
}
