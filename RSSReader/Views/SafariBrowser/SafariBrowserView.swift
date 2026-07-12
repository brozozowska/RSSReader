import SafariServices
import SwiftUI
import UIKit

struct SafariBrowserView: View {
    let route: ArticleSafariRoute
    let dismissSafari: () -> Void
    let backNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers
    private let safariPresentationConfiguration: ArticleSafariPresentationConfiguration = .standard

    init(
        route: ArticleSafariRoute,
        dismissSafari: @escaping () -> Void,
        backNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers = .inactive
    ) {
        self.route = route
        self.dismissSafari = dismissSafari
        self.backNavigationInteraction = backNavigationInteraction
    }

    var body: some View {
        if ArticleSafariRoute.canOpen(route.url) {
            ArticleSafariViewController(
                route: route,
                presentationConfiguration: safariPresentationConfiguration,
                onDismiss: dismissSafari,
                backNavigationInteraction: backNavigationInteraction
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
    let backNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDismiss: onDismiss,
            backNavigationInteraction: backNavigationInteraction
        )
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
        context.coordinator.installBackNavigationGesture(
            on: safariViewController.view,
            layoutDirection: context.environment.layoutDirection,
            backNavigationInteraction: backNavigationInteraction
        )
        return safariViewController
    }

    func updateUIViewController(
        _ safariViewController: SFSafariViewController,
        context: Context
    ) {
        context.coordinator.update(
            onDismiss: onDismiss,
            layoutDirection: context.environment.layoutDirection,
            backNavigationInteraction: backNavigationInteraction
        )
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate, UIGestureRecognizerDelegate {
        private var onDismiss: () -> Void
        private var backNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers
        private var layoutDirection: LayoutDirection = .leftToRight
        private weak var safariView: UIView?
        private lazy var backNavigationGesture: UIScreenEdgePanGestureRecognizer = {
            let gesture = UIScreenEdgePanGestureRecognizer(
                target: self,
                action: #selector(handleBackNavigationGesture(_:))
            )
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        init(
            onDismiss: @escaping () -> Void,
            backNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers
        ) {
            self.onDismiss = onDismiss
            self.backNavigationInteraction = backNavigationInteraction
        }

        func installBackNavigationGesture(
            on safariView: UIView,
            layoutDirection: LayoutDirection,
            backNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers
        ) {
            self.safariView = safariView
            update(
                onDismiss: onDismiss,
                layoutDirection: layoutDirection,
                backNavigationInteraction: backNavigationInteraction
            )
            safariView.addGestureRecognizer(backNavigationGesture)
        }

        func update(
            onDismiss: @escaping () -> Void,
            layoutDirection: LayoutDirection,
            backNavigationInteraction: SafariBrowserBackNavigationInteractionHandlers
        ) {
            self.onDismiss = onDismiss
            self.layoutDirection = layoutDirection
            self.backNavigationInteraction = backNavigationInteraction
            backNavigationGesture.edges = semanticLeadingEdge(for: layoutDirection)
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc
        private func handleBackNavigationGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard let safariView else { return }

            let translation = gesture.translation(in: safariView)
            let translationSize = CGSize(width: translation.x, height: translation.y)
            let startLocationX = gesture.location(in: safariView).x - translation.x

            switch gesture.state {
            case .began, .changed:
                backNavigationInteraction.update(
                    SafariBrowserNavigationState.dismissalProgress(
                        containerWidth: safariView.bounds.width,
                        layoutDirection: layoutDirection,
                        translation: translationSize
                    )
                )
            case .ended:
                if SafariBrowserNavigationState.shouldDismissSafariOnDrag(
                    startLocationX: startLocationX,
                    containerWidth: safariView.bounds.width,
                    layoutDirection: layoutDirection,
                    translation: translationSize
                ) {
                    backNavigationInteraction.finish()
                } else {
                    backNavigationInteraction.cancel()
                }
            case .cancelled, .failed:
                backNavigationInteraction.cancel()
            case .possible, .recognized:
                break
            @unknown default:
                backNavigationInteraction.cancel()
            }
        }

        private func semanticLeadingEdge(for layoutDirection: LayoutDirection) -> UIRectEdge {
            switch layoutDirection {
            case .leftToRight:
                .left
            case .rightToLeft:
                .right
            @unknown default:
                .left
            }
        }
    }
}

enum SafariBrowserNavigationState {
    private static let verticalTranslationTolerance: CGFloat = 48

    static func shouldDismissSafariOnDrag(
        startLocationX: CGFloat,
        containerWidth: CGFloat,
        layoutDirection: LayoutDirection,
        translation: CGSize
    ) -> Bool {
        CompactBackNavigationPolicy.shouldNavigateBackOnDrag(
            startLocationX: startLocationX,
            containerWidth: containerWidth,
            layoutDirection: layoutDirection,
            translation: translation
        )
    }

    static func dismissalProgress(
        containerWidth: CGFloat,
        layoutDirection: LayoutDirection,
        translation: CGSize
    ) -> CGFloat {
        guard containerWidth > 0 else { return 0 }
        guard abs(translation.height) <= verticalTranslationTolerance else { return 0 }

        let directionalTranslation: CGFloat
        switch layoutDirection {
        case .leftToRight:
            directionalTranslation = translation.width
        case .rightToLeft:
            directionalTranslation = -translation.width
        @unknown default:
            directionalTranslation = translation.width
        }

        return min(max(directionalTranslation / containerWidth, 0), 1)
    }
}

struct SafariBrowserBackNavigationInteractionHandlers {
    let update: (CGFloat) -> Void
    let cancel: () -> Void
    let finish: () -> Void

    static let inactive = SafariBrowserBackNavigationInteractionHandlers(
        update: { _ in },
        cancel: {},
        finish: {}
    )
}

private struct SafariUnsupportedURLView: View {
    let dismissSafari: () -> Void

    var body: some View {
        NavigationStack {
            ScreenPlaceholderView(
                title: ReadingLocalization.cannotOpenLinkTitle,
                systemImage: "exclamationmark.triangle",
                description: ReadingLocalization.cannotOpenLinkDescription
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ReadingLocalization.closeAction, action: dismissSafari)
                }
            }
        }
    }
}
