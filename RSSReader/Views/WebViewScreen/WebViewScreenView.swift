import SwiftUI

struct WebViewScreenView: View {
    let route: ArticleWebViewRoute
    let closeWebView: () -> Void

    var body: some View {
        ContentUnavailableView(
            "Web View Screen",
            systemImage: "globe",
            description: Text(route.url.absoluteString)
        )
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeWebView) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close Web View")
            }
        }
    }
}

#Preview {
    NavigationStack {
        WebViewScreenView(
            route: ArticleWebViewRoute(
                articleID: UUID(),
                url: URL(string: "https://example.com/articles/webview-preview")!
            ),
            closeWebView: {}
        )
    }
}
