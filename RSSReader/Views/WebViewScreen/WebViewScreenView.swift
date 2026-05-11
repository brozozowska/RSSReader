import SafariServices
import SwiftUI

struct WebViewScreenView: View {
    let route: ArticleSafariRoute
    let closeWebView: () -> Void
    let previewScreenState: WebViewScreenState?

    init(
        route: ArticleSafariRoute,
        closeWebView: @escaping () -> Void,
        previewScreenState: WebViewScreenState? = nil
    ) {
        self.route = route
        self.closeWebView = closeWebView
        self.previewScreenState = previewScreenState
    }

    var body: some View {
        if ArticleSafariRoute.canOpen(route.url) {
            ArticleSafariViewController(
                route: route,
                dismissButtonStyle: .close,
                barCollapsingEnabled: true,
                onDismiss: closeWebView
            )
            .ignoresSafeArea()
        } else {
            SafariUnsupportedURLView(closeWebView: closeWebView)
        }
    }
}

private struct ArticleSafariViewController: UIViewControllerRepresentable {
    let route: ArticleSafariRoute
    let dismissButtonStyle: SFSafariViewController.DismissButtonStyle
    let barCollapsingEnabled: Bool
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = barCollapsingEnabled

        let safariViewController = SFSafariViewController(
            url: route.url,
            configuration: configuration
        )
        safariViewController.dismissButtonStyle = dismissButtonStyle
        safariViewController.delegate = context.coordinator
        return safariViewController
    }

    func updateUIViewController(
        _ safariViewController: SFSafariViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}

private struct SafariUnsupportedURLView: View {
    let closeWebView: () -> Void

    var body: some View {
        NavigationStack {
            ScreenPlaceholderView(
                title: "Cannot Open Link",
                systemImage: "exclamationmark.triangle",
                description: "This article link can't be opened in the in-app browser."
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: closeWebView)
                }
            }
        }
    }
}
