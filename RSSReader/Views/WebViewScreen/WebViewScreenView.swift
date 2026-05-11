import SafariServices
import SwiftUI

struct WebViewScreenView: View {
    let route: ArticleSafariRoute
    let closeWebView: () -> Void
    let previewScreenState: WebViewScreenState?
    private let safariPresentationConfiguration: ArticleSafariPresentationConfiguration = .standard

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
                presentationConfiguration: safariPresentationConfiguration,
                onDismiss: closeWebView
            )
            .ignoresSafeArea()
        } else {
            SafariUnsupportedURLView(closeWebView: closeWebView)
        }
    }
}

struct ArticleSafariPresentationConfiguration: Equatable {
    let dismissButtonStyle: SFSafariViewController.DismissButtonStyle
    let barCollapsingEnabled: Bool

    static let standard = ArticleSafariPresentationConfiguration(
        dismissButtonStyle: .close,
        barCollapsingEnabled: true
    )
}

private struct ArticleSafariViewController: UIViewControllerRepresentable {
    let route: ArticleSafariRoute
    let presentationConfiguration: ArticleSafariPresentationConfiguration
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = presentationConfiguration.barCollapsingEnabled

        let safariViewController = SFSafariViewController(
            url: route.url,
            configuration: configuration
        )
        safariViewController.dismissButtonStyle = presentationConfiguration.dismissButtonStyle
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
