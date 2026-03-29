import SwiftUI

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    let selectedSidebarSelection: SidebarSelection?
    @Binding var selection: UUID?
    @State private var articles: [ArticleListItemDTO] = []
    @State private var hasLoadedArticles = false

    var body: some View {
        List(articles, id: \.id, selection: $selection) { article in
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.body.weight(article.isRead ? .regular : .semibold))

                if let summary = article.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .navigationTitle("Articles")
        .overlay {
            if hasLoadedArticles {
                if selectedSidebarSelection == nil {
                    ContentUnavailableView(
                        "No Source Selected",
                        systemImage: "sidebar.left",
                        description: Text("Select Inbox or a feed in the sidebar to load articles.")
                    )
                } else if articles.isEmpty {
                    ContentUnavailableView(
                        "No Articles",
                        systemImage: "newspaper",
                        description: Text(emptyStateDescription)
                    )
                }
            }
        }
        .task(id: selectedSidebarSelection) {
            await loadArticles()
        }
    }

    @MainActor
    private func loadArticles() async {
        defer { hasLoadedArticles = true }

        guard let articleQueryService = dependencies.articleQueryService else {
            articles = []
            selection = nil
            return
        }

        let sortMode = await loadSortMode()

        do {
            switch selectedSidebarSelection {
            case .inbox:
                articles = try articleQueryService.fetchInboxListItems(sortMode: sortMode)
            case .feed(let selectedFeedID):
                articles = try articleQueryService.fetchArticleListItems(feedID: selectedFeedID, sortMode: sortMode)
            case .none:
                articles = []
            }
        } catch {
            dependencies.logger.error("Failed to load article list for selection \(String(describing: selectedSidebarSelection)): \(error)")
            articles = []
        }

        if let selection, articles.contains(where: { $0.id == selection }) == false {
            self.selection = articles.first?.id
        }
    }

    private var emptyStateDescription: String {
        switch selectedSidebarSelection {
        case .inbox:
            "Your global inbox has no stored articles yet."
        case .feed:
            "This feed has no stored articles yet."
        case .none:
            "Select Inbox or a feed in the sidebar to load articles."
        }
    }

    @MainActor
    private func loadSortMode() async -> ArticleSortMode {
        guard let appSettingsRepository = dependencies.appSettingsRepository else {
            return .publishedAtDescending
        }

        do {
            return try appSettingsRepository.fetchOrCreate().sortMode
        } catch {
            dependencies.logger.error("Failed to load app settings for article sort mode: \(error)")
            return .publishedAtDescending
        }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var selection: UUID? = nil
        var body: some View {
            ArticleListView(selectedSidebarSelection: .inbox, selection: $selection)
        }
    }
    return PreviewContainer()
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
