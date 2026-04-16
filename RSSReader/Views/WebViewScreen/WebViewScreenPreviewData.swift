import SwiftUI

// MARK: - State Previews

#Preview("Loading") {
    WebViewScreenPreviewContainer(
        screenState: .previewLoading(
            route: WebViewScreenPreviewData.route,
            progress: 0.42
        )
    )
}

#Preview("Loaded") {
    WebViewScreenPreviewContainer(
        screenState: .previewLoaded(
            route: WebViewScreenPreviewData.route,
            title: "Example Article"
        )
    )
}

#Preview("Live Page") {
    NavigationStack {
        WebViewScreenView(
            route: WebViewScreenPreviewData.route,
            closeWebView: {}
        )
    }
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

// MARK: - Preview Container

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

// MARK: - Preview Data

private enum WebViewScreenPreviewData {
    static let route = ArticleWebViewRoute(
        articleID: UUID(),
        url: URL(string: "https://example.com")!
    )
}
