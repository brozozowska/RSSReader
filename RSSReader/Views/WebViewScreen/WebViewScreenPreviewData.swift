import SwiftUI

#Preview("Loading") {
    WebViewScreenPreviewContainer(
        screenState: .previewLoading(
            route: WebViewScreenPreviewData.route,
            progress: 0.42
        )
    )
}

#Preview("Loaded") {
    NavigationStack {
        WebViewScreenView(
            route: WebViewScreenPreviewData.route,
            closeWebView: {}
        )
    }
}

#Preview("Loaded State") {
    WebViewScreenPreviewContainer(
        screenState: .previewLoaded(
            route: WebViewScreenPreviewData.route,
            title: "Example Article"
        )
    )
}

#Preview("Failed") {
    WebViewScreenPreviewContainer(
        screenState: .previewFailed(
            route: WebViewScreenPreviewData.route,
            message: "The page could not be loaded.",
            title: "Example Article"
        )
    )
}

private struct WebViewScreenPreviewContainer: View {
    let screenState: WebViewScreenState

    var body: some View {
        NavigationStack {
            WebViewScreenView(
                route: screenState.route,
                closeWebView: {},
                previewScreenState: screenState
            )
        }
    }
}

private enum WebViewScreenPreviewData {
    static let route = ArticleWebViewRoute(
        articleID: UUID(),
        url: URL(string: "https://example.com")!
    )
}
