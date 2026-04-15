import SwiftUI
import WebKit

struct WebViewScreenView: View {
    let route: ArticleWebViewRoute
    let closeWebView: () -> Void

    var body: some View {
        ArticleWebView(url: route.url)
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

private struct ArticleWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
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
