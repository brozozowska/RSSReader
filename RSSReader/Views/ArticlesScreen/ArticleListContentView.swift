import SwiftUI

struct ArticleListContentView: View {
    let sections: [ArticlesDaySection]
    @Binding var selection: UUID?
    let refreshAction: @MainActor () async -> Void
    let toggleReadStatusAction: @MainActor (ArticleListItemDTO) -> Void
    let toggleStarredAction: @MainActor (ArticleListItemDTO) -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            List(selection: $selection) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.articles, id: \.id) { article in
                            ArticleListRowView(article: article)
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
            .contentMargins(.top, 8, for: .scrollContent)
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
        .tint(.primary)
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
        .tint(.primary)
    }
}
