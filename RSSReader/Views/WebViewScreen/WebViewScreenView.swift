import SwiftUI
import WebKit

struct WebViewScreenView: View {
    let route: ArticleWebViewRoute
    let closeWebView: () -> Void
    @State private var controller: WebViewScreenController

    init(
        route: ArticleWebViewRoute,
        closeWebView: @escaping () -> Void
    ) {
        self.route = route
        self.closeWebView = closeWebView
        self._controller = State(initialValue: WebViewScreenController(route: route))
    }

    var body: some View {
        let viewState = controller.screenState.derivedViewState()

        ArticleWebView(
            url: viewState.initialURL,
            onNavigationStarted: controller.handleNavigationStarted,
            onLoadingProgressChanged: controller.handleLoadingProgressChanged,
            onPageTitleChanged: controller.handlePageTitleChanged,
            onNavigationFinished: controller.handleNavigationFinished,
            onNavigationFailed: controller.handleNavigationFailed
        )
            .toolbarTitleDisplayMode(.inline)
            .navigationTitle(viewState.navigationTitle)
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
    let onNavigationStarted: () -> Void
    let onLoadingProgressChanged: (Double) -> Void
    let onPageTitleChanged: (String?) -> Void
    let onNavigationFinished: () -> Void
    let onNavigationFailed: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigationStarted: onNavigationStarted,
            onLoadingProgressChanged: onLoadingProgressChanged,
            onPageTitleChanged: onPageTitleChanged,
            onNavigationFinished: onNavigationFinished,
            onNavigationFailed: onNavigationFailed
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.attachObservers(to: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigationStarted: () -> Void
        private let onLoadingProgressChanged: (Double) -> Void
        private let onPageTitleChanged: (String?) -> Void
        private let onNavigationFinished: () -> Void
        private let onNavigationFailed: (Error) -> Void
        private var estimatedProgressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?

        init(
            onNavigationStarted: @escaping () -> Void,
            onLoadingProgressChanged: @escaping (Double) -> Void,
            onPageTitleChanged: @escaping (String?) -> Void,
            onNavigationFinished: @escaping () -> Void,
            onNavigationFailed: @escaping (Error) -> Void
        ) {
            self.onNavigationStarted = onNavigationStarted
            self.onLoadingProgressChanged = onLoadingProgressChanged
            self.onPageTitleChanged = onPageTitleChanged
            self.onNavigationFinished = onNavigationFinished
            self.onNavigationFailed = onNavigationFailed
        }

        func attachObservers(to webView: WKWebView) {
            estimatedProgressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                self?.onLoadingProgressChanged(webView.estimatedProgress)
            }
            titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                self?.onPageTitleChanged(webView.title)
            }
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            onNavigationStarted()
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            onNavigationFinished()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            onNavigationFailed(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onNavigationFailed(error)
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
