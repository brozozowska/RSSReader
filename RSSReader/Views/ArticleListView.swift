import SwiftUI

struct ArticleListView: View {
    @Environment(\.appDependencies) private var dependencies
    let selectedFeedID: UUID?
    @Binding var selection: UUID?
    @State private var articles: [Article] = []
    @State private var hasLoadedArticles = false

    var body: some View {
        List(articles, id: \.id, selection: $selection) { article in
            Text(article.title)
        }
        .navigationTitle("Articles")
        .overlay {
            if hasLoadedArticles {
                if selectedFeedID == nil {
                    ContentUnavailableView(
                        "No Feed Selected",
                        systemImage: "sidebar.left",
                        description: Text("Select a feed in the sidebar to load its articles.")
                    )
                } else if articles.isEmpty {
                    ContentUnavailableView(
                        "No Articles",
                        systemImage: "newspaper",
                        description: Text("This feed has no stored articles yet.")
                    )
                }
            }
        }
        .task(id: selectedFeedID) {
            await loadArticles()
        }
    }

    @MainActor
    private func loadArticles() async {
        defer { hasLoadedArticles = true }

        guard
            let selectedFeedID,
            let articleRepository = dependencies.articleRepository
        else {
            articles = []
            selection = nil
            return
        }

        let sortMode = await loadSortMode()

        do {
            articles = try articleRepository.fetchArticles(feedID: selectedFeedID, sortMode: sortMode)
        } catch {
            dependencies.logger.error("Failed to load articles for feed \(selectedFeedID): \(error)")
            articles = []
        }

        if let selection, articles.contains(where: { $0.id == selection }) == false {
            self.selection = articles.first?.id
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
            ArticleListView(selectedFeedID: nil, selection: $selection)
        }
    }
    return PreviewContainer()
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
