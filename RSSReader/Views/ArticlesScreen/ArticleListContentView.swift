import SwiftUI

struct ArticleListContentView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let sections: [ArticlesDaySection]
    let animationState: ArticleListAnimationState
    let customRefreshState: ArticlesScreenCustomRefreshState
    let canLoadNextPage: Bool
    let isLoadingNextPage: Bool
    @Binding var selection: UUID?
    @Binding var scrollPositionID: UUID?
    let customRefreshPullProgressChanged: @MainActor (Double) -> Void
    let customRefreshReleaseAction: @MainActor () async -> Void
    let loadNextPageAction: @MainActor () async -> Void
    let toggleReadStatusAction: @MainActor (ArticleListItemDTO) -> Void
    let toggleStarredAction: @MainActor (ArticleListItemDTO) -> Void
    @State private var latestPaginationGeometry = ArticleListPaginationGeometry()
    @State private var hasUserDrivenScrollDemand = false

    var body: some View {
        ZStack {
            appThemeVariant.primaryBackground
                .ignoresSafeArea()

            articleList

            customRefreshIndicator
        }
    }

    private var articleList: some View {
        List(selection: $selection) {
            articleSections
            paginationFooter
        }
        .listStyle(.plain)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .scrollPosition(id: $scrollPositionID)
        .contentMargins(.top, 8, for: .scrollContent)
        .animation(listAnimation, value: animationState)
        .onScrollGeometryChange(for: ArticleListScrollObservation.self) { geometry in
            ArticleListScrollObservation(
                refreshGeometry: ArticleListCustomRefreshGeometry(
                    contentOffsetY: geometry.contentOffset.y,
                    contentInsetTop: geometry.contentInsets.top
                ),
                paginationGeometry: ArticleListPaginationGeometry(
                    contentHeight: geometry.contentSize.height,
                    visibleMaxY: geometry.visibleRect.maxY
                )
            )
        } action: { _, newObservation in
            latestPaginationGeometry = newObservation.paginationGeometry
            let progress = ArticleListCustomRefreshPullPolicy.progress(
                for: newObservation.refreshGeometry
            )
            customRefreshPullProgressChanged(progress)
            requestNextPageIfNeeded()
        }
        .onScrollPhaseChange { oldPhase, newPhase, _ in
            if newPhase == .tracking || newPhase == .interacting {
                hasUserDrivenScrollDemand = true
            }

            if ArticleListCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: oldPhase == .interacting,
                isInteracting: newPhase == .interacting,
                customRefreshState: customRefreshState
            ) {
                Task {
                    await customRefreshReleaseAction()
                }
            }

            requestNextPageIfNeeded()
            if newPhase == .idle {
                hasUserDrivenScrollDemand = false
            }
        }
        .onDisappear {
            hasUserDrivenScrollDemand = false
        }
    }

    private var listAnimation: Animation? {
        guard animationState.allowsAnimation(reduceMotion: accessibilityReduceMotion) else {
            return nil
        }

        return .snappy(duration: 0.24)
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
            canLoadNextPage: canLoadNextPage
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
    private var customRefreshIndicator: some View {
        if customRefreshState.showsIndicator {
            VStack {
                AppRefreshIndicator(
                    state: customRefreshState.indicatorState,
                    size: 24,
                    lineWidth: 2.5
                )
                .padding(.top, 14)

                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.opacity)
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
            Label(
                swipeActionsState.readActionTitle,
                systemImage: swipeActionsState.readActionSystemImage
            )
        }
        .tint(.gray)
    }

    @ViewBuilder
    private func trailingSwipeActions(for article: ArticleListItemDTO) -> some View {
        let swipeActionsState = ArticleRowSwipeActionsState(article: article)

        Button {
            Task {
                toggleStarredAction(article)
            }
        } label: {
            Label(swipeActionsState.starActionTitle, systemImage: swipeActionsState.starActionSystemImage)
        }
        .tint(.gray)
    }
}

private struct ArticleListScrollObservation: Equatable {
    let refreshGeometry: ArticleListCustomRefreshGeometry
    let paginationGeometry: ArticleListPaginationGeometry
}
