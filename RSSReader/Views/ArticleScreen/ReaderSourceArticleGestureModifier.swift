import SwiftUI

/// Uses the existing source-swipe policy and one simultaneous gesture. Native
/// Back, scroll gestures and Safari dismissal remain owned by the reading shell.
struct ReaderSourceArticleGestureModifier: ViewModifier {
    @Environment(\.layoutDirection) private var layoutDirection
    @Binding var containerWidth: CGFloat
    @State private var codeBlockInteractionFrames: [CGRect] = []
    let interaction: ReaderSourceArticleSafariInteractionHandlers
    let openingRequest: () -> ArticleSourceOpeningRequest?
    let openSourceArticle: () -> Void

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .onPreferenceChange(ReaderArticleCodeBlockFramesPreferenceKey.self) { codeBlockInteractionFrames = $0 }
            .simultaneousGesture(openSourceArticleGesture)
    }

    private var openSourceArticleGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                handleOpenSourceArticleDragChange(value)
            }
            .onEnded { value in
                handleOpenSourceArticleDragEnd(value)
            }
    }

    private func handleOpenSourceArticleDragChange(_ value: DragGesture.Value) {
        let progress = ArticleScreenNavigationState.openSourceArticleSwipeProgress(
            layoutDirection: layoutDirection,
            containerWidth: containerWidth,
            translation: value.translation,
            startLocation: value.startLocation,
            excludedSourceSwipeRegions: codeBlockInteractionFrames
        )
        guard progress > 0 else {
            interaction.cancel()
            return
        }

        guard case .inAppBrowser(let route) = openingRequest() else {
            return
        }

        interaction.update(route, progress)
    }

    private func handleOpenSourceArticleDragEnd(_ value: DragGesture.Value) {
        guard ArticleScreenNavigationState.shouldOpenSourceArticleOnDrag(
            layoutDirection: layoutDirection,
            containerWidth: containerWidth,
            translation: value.translation,
            startLocation: value.startLocation,
            excludedSourceSwipeRegions: codeBlockInteractionFrames
        ) else {
            interaction.cancel()
            return
        }

        openSourceArticle()
        interaction.finish()
    }
}
