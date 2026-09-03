import SwiftUI

struct ReaderArticleContentSurface: View {
    let viewState: ArticleScreenDerivedViewState
    let contentSafeAreaInsets: EdgeInsets
    let actionHandlers: ArticleScreenActionHandlers
    let onScrollGeometryChange: (ReaderArticleScrollGeometry) -> Void
    let onScrollPhaseChange: (ScrollPhase, ScrollPhase) -> Void

    var body: some View {
        Group {
            if let content = viewState.content {
                ScrollView {
                    ReaderArticleContentView(
                        content: content,
                        actionHandlers: actionHandlers
                    )
                    .padding(.horizontal, ReaderChromeUnderlayLayout.contentMargin)
                    .padding(.top, contentSafeAreaInsets.top + ReaderChromeUnderlayLayout.contentMargin)
                    .padding(.bottom, contentSafeAreaInsets.bottom + ReaderChromeUnderlayLayout.contentMargin)
                }
                .scrollEdgeEffectHidden(true, for: .vertical)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .onScrollGeometryChange(for: ReaderArticleScrollGeometry.self) { geometry in
                    ReaderArticleScrollGeometry(
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height,
                        contentOffsetY: geometry.contentOffset.y,
                        contentInsetTop: geometry.contentInsets.top,
                        contentInsetBottom: geometry.contentInsets.bottom,
                        boundsMaxY: geometry.bounds.maxY
                    )
                } action: { _, newGeometry in
                    onScrollGeometryChange(newGeometry)
                }
                .onScrollPhaseChange { oldPhase, newPhase, _ in
                    onScrollPhaseChange(oldPhase, newPhase)
                }
            } else if let primaryLoadingState = viewState.primaryLoadingState {
                ScreenLoadingView(title: primaryLoadingState.title)
            } else if let placeholder = viewState.placeholder {
                ScreenPlaceholderView(
                    title: placeholder.title,
                    systemImage: placeholder.systemImage,
                    description: placeholder.description
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
