import SwiftUI

struct ArticleListContentView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let sections: [ArticlesDaySection]
    let visibleArticleIDs: [UUID]
    @Binding var selection: UUID?
    @Binding var scrollPositionID: UUID?
    let refreshAction: @MainActor () async -> Void
    let toggleReadStatusAction: @MainActor (ArticleListItemDTO) -> Void
    let toggleStarredAction: @MainActor (ArticleListItemDTO) -> Void

    var body: some View {
        ZStack {
            appThemeVariant.primaryBackground
                .ignoresSafeArea()

            List(selection: $selection) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.articles, id: \.id) { article in
                            ArticleListRowView(article: article)
                                .id(article.id)
                                .tag(article.id)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    leadingSwipeActions(for: article)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    trailingSwipeActions(for: article)
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        ArticleListSectionHeaderView(title: section.title)
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .scrollPosition(id: $scrollPositionID)
            .contentMargins(.top, 8, for: .scrollContent)
            .animation(.snappy(duration: 0.24), value: visibleArticleIDs)
            .refreshable {
                await refreshAction()
            }
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
