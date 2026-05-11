import SafariServices
import SwiftUI

struct SafariBrowserView: View {
    let route: ArticleSafariRoute
    let dismissSafari: () -> Void
    private let safariPresentationConfiguration: ArticleSafariPresentationConfiguration = .standard

    init(
        route: ArticleSafariRoute,
        dismissSafari: @escaping () -> Void
    ) {
        self.route = route
        self.dismissSafari = dismissSafari
    }

    var body: some View {
        if ArticleSafariRoute.canOpen(route.url) {
            ArticleSafariViewController(
                route: route,
                presentationConfiguration: safariPresentationConfiguration,
                onDismiss: dismissSafari
            )
            .ignoresSafeArea()
        } else {
            SafariUnsupportedURLView(dismissSafari: dismissSafari)
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
    let dismissSafari: () -> Void

    var body: some View {
        NavigationStack {
            ScreenPlaceholderView(
                title: "Cannot Open Link",
                systemImage: "exclamationmark.triangle",
                description: "This article link can't be opened in the in-app browser."
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: dismissSafari)
                }
            }
        }
    }
}
