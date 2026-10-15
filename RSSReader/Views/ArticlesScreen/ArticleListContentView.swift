import SwiftUI
import UIKit

struct ArticleListContentView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let sections: [ArticlesDaySection]
    let animationState: ArticleListAnimationState
    let customRefreshState: ArticlesScreenCustomRefreshState
    let canLoadNextPage: Bool
    let isLoadingNextPage: Bool
    var allowsArticleActions = true
    @Binding var selection: UUID?
    @Binding var scrollPositionID: UUID?
    let customRefreshPullProgressChanged: @MainActor (Double) -> Void
    let customRefreshReleaseAction: @MainActor () async -> Void
    let loadNextPageAction: @MainActor () async -> Void
    let toggleReadStatusAction: @MainActor (ArticleListItemDTO) -> Void
    let toggleStarredAction: @MainActor (ArticleListItemDTO) -> Void
    var scrollInteractionBegan: @MainActor () -> Void = {}
    @State private var latestPaginationGeometry = ArticleListPaginationGeometry()
    @State private var hasUserDrivenScrollDemand = false
    @State private var isOverscrollingTop = false
    @State private var isScrollInteracting = false

    var body: some View {
        ZStack {
            appThemeVariant.primaryBackground
                .ignoresSafeArea()

            articleList

            AppRefreshOverlay(state: customRefreshState.indicatorState)
        }
    }

    private var articleList: some View {
        List(selection: $selection) {
            articleSections
            paginationFooter
        }
        .disabled(allowsArticleActions == false)
        .listStyle(.plain)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .scrollPosition(id: $scrollPositionID)
        .scrollDismissesKeyboard(.immediately)
        .contentMargins(.top, 8, for: .scrollContent)
        .animation(animationState.animation(reduceMotion: accessibilityReduceMotion), value: animationState)
        .transaction { transaction in
            if accessibilityReduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onScrollGeometryChange(for: ArticleListScrollObservation.self) { geometry in
            ArticleListScrollObservation(
                offsetFromTop: geometry.contentOffset.y + geometry.contentInsets.top,
                paginationGeometry: ArticleListPaginationGeometry(
                    contentHeight: geometry.contentSize.height,
                    visibleMaxY: geometry.visibleRect.maxY
                )
            )
        } action: { _, newObservation in
            latestPaginationGeometry = newObservation.paginationGeometry
            isOverscrollingTop = newObservation.offsetFromTop < 0
            if isOverscrollingTop {
                hasUserDrivenScrollDemand = false
            } else if isScrollInteracting && newObservation.offsetFromTop > 0 {
                hasUserDrivenScrollDemand = true
            }
            requestNextPageIfNeeded()
        }
        .onScrollPhaseChange { _, newPhase, context in
            isScrollInteracting = newPhase == .interacting
            if isScrollInteracting {
                scrollInteractionBegan()
                if context.geometry.contentOffset.y + context.geometry.contentInsets.top > 0 {
                    hasUserDrivenScrollDemand = true
                }
            }

            requestNextPageIfNeeded()
            if newPhase == .idle {
                hasUserDrivenScrollDemand = false
            }
        }
        .background {
            AppRefreshScrollGestureBridge(
                isEnabled: allowsArticleActions,
                isRefreshing: customRefreshState.phase == .refreshing,
                pullProgressChanged: customRefreshPullProgressChanged,
                releaseAction: {
                    Task {
                        await customRefreshReleaseAction()
                    }
                }
            )
        }
        .onDisappear {
            isScrollInteracting = false
            hasUserDrivenScrollDemand = false
        }
    }

    @ViewBuilder
    private var articleSections: some View {
        ForEach(sections) { section in
            Section {
                ForEach(section.articles, id: \.id) { article in
                    articleRow(article)
                }
            } header: {
                ArticleListSectionHeaderView(title: section.title)
            }
            .textCase(nil)
        }
    }

    private func articleRow(_ article: ArticleListItemDTO) -> some View {
        ArticleListRowView(article: article)
            .id(article.id)
            .tag(article.id)
            .swipeActions(edge: ArticleRowSwipeActionsState.readStatusEdge, allowsFullSwipe: true) {
                leadingSwipeActions(for: article)
            }
            .swipeActions(edge: ArticleRowSwipeActionsState.starredStatusEdge, allowsFullSwipe: true) {
                trailingSwipeActions(for: article)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func requestNextPageIfNeeded() {
        guard ArticleListPaginationPrefetchPolicy.shouldRequestNextPage(
            geometry: latestPaginationGeometry,
            hasUserDrivenScrollDemand: hasUserDrivenScrollDemand,
            canLoadNextPage: canLoadNextPage,
            isRefreshInteractionActive: isOverscrollingTop || customRefreshState.showsIndicator
        ) else {
            return
        }

        Task {
            await loadNextPageAction()
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if isLoadingNextPage {
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func leadingSwipeActions(for article: ArticleListItemDTO) -> some View {
        let swipeActionsState = ArticleRowSwipeActionsState(article: article)

        Button {
            Task {
                toggleReadStatusAction(article)
            }
        } label: {
            Label {
                Text(swipeActionsState.readActionTitle)
            } icon: {
                swipeActionImage(systemName: swipeActionsState.readActionSystemImage)
            }
        }
        .labelStyle(.iconOnly)
        .tint(.clear)
        .accessibilityLabel(swipeActionsState.readActionTitle)
    }

    @ViewBuilder
    private func trailingSwipeActions(for article: ArticleListItemDTO) -> some View {
        let swipeActionsState = ArticleRowSwipeActionsState(article: article)

        Button {
            Task {
                toggleStarredAction(article)
            }
        } label: {
            Label {
                Text(swipeActionsState.starActionTitle)
            } icon: {
                swipeActionImage(systemName: swipeActionsState.starActionSystemImage)
            }
        }
        .labelStyle(.iconOnly)
        .tint(.clear)
        .accessibilityLabel(swipeActionsState.starActionTitle)
    }

    @ViewBuilder
    private func swipeActionImage(systemName: String) -> some View {
        let color: UIColor = appThemeVariant == .light ? .black : .white
        if let image = UIImage(systemName: systemName) {
            Image(uiImage: image.withTintColor(color, renderingMode: .alwaysOriginal))
                .renderingMode(.original)
                .environment(\.symbolVariants, .none)
        }
    }
}

private struct ArticleListScrollObservation: Equatable {
    let offsetFromTop: CGFloat
    let paginationGeometry: ArticleListPaginationGeometry
}
