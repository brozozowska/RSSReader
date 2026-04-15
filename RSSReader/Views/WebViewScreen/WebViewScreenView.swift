import SwiftUI
import WebKit

enum WebViewScreenNavigationState {
    static func shouldCloseOnDrag(
        startLocationX: CGFloat,
        translation: CGSize
    ) -> Bool {
        startLocationX <= 32
            && translation.width >= 80
            && abs(translation.height) <= 48
    }
}

struct WebViewScreenView: View {
    @Environment(\.openURL) private var openURL

    let route: ArticleWebViewRoute
    let closeWebView: () -> Void
    let previewScreenState: WebViewScreenState?
    @State private var controller: WebViewScreenController

    init(
        route: ArticleWebViewRoute,
        closeWebView: @escaping () -> Void,
        previewScreenState: WebViewScreenState? = nil
    ) {
        self.route = route
        self.closeWebView = closeWebView
        self.previewScreenState = previewScreenState
        self._controller = State(
            initialValue: WebViewScreenController(
                route: route,
                previewScreenState: previewScreenState
            )
        )
    }

    var body: some View {
        let viewState = controller.screenState.derivedViewState()

        ZStack {
            if previewScreenState == nil, viewState.showsWebViewContent {
                ArticleWebView(
                    url: viewState.initialURL,
                    reloadRevision: viewState.reloadRevision,
                    onNavigationStarted: controller.handleNavigationStarted,
                    onLoadingProgressChanged: controller.handleLoadingProgressChanged,
                    onPageTitleChanged: controller.handlePageTitleChanged,
                    onNavigationFinished: controller.handleNavigationFinished,
                    onNavigationFailed: controller.handleNavigationFailed
                )
            } else if previewScreenState != nil {
                WebViewScreenPreviewSurface(url: viewState.initialURL)
            }

            if viewState.phase == .initialLoading {
                WebViewScreenLoadingOverlay(progress: viewState.loadingProgress)
            } else if case .failed(let message) = viewState.phase {
                WebViewScreenFailureOverlay(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle(viewState.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeWebView) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close Web View")
            }

            ToolbarItem(placement: .topBarTrailing) {
                WebViewScreenShareToolbarButton(toolbar: viewState.toolbar)
            }

            ToolbarItem(placement: .bottomBar) {
                WebViewScreenRefreshButton(
                    bottomActions: viewState.bottomActions,
                    refreshPage: controller.handleReloadRequested
                )
            }

            ToolbarSpacer(placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                WebViewScreenOpenExternalBrowserButton(
                    bottomActions: viewState.bottomActions,
                    openURL: openURL
                )
            }
        }
        .simultaneousGesture(closeGesture)
    }

    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard WebViewScreenNavigationState.shouldCloseOnDrag(
                    startLocationX: value.startLocation.x,
                    translation: value.translation
                ) else {
                    return
                }

                closeWebView()
            }
    }
}

private struct WebViewScreenShareToolbarButton: View {
    let toolbar: WebViewScreenToolbarState

    var body: some View {
        Group {
            if let shareURL = toolbar.shareURL {
                ShareLink(item: shareURL) {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .accessibilityLabel("Share Page")
        .disabled(toolbar.isShareEnabled == false)
    }
}

private struct WebViewScreenRefreshButton: View {
    let bottomActions: WebViewScreenBottomActionsState
    let refreshPage: () -> Void

    var body: some View {
        Button(action: refreshPage) {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(bottomActions.isRefreshEnabled == false)
        .accessibilityLabel("Reload Page")
    }
}

private struct WebViewScreenOpenExternalBrowserButton: View {
    let bottomActions: WebViewScreenBottomActionsState
    let openURL: OpenURLAction

    var body: some View {
        Button(action: openExternalBrowser) {
            Image(systemName: "safari")
        }
        .disabled(bottomActions.isOpenExternalBrowserEnabled == false)
        .accessibilityLabel("Open in External Browser")
    }

    private func openExternalBrowser() {
        guard let url = bottomActions.openExternalBrowserURL else {
            return
        }
        openURL(url)
    }
}

private struct WebViewScreenPreviewSurface: View {
    let url: URL

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.white, Color(.systemGray6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 18)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 18)
                    .frame(maxWidth: 240)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemGray6))
                    .frame(height: 220)

                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(height: 14)
                        .frame(maxWidth: index == 3 ? 220 : .infinity)
                }
            }
            .padding(20)
        }
    }
}

private struct WebViewScreenLoadingOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background.opacity(0.92))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                } else {
                    ProgressView()
                }

                Text("Loading Page")
                    .font(.headline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .transition(.opacity)
    }
}

private struct WebViewScreenFailureOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background.opacity(0.94))
                .ignoresSafeArea()

            ContentUnavailableView {
                Label("Failed to Load Page", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        }
        .transition(.opacity)
    }
}

private struct ArticleWebView: UIViewRepresentable {
    let url: URL
    let reloadRevision: Int
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
        // Reserve left-edge drags for dismissing the web detail back to the article screen.
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.attachObservers(to: webView)
        context.coordinator.lastReloadRevision = reloadRevision
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
            context.coordinator.lastReloadRevision = reloadRevision
            return
        }

        if context.coordinator.lastReloadRevision != reloadRevision {
            context.coordinator.lastReloadRevision = reloadRevision
            if webView.url == nil {
                webView.load(URLRequest(url: url))
            } else {
                webView.reload()
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigationStarted: () -> Void
        private let onLoadingProgressChanged: (Double) -> Void
        private let onPageTitleChanged: (String?) -> Void
        private let onNavigationFinished: () -> Void
        private let onNavigationFailed: (Error) -> Void
        private var estimatedProgressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        var lastReloadRevision: Int = 0

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
