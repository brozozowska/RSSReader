import SwiftUI

struct ArticleListContentView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let sections: [ArticlesDaySection]
    let visibleArticleIDs: [UUID]
    let customRefreshState: ArticlesScreenCustomRefreshState
    @Binding var selection: UUID?
    @Binding var scrollPositionID: UUID?
    let customRefreshPullProgressChanged: @MainActor (Double) -> Void
    let customRefreshReleaseAction: @MainActor () async -> Void
    let toggleReadStatusAction: @MainActor (ArticleListItemDTO) -> Void
    let toggleStarredAction: @MainActor (ArticleListItemDTO) -> Void

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
        }
        .listStyle(.plain)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .scrollPosition(id: $scrollPositionID)
        .contentMargins(.top, 8, for: .scrollContent)
        .animation(.snappy(duration: 0.24), value: visibleArticleIDs)
        .onScrollGeometryChange(for: ArticleListCustomRefreshGeometry.self) { geometry in
            ArticleListCustomRefreshGeometry(
                contentOffsetY: geometry.contentOffset.y,
                contentInsetTop: geometry.contentInsets.top
            )
        } action: { _, newGeometry in
            let progress = ArticleListCustomRefreshPullPolicy.progress(for: newGeometry)
            customRefreshPullProgressChanged(progress)
        }
        .onScrollPhaseChange { oldPhase, newPhase, _ in
            guard ArticleListCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: oldPhase == .interacting,
                isInteracting: newPhase == .interacting,
                customRefreshState: customRefreshState
            ) else {
                return
            }

            Task {
                await customRefreshReleaseAction()
            }
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
